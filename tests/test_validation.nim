# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  std/[os, strutils, tables],
  pkg/[toml_serialization, unittest2],
  ../graphql, ../graphql/test_config,
  ../graphql/graphql as context,
  ../graphql/validator

type
  Unit = object
    name: string
    skip: bool
    error: string
    code: string

  TestCase = object
    units: seq[Unit]

  # unittest2 complaint about
  # `var Counter` in parameter
  Counter = ref object
    skip: int
    fail: int
    ok: int

const
  caseFolder = "tests" / "validation"

proc scalarMyScalar(ctx: GraphqlRef, typeNode, node: Node): NodeResult {.cdecl, gcsafe, noSideEffect.} =
  if node.kind == nkString:
    ok(node)
  else:
    err("expect string, but got '$1'" % [$node.kind])

proc setupContext(): GraphqlRef =
  var ctx {.inject.} = new(GraphqlRef)
  ctx.customScalar("myScalar", scalarMyScalar)
  ctx.addVar("myStringVar", "graphql")
  ctx.addVar("myIntVar", 567)
  ctx.addVar("myNullVar")
  ctx.addVar("myBoolVar", true)
  let res = ctx.parseVar("myList", "[123, 456, 789]")
  assert(res.isOk)
  ctx

template setupParser(ctx: GraphqlRef, unit: Unit) =
  var stream = unsafeMemoryInput(unit.code)
  var parser {.inject.} = Parser.init(stream, ctx.names)
  parser.flags.incl pfExperimentalFragmentVariables
  var doc {.inject.}: FullDocument
  parseDocument(parser, doc)
  stream.close()

proc escape(x: string): string =
  result.add '"'
  for c in x:
    if c == '"':
      result.add '\\'
      result.add '\"'
    elif c == '\\':
      result.add '\\'
      result.add '\\'
    else:
      result.add c

  result.add '"'
  result.add "\n"

proc writeUnit(f: File, unit: Unit) =
  f.write("[[units]]\n")
  f.write("  name = \"" & unit.name & "\"\n")
  if unit.skip:
    f.write("  skip = " & $unit.skip & "\n")
  if unit.error.len > 0:
    f.write("  error = " & escape(unit.error))
  f.write("  code = \"\"\"\n")
  f.write(unit.code)
  f.write("\"\"\"\n\n")

proc validateAll(ctx: GraphqlRef, root: Node) =
  visit validate(root)
  for name, sym in ctx.opTable:
    if sym.sym.kind != skFragment:
      exec := getOperation($name)
      discard exec

proc runConverter(ctx: GraphqlRef, unit: var Unit) =
  setupParser(ctx, unit)
  if parser.error != errNone:
    unit.error = $parser.err
    return

  ctx.validateAll(doc.root)
  if ctx.errKind != ErrNone:
    assert(ctx.errors.len == 1)
    unit.error = $ctx.errors[0]
    return

proc runConverter(ctx: GraphqlRef, savePoint: NameCounter, path, output: string) =
  let parts = splitFile(path)
  let newPath = "tests" / output / parts.name & parts.ext
  var cases = Toml.loadFile(path, TestCase)
  var f = open(newPath, fmWrite)
  for unit in mitems(cases.units):
    ctx.runConverter(unit)
    ctx.purgeQueries(false)
    ctx.purgeSchema(false, false, false)
    ctx.purgeNames(savePoint)
    writeUnit(f, unit)

  f.close()

proc convertCases(output: string) =
  var ctx = setupContext()
  let savePoint = ctx.getNameCounter()
  for fileName in walkDirRec(caseFolder):
    ctx.runConverter(savePoint, fileName, output)

proc runValidator(ctx: GraphqlRef, unit: Unit, testStatusIMPL: var TestStatus) =
  setupParser(ctx, unit)
  if parser.error != errNone:
    check (parser.error != errNone) == (unit.error.len > 0)
    check $parser.err == unit.error
    return

  ctx.validateAll(doc.root)
  if ctx.errKind != ErrNone:
    check (ctx.errKind != ErrNone) == (unit.error.len > 0)
    check ctx.errors.len == 1
    check $ctx.errors[0] == unit.error
    return

  check (unit.error.len == 0)

proc runSuite(ctx: GraphqlRef, savePoint: NameCounter, fileName: string, counter: Counter) =
  let parts = splitFile(fileName)
  let cases = Toml.loadFile(fileName, TestCase)
  suite parts.name:
    for x in cases.units:
      let unit = x # prevent nim >= 1.6 cannot capture lent
      test unit.name:
        if unit.skip:
          skip()
          inc counter.skip
        else:
          ctx.runValidator(unit, testStatusIMPL)
          ctx.purgeQueries(false)
          ctx.purgeSchema(false, false, false)
          ctx.purgeNames(savePoint)
          if testStatusIMPL == OK:
            inc counter.ok
          else:
            inc counter.fail

proc validateCases() =
  var counter = Counter()
  var ctx = setupContext()
  let savePoint = ctx.getNameCounter()
  for fileName in walkDirRec(caseFolder):
    ctx.runSuite(savePoint, fileName, counter)
  debugEcho counter[]

proc runValidator(ctx: GraphqlRef, fileName: string, testStatusIMPL: var TestStatus) =
  var stream = memFileInput(fileName)
  var parser = Parser.init(stream, ctx.names)
  parser.flags.incl pfExperimentalFragmentVariables
  var doc: FullDocument
  parser.parseDocument(doc)
  stream.close()

  check parser.error == errNone
  if parser.error != errNone:
    debugEcho $parser.err
    return

  ctx.validateAll(doc.root)
  check ctx.errKind == ErrNone
  if ctx.errKind != ErrNone:
    debugEcho $ctx.errors
    return

proc validateSchemas() =
  suite "validate schemas":
    var ctx = new(GraphqlRef)
    var savePoint = ctx.getNameCounter()

    # if walkDirRec combined directly with `test` will sigsev
    var fileNames: seq[string]
    for fileName in walkDirRec("tests" / "schemas"):
      fileNames.add fileName

    for fileName in fileNames:
      test fileName:
        ctx.runValidator(fileName, testStatusIMPL)
        ctx.purgeQueries(true)
        ctx.purgeSchema(true, true, true)
        ctx.purgeNames(savePoint)

when isMainModule:
  proc main() =
    let conf = getConfiguration()
    if conf.convertPath.len != 0:
      createDir("tests" / conf.convertPath)
      convertCases(conf.convertPath)
      return

    if conf.testFile.len == 0:
      validateCases()
      validateSchemas()
      return

    # disable unittest param handler
    disableParamFiltering()
    var counter = Counter()
    var ctx = setupContext()
    var savePoint = ctx.getNameCounter()
    let fileName = caseFolder / conf.testFile
    if conf.unit.len == 0:
      ctx.runSuite(savePoint, fileName, counter)
      echo counter[]
      return

    let cases = Toml.loadFile(fileName, TestCase)
    for unit in cases.units:
      if unit.name != conf.unit:
        continue
      test unit.name:
        ctx.runValidator(unit, testStatusIMPL)
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
  validateCases()
