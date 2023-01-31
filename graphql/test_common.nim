# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  std/[os, strutils],
  pkg/[toml_serialization, unittest2],
  ../graphql, ./test_config

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

  Counter = ref object
    skip: int
    fail: int
    ok: int

proc removeWhitespaces(x: string): string =
  const whites = {' ', '\t', '\r', '\n'}
  type
    State = enum
      inRoot
      inString

  if x.len == 0:
    return

  var state = inRoot
  var i = 0
  while i < x.len:
    var c = x[i]
    case state
    of inRoot:
      if c == '\"':
        state = inString
        result.add c
      elif c notin whites:
        result.add c
      inc i
    of inString:
      if c == '\\':
        result.add c
        inc i
        c = x[i]
      elif c == '\"':
        state = inRoot
      result.add c
      inc i

proc checkErrors(ctx: GraphqlRef, errors: openArray[ErrorDesc],
                 unit: Unit, testStatusIMPL: var TestStatus) =
  check errors.len == unit.errors.len
  if errors.len > unit.errors.len:
    debugEcho ctx.errors
  for i in 0..<min(errors.len, unit.errors.len):
    check $errors[i] == unit.errors[i]

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
  if ctx.errKind != ErrNone:
    checkErrors(ctx, ctx.errors, unit, testStatusIMPL)
    return

  let js = JsonRespStream.new()
  let res = ctx.executeRequest(respStream(js), unit.opName)
  if res.isErr:
    check res.isErr == (unit.errors.len > 0)
    let errors = res.error
    checkErrors(ctx, errors, unit, testStatusIMPL)
  else:
    check unit.errors.len == 0

  # don't skip result comparison even though there are errors
  let unitRes = removeWhitespaces(unit.result)
  let execRes = removeWhitespaces(js.getString)
  check unitRes == execRes

proc runSuite(ctx: GraphqlRef, savePoint: NameCounter, fileName: string, counter: Counter, purgeSchema: bool) =
  let parts = splitFile(fileName)
  let cases = Toml.loadFile(fileName, TestCase)
  suite parts.name:
    for x in cases.units:
      let unit = x # prevent nim >= 1.6 cannot capture lent
      test unit.name:
        if unit.skip:
          ctx.purgeQueries(true)
          ctx.purgeNames(savePoint)
          if purgeSchema:
            ctx.purgeSchema(false, false, false)
          skip()
          inc counter.skip
        else:
          ctx.runExecutor(unit, testStatusIMPL)
          ctx.purgeQueries(true)
          ctx.purgeNames(savePoint)
          if purgeSchema:
            ctx.purgeSchema(false, false, false)
          if testStatusIMPL == OK:
            inc counter.ok
          else:
            inc counter.fail

proc executeCases*(ctx: GraphqlRef, caseFolder: string, purgeSchema: bool) =
  let savePoint = ctx.getNameCounter()
  var counter = Counter()
  var fileNames: seq[string]
  for fileName in walkDirRec(caseFolder):
    if not fileName.endsWith(".toml"):
      continue
    fileNames.add fileName

  for fileName in fileNames:
    ctx.runSuite(savePoint, fileName, counter, purgeSchema)

  debugEcho counter[]

proc main*(ctx: GraphqlRef, caseFolder: string, purgeSchema: bool) =
  let conf = getConfiguration()
  if conf.testFile.len == 0:
    executeCases(ctx, caseFolder, purgeSchema)
    return

  # disable unittest param handler
  disableParamFiltering()
  var counter = Counter()
  let fileName = caseFolder / conf.testFile
  let savePoint = ctx.getNameCounter()
  if conf.unit.len == 0:
    ctx.runSuite(savePoint, fileName, counter, purgeSchema)
    echo counter[]
    return

  let cases = Toml.loadFile(fileName, TestCase)
  for unitx in cases.units:
    let unit = unitx # silence cannot capture <lent Unit>
    if unit.name != conf.unit:
      continue
    test unit.name:
      ctx.runExecutor(unit, testStatusIMPL)
      ctx.purgeQueries(true)
      ctx.purgeNames(savePoint)
      if purgeSchema:
        ctx.purgeSchema(false, false, false)

proc processArguments*() =
  var message: string
  ## Processing command line arguments
  if processArguments(message) != Success:
    echo message
    quit(QuitFailure)
  else:
    if len(message) > 0:
      echo message
      quit(QuitSuccess)
