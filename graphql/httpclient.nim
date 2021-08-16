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
  chronos/streams/tlsstream,
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
    serverName    : string
    version       : HttpVersion
    path          : string
    uriResolved   : bool
    secure        : bool
    contentType   : ContentType
    bodyTimeout   : Duration
    headersTimeout: Duration
    remoteAddress : TransportAddress

  GraphqlSHttpClientRef* = ref object of GraphqlHttpClientRef
    tlsFlags*: set[TLSFlags]
    minVersion*: TLSVersion
    maxVersion*: TLSVersion

  GraphqlHttpClientResult* = Result[GraphqlHttpClientRef, string]

  ConnectError = object of ValueError

when (NimMajor, NimMinor) <= (1, 2):
  type
    UriParseError = ValueError

const
  HttpBodyTimeout = 12.seconds
  HttpHeadersTimeout = 120.seconds

proc init*(ctx: GraphqlHttpClientRef,
           address: TransportAddress,
           path: string,
           serverName: string,
           meth: HttpMethod,
           version: HttpVersion,
           contentType: ContentType,
           bodyTimeout: Duration,
           headersTimeout: Duration) =
  ctx.names = newNameCache()
  ctx.varTable = @[]
  ctx.meth = meth
  ctx.contentType = contentType
  ctx.bodyTimeout = bodyTimeout
  ctx.headersTimeout = headersTimeout
  ctx.version = version

  ctx.uriResolved = true
  ctx.path = path
  ctx.serverName = serverName
  ctx.address = address

proc init*(ctx: GraphqlHttpClientRef,
           uri: Uri | string,
           meth: HttpMethod,
           version: HttpVersion,
           contentType: ContentType,
           bodyTimeout: Duration,
           headersTimeout: Duration) =
  ctx.names = newNameCache()
  ctx.varTable = @[]
  ctx.meth = meth
  ctx.contentType = contentType
  ctx.bodyTimeout = bodyTimeout
  ctx.headersTimeout = headersTimeout
  ctx.version = version

  ctx.uriResolved = false
  when uri is string:
    ctx.uri = parseUri(uri)
  else:
    ctx.uri = uri

proc init*(ctx: GraphqlSHttpClientRef,
           uri: Uri | string,
           tlsFlags: set[TLSFlags],
           tlsMinVersion: TLSVersion,
           tlsMaxVersion: TLSVersion,
           meth: HttpMethod,
           version: HttpVersion,
           contentType: ContentType,
           bodyTimeout: Duration,
           headersTimeout: Duration) =

  ctx.init(uri,
    meth,
    version,
    contentType,
    bodyTimeout,
    headersTimeout)

  ctx.tlsFlags = tlsFlags
  ctx.minVersion = tlsMinVersion
  ctx.maxVersion = tlsMaxVersion
  ctx.secure = true

proc init*(ctx: GraphqlSHttpClientRef,
           address: TransportAddress,
           path: string,
           serverName: string,
           tlsFlags: set[TLSFlags],
           tlsMinVersion: TLSVersion,
           tlsMaxVersion: TLSVersion,
           meth: HttpMethod,
           version: HttpVersion,
           contentType: ContentType,
           bodyTimeout: Duration,
           headersTimeout: Duration) =

  ctx.init(address,
    path,
    serverName,
    meth,
    version,
    contentType,
    bodyTimeout,
    headersTimeout)

  ctx.tlsFlags = tlsFlags
  ctx.minVersion = tlsMinVersion
  ctx.maxVersion = tlsMaxVersion
  ctx.secure = true

proc new*(_: type GraphqlHttpClientRef,
          address: TransportAddress,
          path: string = "/graphql",
          serverName: string = "",
          meth: HttpMethod = MethodPost,
          version: HttpVersion = HttpVersion10,
          contentType: ContentType = ctJson,
          bodyTimeout: Duration = HttpBodyTimeout,
          headersTimeout: Duration = HttpHeadersTimeout): GraphqlHttpClientResult =

  let client = GraphqlHttpClientRef()
  client.init(address,
    path,
    serverName,
    meth,
    version,
    contentType,
    bodyTimeout,
    headersTimeout)
  ok(client)

proc new*(_: type GraphqlHttpClientRef,
          uri: Uri | string,
          meth: HttpMethod = MethodPost,
          version: HttpVersion = HttpVersion10,
          contentType: ContentType = ctJson,
          bodyTimeout: Duration = HttpBodyTimeout,
          headersTimeout: Duration = HttpHeadersTimeout): GraphqlHttpClientResult =
  let client = GraphqlHttpClientRef()
  try:
    client.init(uri,
      meth,
      version,
      contentType,
      bodyTimeout,
      headersTimeout)
    ok(client)
  except UriParseError as exc:
    err(exc.msg)

