# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  std/[os, strutils, unittest],
  toml_serialization,
  ../graphql, ./test_config, ./test_utils

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

  Counter = object
    skip: int
    fail: int
    ok: int

const
  caseFolder = "tests" / "execution"

{.push hint[XDeclaredButNotUsed]: off.}
{.pragma: apiPragma, cdecl, gcsafe, raises: [Defect, CatchableError].}

proc queryNameImpl(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  ok(resp("superman"))

proc queryColorImpl(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  ok(resp(567))

const queryProtos = {
  "name": queryNameImpl,
  "color": queryColorImpl
}

proc setupContext(): GraphqlRef =
  var ctx = new(GraphqlRef)
  ctx.addVar("myFalse", false)
  ctx.addVar("myTrue", true)
  ctx.addResolvers(nil, "Query", queryProtos)
  ctx

proc runExecutor(ctx: GraphqlRef, unit: Unit, testStatusIMPL: var TestStatus) =
  var stream = unsafeMemoryInput(unit.code)
  var parser = Parser.init(stream, ctx.names)
  parser.flags.incl pfExperimentalFragmentVariables
  var doc: FullDocument
  parser.parseDocument(doc)
  stream.close()

  check parser.error == errNone
  if parser.error != errNone:
    debugEcho parser.err
    return

  ctx.validate(doc.root)
  check ctx.errKind == ErrNone
  if ctx.errKind != ErrNone:
    debugEcho ctx.err
    return

  var resp = JsonRespStream.new()
  let res = ctx.executeRequest(resp, unit.opName)
  if res.isErr:
    check res.isErr == (unit.error.len > 0)
    check $res.error == unit.error
    return

  let unitRes = removeWhitespaces(unit.result)
  let execRes = removeWhitespaces(resp.getString)
  check unitRes == execRes

  check (unit.error.len == 0)

proc runSuite(ctx: GraphqlRef, savePoint: NameCounter, fileName: string, counter: var Counter) =
  let parts = splitFile(fileName)
  let cases = Toml.loadFile(fileName, TestCase)
  suite parts.name:
    for unit in cases.units:
      test unit.name:
        if unit.skip:
          skip()
          inc counter.skip
        else:
          ctx.runExecutor(unit, testStatusIMPL)
          ctx.purgeQueries(false)
          ctx.purgeSchema(false, false)
          ctx.purgeNames(savePoint)
          if testStatusIMPL == OK:
            inc counter.ok
          else:
            inc counter.fail

proc executeCases() =
  var ctx = setupContext()
  let savePoint = ctx.getNameCounter()
  var counter: Counter
  for fileName in walkDirRec(caseFolder):
    ctx.runSuite(savePoint, fileName, counter)
  debugEcho counter

when isMainModule:
  proc main() =
    let conf = getConfiguration()
    if conf.testFile.len == 0:
      executeCases()
      return

    # disable unittest param handler
    disableParamFiltering()
    var counter: Counter
    let fileName = caseFolder / conf.testFile
    var ctx = setupContext()
    let savePoint = ctx.getNameCounter()
    if conf.unit.len == 0:
      ctx.runSuite(savePoint, fileName, counter)
      echo counter
      return

    let cases = Toml.loadFile(fileName, TestCase)
    for unit in cases.units:
      if unit.name != conf.unit:
        continue
      test unit.name:
        ctx.runExecutor(unit, testStatusIMPL)
        ctx.purgeQueries(true)
        ctx.purgeSchema(true, true)
        ctx.purgeNames(savePoint)

  var message: string
  ## Processing command line arguments
  if processArguments(message) != Success:
    echo message
    quit(QuitFailure)
  else:
    if len(message) > 0:
      echo message
      quit(QuitSuccess)
  main()
else:
  executeCases()

{.pop.}