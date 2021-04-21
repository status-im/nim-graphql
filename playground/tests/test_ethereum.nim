# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  std/os,
  ../../graphql, ../ethapi, ../../graphql/test_common

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

when isMainModule:
  let ctx = setupContext()
  processArguments()
  ctx.main(caseFolder, false)
else:
  let ctx = setupContext()
  ctx.executeCases(caseFolder, false)
