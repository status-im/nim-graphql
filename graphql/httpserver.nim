# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  std/[strutils],
  chronicles, json_serialization,
  chronos, chronos/apps/http/httpserver,
  ./graphql, ./api, ./builtin/json_respstream

type
  VarPair = object
    name: string
    value: string

  VarTable = seq[VarPair]

  ContentType = enum
    ctGraphQl
    ctJson

  RequestObject = object
    query: string
    operationName: string
    variables: VarTable

  GraphqlHttpServerState* {.pure.} = enum
    Closed
    Stopped
    Running

  GraphqlHttpResult*[T] = Result[T, string]

  GraphqlHttpServer* = object of RootObj
    server*: HttpServerRef
    graphql*: GraphqlRef
    savePoint: NameCounter
    defRespHeader: HttpTable

  GraphqlHttpServerRef* = ref GraphqlHttpServer

proc readValue*(reader: var JsonReader, value: var VarTable) =
  for key, val in readObject(reader, string, string):
    value.add VarPair(name: key, value: val)

template jsonDecodeImpl(input, value: untyped): GraphqlHttpResult[void] =
  try:
    var stream = unsafeMemoryInput(input)
    var reader = init(ReaderType(Json), stream)
    reader.readValue(value)
    return ok()
  except:
    return err(getCurrentExceptionMsg())

proc jsonDecode[T](input: openArray[byte], value: var T): GraphqlHttpResult[void] =
  jsonDecodeImpl(input, value)

proc jsonDecode[T](input: string, value: var T): GraphqlHttpResult[void] =
  jsonDecodeImpl(input, value)

proc errorResp(msg: string): string =
  var r = JsonRespStream.new()
  respMap(r):
    r.fieldName("errors")
    respList(r):
      respMap(r):
        r.fieldName("message")
        r.write(msg)
  r.getString()

proc errorResp(err: ErrorDesc): string =
  var r = JsonRespStream.new()
  respMap(r):
    r.fieldName("errors")
    respList(r):
      respMap(r):
        r.fieldName("message")
        r.write(err.message)
        r.fieldName("locations")
        respList(r):
          respMap(r):
            r.fieldName("line")
            r.write(err.pos.line.int)
            r.fieldName("column")
            r.write(err.pos.col.int)
  r.getString()

proc errorResp(err: ErrorDesc, data: openArray[byte]): string =
  var r = JsonRespStream.new()
  respMap(r):
    r.fieldName("errors")
    respList(r):
      respMap(r):
        r.fieldName("message")
        r.write(err.message)
        r.fieldName("locations")
        respList(r):
          respMap(r):
            r.fieldName("line")
            r.write(err.pos.line.int)
            r.fieldName("column")
            r.write(err.pos.col.int)
    r.fieldName("data")
    r.write(data)
  r.getString()

proc okResp(data: openArray[byte]): string =
  var r = JsonRespStream.new()
  respMap(r):
    r.fieldName("data")
    r.write(data)
  r.getString()

template exec(executor: untyped) =
  let res = callValidator(ctx, executor)
  if res.isErr:
    return errorResp(res.error)

proc execRequest(server: GraphqlHttpServerRef, ro: RequestObject): string {.gcsafe.} =
  let ctx = server.graphql

  # clean up previous garbage before new execution
  ctx.purgeQueries(includeVariables = true)
  ctx.purgeNames(server.savePoint)

  # TODO: get rid of this {.gcsafe.} if possible
  {.gcsafe.}:
    for n in ro.variables:
      exec parsevar(n.name, n.value)

    exec parseQuery(ro.query)
    let resp = JsonRespStream.new()
    let res = ctx.executeRequest(resp, ro.operationName)
    if res.isErr:
      errorResp(res.error, resp.getBytes())
    else:
      okResp(resp.getBytes())

