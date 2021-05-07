# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  std/[unittest, os],
  ../graphql, ./test_utils

const
  schema = """
type Query {
  echoString(arg: String): String
}
"""

  query = """
query banana($mm: String) {
  name: echoString(arg: $mm)
}
"""

  extend = """
extend type SmallChild {
  name: Int
}
"""

proc suite1() =
  suite "misc test suite":
    let ctx = GraphqlRef.new()
    ctx.initMockApi()
    let savePoint = ctx.getNameCounter()
    let r1 = ctx.parseSchema(schema)
    if r1.isErr:
      debugEcho r1.error
      return
    let r2 = ctx.parseQuery(query)
    if r2.isErr:
      debugEcho r2.error
      return
      
    test "parseVariable":
      var res = ctx.parseVar("boolVar", "true")
      check res.isOk
      res = ctx.parseVar("inputObject", "{apple: 123, banana: \"hello\"}")
      check res.isOk
      res = ctx.parseVar("invalid", "\"unclosed string")
      check res.isErr
      check $res.error == "@[[1, 17]: Error: Please terminate string with '\"']"

    test "reusable queries with variables":
      ctx.addVar("mm", "hello")
      var resp = JsonRespStream.new()
      var res = ctx.executeRequest(respStream(resp), "banana")
      check res.isOk
      let resp1 = resp.getString()
      check resp1 == """{"name":"hello"}"""
    
    
      ctx.addVar("mm", "sweet banana")
      resp = JsonRespStream.new()
      res = ctx.executeRequest(respStream(resp), "banana")
      check res.isOk
      let resp2 = resp.getString()
      check resp2 == """{"name":"sweet banana"}"""
      
    test "parseSchemas":
      const
        schemaFile = "tests" / "schemas" / "example_schema.ql"
      ctx.purgeQueries()
      ctx.purgeSchema()
      ctx.purgeNames(savePoint)
      let res = ctx.parseSchemas([schemaFile], [extend])
      check res.isErr
      check $res.error == "@[[2, 3]: Error: duplicate name 'name']"
      
suite1()
