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
    errors: seq[string]
    opName: string
    variables: string
    code: string
    result: string

  TestCase = object
    units: seq[Unit]

  Counter = object
    skip: int
    fail: int
    ok: int

  TestNames = enum
    tnHuman     = "Human"
    tnDroid     = "Droid"
    tnStarship  = "Starship"
    tnEntity    = "Entity"

  TestContext = ref object of RootRef
    names: array[TestNames, Name]

const
  caseFolder = "tests" / "introspection"

{.push hint[XDeclaredButNotUsed]: off.}
{.pragma: apiPragma, cdecl, gcsafe, raises: [Defect, CatchableError].}

proc queryNameImpl(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  ok(resp("superman"))

proc querySearchImpl(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var tc = TestContext(ud)
  var list = respList()
  list.add respMap(tc.names[tnHuman])
  list.add respMap(tc.names[tnDroid])
  list.add respMap(tc.names[tnStarship])
  ok(list)

const queryProtos = {
  "name": queryNameImpl,
  "search": querySearchImpl
}

proc nameImpl(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  let tc = TestContext(ud)
  if parent.typeName == tc.names[tnHuman]:
    ok(resp("Dr. Jones"))
  elif parent.typeName == tc.names[tnStarship]:
    ok(resp("Millenium Falcon"))
  else:
    ok(resp("3CPO"))

proc colorImpl(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  ok(resp("YELLOW"))

proc setupContext(): GraphqlRef =
  var ctx = new(GraphqlRef)
  var tc = TestContext()
  for c in TestNames:
    let name = ctx.createName($c)
    tc.names[c] = name
    ctx.addResolvers(tc, name, [("name", nameImpl)])

  ctx.addResolvers(tc, "Query", queryProtos)
  ctx.addResolvers(tc, "Droid", [("color", colorImpl)])
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

  if unit.variables.len != 0:
    let res = ctx.parseVars(unit.variables)
    check res.isOk
    if res.isErr:
      debugEcho res.error
      return

  ctx.validate(doc.root)
  check ctx.errKind == ErrNone
  if ctx.errKind != ErrNone:
    debugEcho ctx.errors
    return

  var resp = JsonRespStream.new()
  let res = ctx.executeRequest(resp, unit.opName)
  if res.isErr:
    check res.isErr == (unit.errors.len > 0)
    let errors = res.error
    check errors.len == unit.errors.len
    if errors.len > unit.errors.len:
      debugEcho ctx.errors
    for i in 0..<min(errors.len, unit.errors.len):
      check $errors[i] == unit.errors[i]
    return

  let unitRes = removeWhitespaces(unit.result)
  let execRes = removeWhitespaces(resp.getString)
  check unitRes == execRes

  check (unit.errors.len == 0)

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
          ctx.purgeSchema(false, false, false)
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
    if not fileName.endsWith(".toml"):
      continue
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
        ctx.purgeSchema(true, true, true)
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