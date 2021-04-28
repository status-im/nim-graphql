# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  std/[uri],
  faststreams/inputs,
  stew/results, chronicles,
  chronos, httputils, chronos/apps/http/httpcommon,
  ./common/[ast, names, response, types, errors],
  ./builtin/json_respstream, ./common_parser, ./lexer

type
  ContentType = enum
    ctGraphQl = "application/graphql"
    ctJson    = "application/json"

  VarPair = object
    name: string
    value: Node

  ParseResult* = Result[void, ErrorDesc]

  ClientResp* = object
    code*: int # HTTP code
    response*: string

  ClientResult* = Result[ClientResp, string]

  GraphqlHttpClientRef* = ref GraphqlHttpClientObj
  GraphqlHttpClientObj* = object of RootObj
    opName        : string
    varTable      : seq[VarPair]
    names         : NameCache
    meth          : HttpMethod
    address       : TransportAddress
    uri           : Uri
    contentType   : ContentType
    bodyTimeout   : Duration
    headersTimeout: Duration

const
  HttpBodyTimeout = 12.seconds
  HttpHeadersTimeout = 120.seconds

proc init*(ctx: GraphqlHttpClientRef,
           address: TransportAddress,
           uri: Uri,
           meth: HttpMethod,
           contentType: ContentType,
           bodyTimeout: Duration,
           headersTimeout: Duration) =
  ctx.names = newNameCache()
  ctx.varTable = @[]
  ctx.address = address
  ctx.meth = meth
  ctx.uri = uri
  ctx.contentType = contentType
  ctx.bodyTimeout = bodyTimeout
  ctx.headersTimeout = headersTimeout

proc new*(_: type GraphqlHttpClientRef,
          address: TransportAddress,
          url: string = "/graphql",
          meth: HttpMethod = MethodPost,
          contentType: ContentType = ctJson,
          bodyTimeout: Duration = HttpBodyTimeout,
          headersTimeout: Duration = HttpHeadersTimeout): GraphqlHttpClientRef =
  result = GraphqlHttpClientRef()
  result.init(address,
    parseUri(url),
    meth,
    contentType,
    bodyTimeout,
    headersTimeout)

proc addVar*(ctx: GraphqlHttpClientRef, name: string, val: int) =
  ctx.varTable.add VarPair(name: name, value: resp(val))

proc addVar*(ctx: GraphqlHttpClientRef, name: string, val: string) =
  ctx.varTable.add VarPair(name: name, value: resp(val))

proc addVar*(ctx: GraphqlHttpClientRef, name: string, val: float64) =
  ctx.varTable.add VarPair(name: name, value: resp(val))

proc addVar*(ctx: GraphqlHttpClientRef, name: string, val: bool) =
  ctx.varTable.add VarPair(name: name, value: resp(val))

proc addVar*(ctx: GraphqlHttpClientRef, name: string) =
  ctx.varTable.add VarPair(name: name, value: respNull())

proc addEnumVar*(ctx: GraphqlHttpClientRef, name: string, val: string) =
  ctx.varTable.add VarPair(name: name,
    value: Node(kind: nkEnum, pos: Pos(), name: ctx.names.insert(val))
  )

proc parseVars(ctx: GraphqlHttpClientRef, input: InputStream): ParseResult  =
  var parser = Parser.init(input, ctx.names)
  parser.lex.next()
  if parser.lex.tok == tokEof:
    return ok()

  var values: Node
  parser.rgReset(rgValueLiteral) # recursion guard
  parser.valueLiteral(isConst = true, values)
  if parser.error != errNone:
    return err(parser.err)

  for n in values:
    ctx.varTable.add VarPair(name: $n[0].name, value: n[1])

  ok()

proc parseVars*(ctx: GraphqlHttpClientRef, input: string): ParseResult  {.gcsafe.} =
  {.gcsafe.}:
    var stream = unsafeMemoryInput(input)
    ctx.parseVars(stream)

proc parseVars*(ctx: GraphqlHttpClientRef, input: openArray[byte]): ParseResult  {.gcsafe.} =
  {.gcsafe.}:
    var stream = unsafeMemoryInput(input)
    ctx.parseVars(stream)

proc operationName*(ctx: GraphqlHttpClientRef, name: string) =
  ctx.opName = name

proc clearVariables*(ctx: GraphqlHttpClientRef) =
  ctx.varTable.setLen(0)

proc clearAll*(ctx: GraphqlHttpClientRef) =
  ctx.varTable.setLen(0)
  ctx.opName = ""

proc sendRequest*(ctx: GraphqlHttpClientRef, query: string): Future[ClientResult] {.async.} =
  # TODO: implement GET method
  # TODO: implement content-type: graphql

  var r = JsonRespStream.new()
  respMap(r):
    r.fieldName("query")
    r.write(query)
    r.fieldName("operationName")
    r.write(ctx.opName)
    r.fieldName("variables")
    respMap(r):
      for n in ctx.varTable:
        r.fieldName(n.name)
        serialize(n.value, r)

  let body = r.getString()
  var request = $ctx.meth & " " & $ctx.uri & " HTTP/1.0\r\n"
  request.add("Host: " & $ctx.address & "\r\n")
  request.add("Content-Length: " & $len(body) & "\r\n")
  request.add("Content-Type: " & $ctx.contentType & "\r\n")
  request.add("\r\n")
  request.add(body)

  let transp = await connect(ctx.address)
  let res {.used.} = await transp.write(request)

  var headersBuf = newSeq[byte](4096)
  let rlenFut = transp.readUntil(addr headersBuf[0], len(headersBuf),
                                    HeadersMark)
  let hres = await withTimeout(rlenFut, ctx.headersTimeout)
  if not hres:
    debug "Timeout expired while receiving headers",
              address = transp.remoteAddress()
    return err("headers timeout")

  let rLen = rlenFut.read()
  headersBuf.setLen(rLen)

  let resp = parseResponse(headersBuf, true)
  if not resp.success():
    return err("parse header error")

  let length = resp.contentLength()
  let cresp =
    if length > 0:
      var dataBuf = newString(length)
      let dataFut = transp.readExactly(addr dataBuf[0], len(dataBuf))
      let dres = await withTimeout(dataFut, ctx.bodyTimeout)
      if not dres:
        debug "Timeout expired while receiving response body",
              address = transp.remoteAddress()
        return err("response body timeout")
      dataFut.read()
      ok(ClientResp(code: resp.code, response: dataBuf))
    else:
      ok(ClientResp(code: resp.code, response: ""))
  await transp.closeWait()
  return cresp
