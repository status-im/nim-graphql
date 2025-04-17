# nim-graphql
# Copyright (c) 2021-2025 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  std/[uri],
  faststreams/inputs, zlib/gzip,
  results, chronicles, stew/byteutils,
  chronos, httputils, chronos/apps/http/[httpcommon, httptable, httpclient],
  chronos/streams/tlsstream,
  ./common/[ast, names, response, types, errors],
  ./builtin/json_respstream, ./common_parser, ./lexer

type
  ContentType = enum
    ctGraphQl = "application/graphql"
    ctJson    = "application/json"

  VarPair = object
    name : string
    value: Node

  ParseResult* = Result[void, ErrorDesc]

  ClientResp* = object
    status*  : int # HTTP code
    reason*  : string
    response*: string

  GraphqlHttpClientRef* = ref GraphqlHttpClientObj
  GraphqlHttpClientObj* = object of RootObj
    opName        : string
    varTable      : seq[VarPair]
    names         : NameCache
    meth          : HttpMethod
    version       : HttpVersion
    secure        : bool
    contentType   : ContentType
    address       : HttpAddress
    session       : HttpSessionRef

const
  GraphQLPath* = "/graphql"

{.push gcsafe, raises: [].}

proc createSession(secure: bool,
                   maxRedirections = HttpMaxRedirections,
                   connectTimeout = HttpConnectTimeout,
                   headersTimeout = HttpHeadersTimeout,
                   connectionBufferSize = DefaultStreamBufferSize
                  ): HttpSessionRef =

  let flags = if secure:
               {HttpClientFlag.NoVerifyHost,
                HttpClientFlag.NoVerifyServerName}
              else:
               {}

  HttpSessionRef.new(flags,
    maxRedirections,
    connectTimeout,
    headersTimeout,
    connectionBufferSize
  )

proc init*(ctx: GraphqlHttpClientRef,
           address: TransportAddress,
           path: string = GraphQLPath,
           secure: bool = false,
           meth: HttpMethod = MethodPost,
           version: HttpVersion = HttpVersion11,
           contentType: ContentType = ctJson,
           maxRedirections = HttpMaxRedirections,
           connectTimeout = HttpConnectTimeout,
           headersTimeout = HttpHeadersTimeout,
           connectionBufferSize = DefaultStreamBufferSize
           ) =

  ctx.names = newNameCache()
  ctx.varTable = @[]
  ctx.meth = meth
  ctx.version = version
  ctx.contentType = contentType
  ctx.secure = secure
  ctx.session = createSession(
    secure,
    maxRedirections,
    connectTimeout,
    headersTimeout,
    connectionBufferSize
  )
  ctx.address =
    if secure:
      getAddress(address, HttpClientScheme.Secure, path)
    else:
      getAddress(address, HttpClientScheme.NonSecure, path)

proc init*(ctx: GraphqlHttpClientRef,
           uri: Uri | string,
           secure: bool = false,
           meth: HttpMethod = MethodPost,
           version: HttpVersion = HttpVersion11,
           contentType: ContentType = ctJson,
           maxRedirections = HttpMaxRedirections,
           connectTimeout = HttpConnectTimeout,
           headersTimeout = HttpHeadersTimeout,
           connectionBufferSize = DefaultStreamBufferSize
           ): HttpResult[void] =

  ctx.names = newNameCache()
  ctx.varTable = @[]
  ctx.meth = meth
  ctx.version = version
  ctx.contentType = contentType
  ctx.secure = secure
  ctx.session = createSession(
    secure,
    maxRedirections,
    connectTimeout,
    headersTimeout,
    connectionBufferSize
  )
  let res = getAddress(ctx.session, uri)
  if res.isErr:
    return err(res.error)
  ctx.address = res.get()

proc new*(_: type GraphqlHttpClientRef,
          address: TransportAddress,
          path: string = GraphQLPath,
          secure: bool = false,
          meth: HttpMethod = MethodPost,
          version: HttpVersion = HttpVersion11,
          contentType: ContentType = ctJson,
          maxRedirections = HttpMaxRedirections,
          connectTimeout = HttpConnectTimeout,
          headersTimeout = HttpHeadersTimeout,
          connectionBufferSize = DefaultStreamBufferSize
          ): HttpResult[GraphqlHttpClientRef] =

  let client = GraphqlHttpClientRef()
  client.init(address,
    path,
    secure,
    meth,
    version,
    contentType,
    maxRedirections,
    connectTimeout,
    headersTimeout,
    connectionBufferSize
  )
  ok(client)

proc new*(_: type GraphqlHttpClientRef,
          uri: Uri | string,
          secure: bool = false,
          meth: HttpMethod = MethodPost,
          version: HttpVersion = HttpVersion11,
          contentType: ContentType = ctJson,
          maxRedirections = HttpMaxRedirections,
          connectTimeout = HttpConnectTimeout,
          headersTimeout = HttpHeadersTimeout,
          connectionBufferSize = DefaultStreamBufferSize
          ): HttpResult[GraphqlHttpClientRef] =

  let client = GraphqlHttpClientRef()
  let res =
    client.init(uri,
      secure,
      meth,
      version,
      contentType,
      maxRedirections,
      connectTimeout,
      headersTimeout,
      connectionBufferSize
    )
  if res.isErr:
    return err(res.error)
  ok(client)

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

proc parseVars(ctx: GraphqlHttpClientRef, input: InputStream): ParseResult =
  try:
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
  except IOError as exc:
    err(errorError(exc.msg))

proc parseVars*(ctx: GraphqlHttpClientRef, input: string): ParseResult {.gcsafe.} =
  {.gcsafe.}:
    var stream = unsafeMemoryInput(input)
    ctx.parseVars(stream)

proc parseVars*(ctx: GraphqlHttpClientRef, input: openArray[byte]): ParseResult {.gcsafe.} =
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

proc sendRequest*(ctx: GraphqlHttpClientRef, query: string,
                  headers: seq[HttpHeaderTuple] = @[]): Future[HttpResult[ClientResp]] {.async.} =
  # TODO: implement content-type: graphql

  var r = JsonRespStream.new()
  respMap(r):
    r.field("query")
    r.write(query)
    r.field("operationName")
    r.write(ctx.opName)
    r.field("variables")
    respMap(r):
      for n in ctx.varTable:
        r.field(n.name)
        r.serialize(n.value)

  let body = r.getBytes()
  var newHeaders = if headers.len > 0:
                     headers
                   else:
                     @[]

  newHeaders.add(("Content-Type", "application/json"))

  try:
    let request =
      HttpClientRequestRef.new(
        ctx.session, ctx.address,
        ctx.meth, ctx.version, {},
        headers = newHeaders, body = body
      )

    let resp = await request.send()
    let dataBuf = await resp.getBodyBytes()

    let cresp =
      if dataBuf.len > 0:
        if ContentEncodingFlags.Gzip in resp.contentEncoding:
          let gres = string.ungzip(dataBuf)
          if gres.isErr:
            return err(gres.error)
          ok(ClientResp(status: resp.status, reason: resp.reason, response: gres.get()))
        else:
          let dataString = string.fromBytes(dataBuf)
          ok(ClientResp(status: resp.status, reason: resp.reason, response: dataString))
      else:
        ok(ClientResp(status: resp.status, reason: resp.reason, response: ""))

    await resp.closeWait()
    await request.closeWait()
    return cresp
  except HttpError as exc:
    return err(exc.msg)

proc closeWait*(ctx: GraphqlHttpClientRef) {.async.} =
  if ctx.session.isNil.not:
    await ctx.session.closeWait()

{.pop.}
