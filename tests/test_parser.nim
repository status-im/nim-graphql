# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  os,
  faststreams/inputs,
  unittest,
  ../graphql/[query_parser, schema_parser, parser],
  ../graphql/common/errors

template runQuery(query: string) =
  var stream = unsafeMemoryInput(query)
  var parser = Parser.init(stream)
  var doc: QueryDocument
  parser.parseDocument(doc)
  check parser.error == errNone

template runBadQuery(query, errmsg: string) =
  var stream = unsafeMemoryInput(query)
  var parser = Parser.init(stream)
  var doc: QueryDocument
  parser.parseDocument(doc)
  let desc = parser.errDesc()
  check $desc == errmsg

template runSchema(input: string) =
  var stream = unsafeMemoryInput(input)
  var parser = Parser.init(stream)
  var doc: SchemaDocument
  parser.parseDocument(doc)
  check parser.error == errNone

template runBadSchema(input, errmsg: string) =
  var stream = unsafeMemoryInput(input)
  var parser = Parser.init(stream)
  var doc: SchemaDocument
  parser.parseDocument(doc)
  let desc = parser.errDesc()
  check $desc == errmsg

proc suite1() =
  suite "query parser test":
    test "bad query":
      runBadQuery("query !", "[1, 7]: Error: get '!', expect '{'")
      runBadQuery("query \"abc", "[1, 11]: Error: Please terminate string with '\"'")
      runBadQuery("query {}", "[1, 8]: Error: get '}', expect Name")      
      runBadQuery("query myquery($__mm) { name }", "[1, 16]: Error: get '__mm', expect name without '__' prefix in this context")

    test "good query":
      runQuery("query __myquery { name }")
      runQuery("query Mega($a: Int! = 10) @deprecated { hero: human(a: 10) {id ,name } }")

proc suite2() =
  suite "schema parser test":
    test "good schema":
      runSchema("union abc")
      runSchema("union abc = apple")
      runSchema("type myquery { name: __string }")

    test "bad schema":
      runBadSchema("union abc = ", "[1, 13]: Error: get EOF, expect Name")      

proc runGoodDoc(fileName: string): bool =
  var doc: FullDocument
  var stream = memFileInput(fileName)
  var parser = Parser.init(stream)
  parser.flags.incl pfAcceptReservedWords
  parser.parseDocument(doc)
  stream.close()
  if parser.error != errNone:
    debugEcho parser.errDesc()
  parser.error == errNone

proc suite3() =
  suite "full parser test: good documents":
    for fileName in walkDirRec("tests" / "schemas"):
      test fileName:
        check runGoodDoc(fileName) == true

suite1()
suite2()
suite3()
