# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  std/[os, strutils, json],
  pkg/[unittest2],
  ../graphql

const
  schemaFolder = "tests" / "schemas"
  introsFolder = "tests" / "execution"

proc runValidator(ctx: GraphqlRef, fileName: string, testStatusIMPL: var TestStatus) =
  var res = ctx.parseSchemaFromFile(fileName)
  check res.isOk
  if res.isErr:
    debugEcho "error when parsing: ", fileName
    debugEcho res.error
    return

  const queryFile = introsFolder / "introspectionQuery.ql"
  res = ctx.parseQueryFromFile(queryFile)
  check res.isOk
  if res.isErr:
    debugEcho "error when parsing: ", queryFile
    debugEcho res.error
    return

  const queryName = "IntrospectionQuery"
  var resp = JsonRespStream.new()
  res = ctx.executeRequest(respStream(resp), queryName)
  check res.isOk
  if res.isErr:
    debugEcho "error when executing: ", queryName
    debugEcho res.error
    return

  try:
    let jsonRes = parseJson(resp.getString())
    check ($jsonRes).len != 0
  except:
    check false

proc main() =
  suite "schema introspection validation":
    var ctx = new(GraphqlRef)
    let savePoint = ctx.getNameCounter()
    var fileNames: seq[string]
    for fileName in walkDirRec(schemaFolder):
      if not fileName.endsWith(".ql"):
        continue
      fileNames.add fileName

    for x in fileNames:
      let fileName = x # prevent nim >= 1.6 cannot capture lent
      let parts = splitFile(fileName)
      test parts.name:
        ctx.runValidator(fileName, testStatusIMPL)
        ctx.purgeSchema(true, true, true)
        ctx.purgeQueries(true)
        ctx.purgeNames(savePoint)

main()
