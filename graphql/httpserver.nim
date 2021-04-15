# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  std/[strutils, json],
  chronicles, chronos, chronos/apps/http/httpserver,
  ./graphql, ./api, ./builtin/json_respstream,
  ./server_common

type
  ContentType = enum
    ctGraphQl
    ctJson

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

template exec(executor: untyped) =
  let res = callValidator(ctx, executor)
  if res.isErr:
    return jsonErrorResp(res.error)

proc execRequest(server: GraphqlHttpServerRef, ro: RequestObject): string {.gcsafe.} =
  let ctx = server.graphql

  # clean up previous garbage before new execution
  ctx.purgeQueries(includeVariables = true)
  ctx.purgeNames(server.savePoint)

  ctx.addVariables(ro.variables)

  exec parseQuery(toString(ro.query))
  let resp = JsonRespStream.new()
  let res = ctx.executeRequest(resp, toString(ro.operationName))
  if res.isErr:
    jsonErrorResp(res.error, resp.getBytes(), ctx.path)
  else:
    jsonOkResp(resp.getBytes())

proc getContentTypes(request: HttpRequestRef): set[ContentType] =
  let conType = request.headers.getList("content-type")
  for n in conType:
    if n == "application/graphql":
      result.incl ctGraphql
    elif n == "application/json":
      result.incl ctJson

proc processGraphqlRequest(server: GraphqlHttpServerRef, r: RequestFence): Future[HttpResponseRef] {.gcsafe, async.} =
  if r.isErr():
    return dumbResponse()

  let request = r.get()
  if request.uri.path != "/graphql":
    let error = jsonErrorResp("path '$1' not found" % [request.uri.path])
    return await request.respond(Http200, error, server.defRespHeader)

  let ctx = server.graphql
  let contentTypes = request.getContentTypes()

  var ro = RequestObject.init()
  for k, v in request.query.stringItems():
    let res = ctx.decodeRequest(ro, k, v)
    if res.isErr:
      let error = jsonErrorResp(res.error)
      return await request.respond(Http200, error, server.defRespHeader)

  if request.hasBody:
    let body = await request.getBody()
    if ctGraphql in contentTypes:
      ro.query = toQueryNode(cast[string](body))
    else:
      let res = ctx.parseLiteral(body)
      if res.isErr:
        let error = jsonErrorResp(res.error)
        return await request.respond(Http200, error, server.defRespHeader)
      requestNodeToObject(res.get(), ro)

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
