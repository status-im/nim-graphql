# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  unittest,
  ../graphql/api

proc suite1() =
  suite "misc test suite":
    test "parseVariable":
      var ctx = GraphqlRef.new()
      var res = ctx.parseVar("boolVar", "true")
      check res.isOk
      res = ctx.parseVar("inputObject", "{apple: 123, banana: \"hello\"}")
      check res.isOk
      res = ctx.parseVar("invalid", "\"unclosed string")
      check res.isErr
      check $res.error == "@[[1, 17]: Error: Please terminate string with '\"']"

suite1()
