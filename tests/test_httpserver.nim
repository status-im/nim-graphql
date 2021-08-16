# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

# curl -X POST -H Content-Type:application/graphql http://localhost:8547/graphql -d @data.json

import
  std/[os, json],
  pkg/[toml_serialization, unittest2, chronos],
  ../graphql, ../graphql/[httpserver, httpclient],
  ../graphql/test_config, ./test_utils, keys/keys

type
  Unit = object
    name: string
    skip: bool
    error: string
    opName: string
    code: string
    result: string

  TestCase = object
    units: seq[Unit]

  Counter = ref object
    skip: int
    fail: int
    ok: int

const
  caseFolder = "tests" / "serverclient"
  serverAddress = initTAddress("127.0.0.1:8547")

proc createServer(serverAddress: TransportAddress): GraphqlHttpServerRef =
  let socketFlags = {ServerFlags.TcpNoDelay, ServerFlags.ReuseAddr}
  var ctx = GraphqlRef.new()
  ctx.initMockApi()

  const schema = """
    type Query {
      name: String
      color: Int
      tree: Tree
    }

    type Tree {
      name: String
      age: Int
      number: [Int!]
    }
  """
  let r = ctx.parseSchema(schema)
  if r.isErr:
    debugEcho r.error
    return

  when defined(tls):
    let res = GraphqlHttpServerRef.new(
      graphql = ctx,
      address = serverAddress,
      tlsPrivateKey = TLSPrivateKey.init(SecureKey),
      tlsCertificate = TLSCertificate.init(SecureCrt),
      socketFlags = socketFlags)
  else:
    let res = GraphqlHttpServerRef.new(ctx, serverAddress, socketFlags = socketFlags)

  if res.isErr():
    debugEcho res.error
    return

  res.get()

proc setupClient(address: TransportAddress): GraphqlHttpClientRef =
  when defined(tls):
    let flags = {TLSFlags.NoVerifyHost, TLSFlags.NoVerifyServerName}
    GraphqlSHttpClientRef.new(address = address, tlsFlags = flags).get()
  else:
    GraphqlHttpClientRef.new(address).get()

proc runExecutor(client: GraphqlHttpClientRef, unit: Unit, testStatusIMPL: var TestStatus) =
  client.operationName(unit.opName)
  let res = waitFor client.sendRequest(unit.code)
  check res.isOk
  if res.isErr:
    debugEcho res.error
    return

  let clientResp = res.get()
  check (clientResp.code == 200) == (unit.error.len == 0)

  let resp = decodeResponse(clientResp.response)
  if not resp.errors.isNil:
    if unit.error.len == 0:
      debugEcho $resp.errors
    check unit.error.len != 0
    let node = parseJson(unit.error)
    check $node == $resp.errors

  if not resp.data.isNil:
    check unit.result.len != 0
    let node = parseJson(unit.result)
    check $node == $resp.data

proc runSuite(client: GraphqlHttpClientRef, fileName: string, counter: Counter) =
  let parts = splitFile(fileName)
  let cases = Toml.loadFile(fileName, TestCase)
  suite parts.name:
    for unit in cases.units:
      test unit.name:
        if unit.skip:
          skip()
          inc counter.skip
        else:
          client.runExecutor(unit, testStatusIMPL)
          if testStatusIMPL == OK:
            inc counter.ok
          else:
            inc counter.fail

proc executeCases() =
  var counter = Counter()
  let server = createServer(serverAddress)
  server.start()
  var client = setupClient(serverAddress)

  for fileName in walkDirRec(caseFolder):
    client.runSuite(fileName, counter)

  waitFor server.closeWait()
  debugEcho counter[]

when isMainModule:
  proc main() =
    let conf = getConfiguration()
    if conf.testFile.len == 0:
      executeCases()
      return

    # disable unittest param handler
    disableParamFiltering()
    var counter = Counter()
    let fileName = caseFolder / conf.testFile
    var client = setupClient(serverAddress)
    if conf.unit.len == 0:
      let server = createServer(serverAddress)
      server.start()
      client.runSuite(fileName, counter)
      waitFor server.closeWait()
      echo counter[]
      return

    let cases = Toml.loadFile(fileName, TestCase)
    let server = createServer(serverAddress)
    server.start()
    for unit in cases.units:
      if unit.name != conf.unit:
        continue
      test unit.name:
        client.runExecutor(unit, testStatusIMPL)
    waitFor server.closeWait()

  var message: string
  ## Processing command line arguments
  if processArguments(message) != ConfigStatus.Success:
    echo message
    quit(QuitFailure)
  else:
    if len(message) > 0:
      echo message
      quit(QuitSuccess)
  main()
else:
  executeCases()
