# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  std/[os],
  pkg/[unittest2],
  ../../graphql, ../ethapi, ../../graphql/test_common,
  ../../graphql/instruments/query_complexity

const
  caseFolder = "playground" / "tests" / "ethereum"

proc setupContext(): GraphqlRef =
  var ctx = new(GraphqlRef)
  ctx.initEthApi()
  let res = ctx.parseSchemaFromFile("tests" / "schemas" / "ethereum_1.0.ql")
  if res.isErr:
    debugEcho res.error
    quit(QuitFailure)
  ctx

proc calcQC(qc: QueryComplexity, field: FieldRef): int {.cdecl, gcsafe, raises: [Defect, CatchableError].} =
  if $field.parentType == "__Type" and $field.field.name == "fields":
    return 100
  elif $field.parentType == "Transaction" and $field.field.name == "block":
    return 100
  else:
    return 1

const
  query1 = """
{ __schema { types { fields { type { fields { name }}}}}}
"""
  query2 = """
{ block { transactions { block { transactions { block { number }}}}}}
"""
  query3 = """
query eth_protocolVersion {
  protocolVersion
}
"""

proc executeQC(ctx: GraphqlRef, query: string): Result[string, string] =
  var res = ctx.parseQuery(query, store = true)
  if res.isErr:
    return err($res.error)

  let resp = JsonRespStream.new()
  res = ctx.executeRequest(respStream(resp))
  ctx.purgeQueries(includeStored = true)
  if res.isErr:
    return err($res.error)

  ok(resp.getString())

proc executeQC(ctx: GraphqlRef) =
  suite "instrument test suite":
    let savePoint = ctx.getNameCounter()
    var qc = QueryComplexity.new(calcQC, 200)
    ctx.addInstrument(qc)

    test "too complex introspection query":
      var res = executeQC(ctx, query1)
      check res.isErr
      check res.error == "@[[2, 1]: Fatal: Instrument Error: query complexity exceed max(200), got 204: @[]]"

    test "too complex eth api query":
      var res = executeQC(ctx, query2)
      check res.isErr
      check res.error == "@[[2, 1]: Fatal: Instrument Error: query complexity exceed max(200), got 204: @[]]"

    ctx.purgeNames(savePoint)

when isMainModule:
  let ctx = setupContext()
  processArguments()
  ctx.main(caseFolder, false)
  ctx.executeQC()
else:
  let ctx = setupContext()
  ctx.executeCases(caseFolder, false)
  ctx.executeQC()