proc processGraphqlRequest(server: GraphqlHttpServerRef, r: RequestFence): Future[HttpResponseRef] {.gcsafe, async.} =
  if r.isErr():
    return dumbResponse()

  let request = r.get()
  if request.uri.path != "/graphql":
    let error = errorResp("path '$1' not found" % [request.uri.path])
    return await request.respond(Http200, error, server.defRespHeader)

  var conSet: set[ContentType]
  let conType = request.headers.getList("content-type")
  for n in conType:
    if n == "application/graphql":
      conSet.incl ctGraphql
    elif n == "application/json":
      conSet.incl ctJson

  var ro: RequestObject
  for k, v in request.query.stringItems():
    case k
    of "query": ro.query = v
    of "operationName": ro.operationName = v
    of "variables":
      let res = jsonDecode(v, ro.variables)
      if res.isErr:
        let error = errorResp(res.error)
        return await request.respond(Http200, error, server.defRespHeader)
    else:
      discard

  if request.hasBody:
    let body = await request.getBody()
    if ctGraphql in conSet:
      ro.query = cast[string](body)
    else:
      let res = jsonDecode(body, ro)
      if res.isErr:
        let error = errorResp(res.error)
        return await request.respond(Http200, error, server.defRespHeader)

  let res = server.execRequest(ro)
  return await request.respond(Http200, res, server.defRespHeader)

proc new*(t: typedesc[GraphqlHttpServerRef],
          graphql: GraphqlRef,
          address: TransportAddress,
          serverIdent: string = "",
          serverFlags = {HttpServerFlags.NotifyDisconnect},
          socketFlags: set[ServerFlags] = {ReuseAddr},
          serverUri = Uri(),
          maxConnections: int = -1,
          backlogSize: int = 100,
          bufferSize: int = 4096,
          httpHeadersTimeout = 10.seconds,
          maxHeadersSize: int = 8192,
          maxRequestBodySize: int = 1_048_576): GraphqlHttpResult[GraphqlHttpServerRef] =
  var server = GraphqlHttpServerRef(
    graphql: graphql,
    savePoint: graphql.getNameCounter,
    defRespHeader: HttpTable.init([("Content-Type", "application/json")])
  )

  proc processCallback(rf: RequestFence): Future[HttpResponseRef] =
    processGraphqlRequest(server, rf)

  let sres = HttpServerRef.new(address, processCallback, serverFlags,
                               socketFlags, serverUri, serverIdent,
                               maxConnections, bufferSize, backlogSize,
                               httpHeadersTimeout, maxHeadersSize,
                               maxRequestBodySize)
  if sres.isOk():
    server.server = sres.get()
    ok(server)
  else:
    err("Could not create HTTP server instance")

proc state*(rs: GraphqlHttpServerRef): GraphqlHttpServerState {.raises: [Defect].} =
  ## Returns current GraphQL server's state.
  case rs.server.state
  of HttpServerState.ServerClosed:
    GraphqlHttpServerState.Closed
  of HttpServerState.ServerStopped:
    GraphqlHttpServerState.Stopped
  of HttpServerState.ServerRunning:
    GraphqlHttpServerState.Running

proc start*(rs: GraphqlHttpServerRef) =
  ## Starts GraphQL server.
  rs.server.start()
  notice "GraphQL service started", address = $rs.server.address

proc stop*(rs: GraphqlHttpServerRef) {.async.} =
  ## Stop GraphQL server from accepting new connections.
  await rs.server.stop()
  notice "GraphQL service stopped", address = $rs.server.address

proc drop*(rs: GraphqlHttpServerRef): Future[void] =
  ## Drop all pending connections.
  rs.server.drop()

proc closeWait*(rs: GraphqlHttpServerRef) {.async.} =
  ## Stop GraphQL server and drop all the pending connections.
  await rs.server.closeWait()
  notice "GraphQL service closed", address = $rs.server.address

proc join*(rs: GraphqlHttpServerRef): Future[void] =
  ## Wait until GraphQL server will not be closed.
  rs.server.join()