proc new*(_: type GraphqlSHttpClientRef,
          address: TransportAddress,
          path: string = "/graphql",
          serverName: string = "",
          tlsFlags: set[TLSFlags] = {},
          tlsMinVersion = TLSVersion.TLS11,
          tlsMaxVersion = TLSVersion.TLS12,
          meth: HttpMethod = MethodPost,
          version: HttpVersion  = HttpVersion10,
          contentType: ContentType = ctJson,
          bodyTimeout: Duration = HttpBodyTimeout,
          headersTimeout: Duration = HttpHeadersTimeout): GraphqlHttpClientResult =
  let client = GraphqlSHttpClientRef()
  client.init(address,
    path,
    serverName,
    tlsFlags,
    tlsMinVersion,
    tlsMaxVersion,
    meth,
    version,
    contentType,
    bodyTimeout,
    headersTimeout)
  ok(client)

proc new*(_: type GraphqlSHttpClientRef,
          uri: Uri | string,
          tlsFlags: set[TLSFlags] = {},
          tlsMinVersion = TLSVersion.TLS11,
          tlsMaxVersion = TLSVersion.TLS12,
          meth: HttpMethod = MethodPost,
          version: HttpVersion = HttpVersion10,
          contentType: ContentType = ctJson,
          bodyTimeout: Duration = HttpBodyTimeout,
          headersTimeout: Duration = HttpHeadersTimeout): GraphqlHttpClientResult =
  let client = GraphqlSHttpClientRef()
  try:
    client.init(uri,
      tlsFlags,
      tlsMinVersion,
      tlsMaxVersion,
      meth,
      version,
      contentType,
      bodyTimeout,
      headersTimeout)
    ok(client)
  except UriParseError as exc:
    err(exc.msg)

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

proc connect(ctx: GraphqlHttpClientRef): Future[AsyncStream] {.async.} =
  let transp = await connect(ctx.address)
  ctx.remoteAddress = transp.remoteAddress()

  let stream = AsyncStream(
    reader: newAsyncStreamReader(transp),
    writer: newAsyncStreamWriter(transp))

  if ctx.secure:
    let c = GraphqlSHttpClientRef(ctx)
    let tlsStream = newTLSClientAsyncStream(
      stream.reader,
      stream.writer,
      serverName = c.serverName,
      minVersion = c.minVersion,
      maxVersion = c.maxVersion,
      flags = c.tlsFlags)

    return AsyncStream(
      reader: tlsStream.reader,
      writer: tlsStream.writer)
  else:
    return stream

proc resolveUri(ctx: GraphqlHttpClientRef): Future[AsyncStream] {.async.} =
  let host = $ctx.uri

  ctx.serverName = host.split(":")[0]
  ctx.path = ctx.uri.path

  let addrs = resolveTAddress(host)
  for a in addrs:
    ctx.address = a
    try:
      let conn = await ctx.connect()
      ctx.uriResolved = true
      return conn
    except TransportError as exc:
      raise newException(ConnectError, exc.msg)

  return AsyncStream()

proc closeTransp(transp: StreamTransport) {.async.} =
  if not transp.closed():
    await transp.closeWait()

proc closeStream(stream: AsyncStreamRW) {.async.} =
  if not stream.closed():
    await stream.closeWait()

proc closeWait(stream: AsyncStream) {.async.} =
  await allFutures(
    stream.reader.closeStream(),
    stream.writer.closeStream(),
    stream.reader.tsource.closeTransp())

proc sendRequest*(ctx: GraphqlHttpClientRef, query: string): Future[ClientResult] {.async.} =
  # TODO: implement GET method
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

  let body = r.getString()
  var request = $ctx.meth & " " & ctx.path & " HTTP/1.0\r\n"
  request.add("Host: " & ctx.serverName & "\r\n")
  request.add("Content-Length: " & $len(body) & "\r\n")
  request.add("Content-Type: " & $ctx.contentType & "\r\n")
  request.add("\r\n")
  request.add(body)

  try:
    let stream = if not ctx.uriResolved:
                   let stream = await ctx.resolveUri()
                   if not ctx.uriResolved:
                     return err("Unable to connect to host on any address!")
                   stream
                 else:
                   await ctx.connect()

    await stream.writer.write(request)

    var headersBuf = newSeq[byte](4096)
    let rlenFut = stream.reader.readUntil(addr headersBuf[0], len(headersBuf),
                                          HeadersMark)
    let hres = await withTimeout(rlenFut, ctx.headersTimeout)
    if not hres:
      debug "Timeout expired while receiving headers",
                address = ctx.remoteAddress
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
        let dataFut = stream.reader.readExactly(addr dataBuf[0], len(dataBuf))
        let dres = await withTimeout(dataFut, ctx.bodyTimeout)
        if not dres:
          debug "Timeout expired while receiving response body",
                address = ctx.remoteAddress
          return err("response body timeout")
        dataFut.read()
        ok(ClientResp(code: resp.code, response: dataBuf))
      else:
        ok(ClientResp(code: resp.code, response: ""))
    await stream.closeWait()
    return cresp
  except ConnectError as exc:
    return err("Error connecting to address $1: $2" % [$ctx.address, exc.msg])
  except TransportError as exc:
    return err(exc.msg)
