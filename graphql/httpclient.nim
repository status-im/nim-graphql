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
  stew/results, chronicles,
  chronos, httputils,
  chronos/apps/http/httpcommon,
  ./builtin/json_respstream

type
  VarPair = object
    name: string
    value: string

  VarTable = seq[VarPair]

  ContentType = enum
    ctGraphQl = "application/graphql"
    ctJson    = "application/json"

  ClientResult* = Result[string, string]

  GraphqlHttpClientRef* = ref GraphqlHttpClientObj
  GraphqlHttpClientObj* = object of RootObj
    opName: string
    varTable: VarTable
    meth: HttpMethod
    address: TransportAddress
    uri: Uri
    contentType: ContentType
    bodyTimeout: Duration
    headersTimeout: Duration

const
  HttpBodyTimeout = 12.seconds
  HttpHeadersTimeout = 120.seconds

proc init*(cr: GraphqlHttpClientRef,
           address: TransportAddress,
           uri: Uri,
           meth: HttpMethod,
           contentType: ContentType,
           bodyTimeout: Duration,
           headersTimeout: Duration) =
  cr.varTable = @[]
  cr.address = address
  cr.meth = meth
  cr.uri = uri
  cr.contentType = contentType
  cr.bodyTimeout = bodyTimeout
  cr.headersTimeout = headersTimeout

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
  ctx.varTable.add VarPair(name: name, value: $val)

proc addVar*(ctx: GraphqlHttpClientRef, name: string, val: string) =
  ctx.varTable.add VarPair(name: name, value: "\"" & val & "\"")

proc addVar*(ctx: GraphqlHttpClientRef, name: string, val: float64) =
  ctx.varTable.add VarPair(name: name, value: $val)

proc addVar*(ctx: GraphqlHttpClientRef, name: string, val: bool) =
  ctx.varTable.add VarPair(name: name, value: $val)

proc addVar*(ctx: GraphqlHttpClientRef, name: string) =
  ctx.varTable.add VarPair(name: name, value: "null")

proc addEnumVar*(ctx: GraphqlHttpClientRef, name: string, val: string) =
  ctx.varTable.add VarPair(name: name, value: val)

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
        r.write(n.value)

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
      ok(dataBuf)
    else:
      ok("")
  await transp.closeWait()
  return cresp
