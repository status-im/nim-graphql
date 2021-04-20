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
  ../../graphql, ../swapi, ./test_common

const
  caseFolder = "playground" / "tests" / "starwars"

proc setupContext(): GraphqlRef =
  var ctx = new(GraphqlRef)
  ctx.initStarWarsApi()
  let res = ctx.parseSchemaFromFile("tests" / "schemas" / "star_wars_schema.ql")
  if res.isErr:
    debugEcho res.error
    quit(QuitFailure)
  ctx

when isMainModule:
  let ctx = setupContext()
  processArguments()
  ctx.main(caseFolder)
else:
  let ctx = setupContext()
  ctx.executeCases(caseFolder)
