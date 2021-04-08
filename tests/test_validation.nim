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
  ../graphql, ./test_config

type
  Unit = object
    name: string
    skip: bool
    error: string
    code: string

  TestCase = object
    units: seq[Unit]

  Counter = object
    skip: int
    fail: int
    ok: int

const
  caseFolder = "tests" / "validation"

proc scalarMyScalar(node: Node): ScalarResult =
  if node.kind == nkString:
    ok(node)
  else:
    err("expect string, but got '$1'" % [$node.kind])

template setupContext() =
  var stream = unsafeMemoryInput(unit.code)
  var ctx {.inject.} = newContext()
  ctx.customScalar("myScalar", scalarMyScalar)
  ctx.addVar("myStringVar", "graphql")
  ctx.addVar("myIntVar", 567)
  ctx.addVar("myNullVar")
  ctx.addVar("myBoolVar", true)

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

proc runConverter(unit: var Unit) =
  setupContext()
  if parser.error != errNone:
    unit.error = $parser.errDesc
    return

  ctx.validate(doc.root)
  if ctx.errKind != ErrNone:
    unit.error = $ctx.err
    return

proc runConverter(path, output: string) =
  let parts = splitFile(path)
  let newPath = "tests"/ output / parts.name & parts.ext
  var cases = Toml.loadFile(path, TestCase)
  var f = open(newPath, fmWrite)
  for unit in mitems(cases.units):
    runConverter(unit)
    writeUnit(f, unit)

  f.close()

proc convertCases(output: string) =
  for fileName in walkDirRec(caseFolder):
    runConverter(fileName, output)

proc runValidator(unit: Unit, testStatusIMPL: var TestStatus) =
  setupContext()
  if parser.error != errNone:
    check (parser.error != errNone) == (unit.error.len > 0)
    check $parser.errDesc() == unit.error
    return

  ctx.validate(doc.root)
  if ctx.errKind != ErrNone:
    check (ctx.errKind != ErrNone) == (unit.error.len > 0)
    check $ctx.err == unit.error
    return

  check (unit.error.len == 0)

proc runSuite(fileName: string, counter: var Counter) =
  let parts = splitFile(fileName)
  let cases = Toml.loadFile(fileName, TestCase)
  suite parts.name:
    for unit in cases.units:
      test unit.name:
        if unit.skip:
          skip()
          inc counter.skip
        else:
          runValidator(unit, testStatusIMPL)
          if testStatusIMPL == OK:
            inc counter.ok
          else:
            inc counter.fail

proc validateCases() =
  var counter: Counter
  for fileName in walkDirRec(caseFolder):
    runSuite(fileName, counter)
  debugEcho counter

proc runValidator(fileName: string, testStatusIMPL: var TestStatus) =
  var stream = memFileInput(fileName)
  var ctx = newContext()

  var parser = Parser.init(stream, ctx.names)
  parser.flags.incl pfExperimentalFragmentVariables
  var doc: FullDocument
  parser.parseDocument(doc)
  stream.close()

  check parser.error == errNone
  if parser.error != errNone:
    debugEcho $parser.errDesc()
    return

  ctx.validate(doc.root)
  check ctx.errKind == ErrNone
  if ctx.errKind != ErrNone:
    debugEcho $ctx.err
    return

proc validateSchemas() =
  suite "validate schemas":
    for fileName in walkDirRec("tests" / "schemas"):
      test fileName:
        runValidator(fileName, testStatusIMPL)

when isMainModule:
  proc main() =
    let conf = getConfiguration()
    if conf.convertPath.len != 0:
      createDir(conf.convertPath)
      convertCases(conf.convertPath)
      return

    if conf.testFile.len == 0:
      validateCases()
      validateSchemas()
      return

    # disable unittest param handler
    disableParamFiltering()
    var counter: Counter
    let fileName = caseFolder / conf.testFile
    if conf.unit.len == 0:
      runSuite(fileName, counter)
      echo counter
      return

    let cases = Toml.loadFile(fileName, TestCase)
    for unit in cases.units:
      if unit.name != conf.unit:
        continue
      test unit.name:
        runValidator(unit, testStatusIMPL)

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
