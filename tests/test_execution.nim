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
  ../graphql, ../graphql/test_common, ./test_utils

const
  caseFolder = "tests" / "execution"

proc setupContext(): GraphqlRef =
  var ctx = new(GraphqlRef)
  ctx.initMockApi()
  ctx

when isMainModule:
  let ctx = setupContext()
  processArguments()
  ctx.main(caseFolder, true)
else:
  let ctx = setupContext()
  ctx.executeCases(caseFolder, true)
