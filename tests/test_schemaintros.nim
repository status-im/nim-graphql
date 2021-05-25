# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  std/[os, strutils, unittest, json],
  ../graphql, ./mocha

const
  schemaFolder = "tests" / "schemas"
  introsFolder = "tests" / "execution"

proc runValidator(ctx: GraphqlRef, fileName: string, testStatusIMPL: var TestStatus, mtest: TestRef) =
  var res = ctx.parseSchemaFromFile(fileName)
  check res.isOk
  if res.isErr:
    debugEcho "error when parsing: ", fileName
    debugEcho res.error
    mtest.setFail($res.error)
    return

  const queryFile = introsFolder / "introspectionQuery.ql"
  res = ctx.parseQueryFromFile(queryFile)
  check res.isOk
  if res.isErr:
    debugEcho "error when parsing: ", queryFile
    debugEcho res.error
    mtest.setFail($res.error)
    return

  const queryName = "IntrospectionQuery"
  var resp = JsonRespStream.new()
  res = ctx.executeRequest(respStream(resp), queryName)
  check res.isOk
  if res.isErr:
    debugEcho "error when executing: ", queryName
    debugEcho res.error
    mtest.setFail($res.error)
    return

  try:
    let jsonRes = parseJson(resp.getString())
    check ($jsonRes).len != 0
  except Exception as e:
    check false
    mtest.setFail(e.msg)
    return

  mtest.setPass()

proc main() =
  var mocha = Mocha.init()
  suite "schema introspection validation":
    var msuite = newSuite("schema introspection validation", currentSourcePath())
    var ctx = new(GraphqlRef)
    let savePoint = ctx.getNameCounter()
    for fileName in walkDirRec(schemaFolder):
      if not fileName.endsWith(".ql"):
        continue

      let parts = splitFile(fileName)
      test parts.name:
        var mtest = newTest(parts.name, fileName)
        ctx.runValidator(fileName, testStatusIMPL, mtest)
        ctx.purgeSchema(true, true, true)
        ctx.purgeQueries(true)
        ctx.purgeNames(savePoint)
        msuite.add mtest

    mocha.add msuite

  mocha.finalize("report" / "schemaintros.json")
main()
