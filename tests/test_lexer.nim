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
  pkg/[faststreams, unittest2],
  ../graphql/lexer,
  ../graphql/common/names

proc scan(input: string): TokKind =
  var stream = unsafeMemoryInput(input)
  var names = newNameCache()
  var lex = Lexer.init(stream, names)
  lex.next()
  lex.tok

proc scanName(input: string): Keyword =
  var stream = unsafeMemoryInput(input)
  var names = newNameCache()
  var lex = Lexer.init(stream, names)
  lex.next()
  toKeyword(lex.name)

proc initLex(input: string): Lexer =
  var stream = unsafeMemoryInput(input)
  var names = newNameCache()
  result = Lexer.init(stream, names)

template scan(input, expect: string, tk: TokKind) =
  var lex = initLex(input)
  lex.next()
  check lex.tok == tk
  check lex.token == expect

proc suite1() =
  suite "NameCache test suite":
    setup:
      var names = newNameCache()

    test "insert":
      let def = names.insert("INPUT_FIELD_DEFINITION")
      check def.id == Keyword.high.int

      let banana = names.insert("banana")
      let apple = names.insert("apple")
      check banana.id == Keyword.high.int + 1
      check apple.id == Keyword.high.int + 2

    test "remove and resetCounter":
      let banana = names.insert("banana")
      let apple = names.insert("apple")
      check banana.id == Keyword.high.int + 1
      check apple.id == Keyword.high.int + 2

      names.remove(banana)
      names.resetCounter()
      let def = names.insert("INPUT_FIELD_DEFINITION")
      check def.id == Keyword.high.int
      check apple.id == Keyword.high.int + 1

proc suite2() =
  suite "basic lexer test suite":
    test "ellipsis":
      check scan("...") == tokEllipsis
      check scan(".. .") == tokError
      check scan(". ..") == tokError
      check scan("... ") == tokEllipsis
      check scan(" ...") == tokEllipsis

    test "keywords":
      check scanName("directive")     == kwDirective
      check scanName("enum")          == kwEnum
      check scanName("extend")        == kwExtend
      check scanName("false")         == kwFalse
      check scanName("fragment")      == kwFragment
      check scanName("implements")    == kwImplements
      check scanName("input")         == kwInput
      check scanName("interface")     == kwInterface
      check scanName("mutation")      == kwMutation
      check scanName("null")          == kwNull
      check scanName("on")            == kwOn
      check scanName("query")         == kwQuery
      check scanName("scalar")        == kwScalar
      check scanName("schema")        == kwSchema
      check scanName("subscription")  == kwSubscription
      check scanName("true")          == kwTrue
      check scanName("type")          == kwType
      check scanName("union")         == kwUnion

      check scanName("QUERY")               == LocQUERY
      check scanName("MUTATION")            == LocMUTATION
      check scanName("SUBSCRIPTION")        == LocSUBSCRIPTION
      check scanName("FIELD")               == LocFIELD
      check scanName("FRAGMENT_DEFINITION") == LocFRAGMENT_DEFINITION
      check scanName("FRAGMENT_SPREAD")     == LocFRAGMENT_SPREAD
      check scanName("INLINE_FRAGMENT")     == LocINLINE_FRAGMENT

      check scanName("SCHEMA")                  == LocSCHEMA
      check scanName("SCALAR")                  == LocSCALAR
      check scanName("OBJECT")                  == LocOBJECT
      check scanName("FIELD_DEFINITION")        == LocFIELD_DEFINITION
      check scanName("ARGUMENT_DEFINITION")     == LocARGUMENT_DEFINITION
      check scanName("INTERFACE")               == LocINTERFACE
      check scanName("UNION")                   == LocUNION
      check scanName("ENUM")                    == LocENUM
      check scanName("ENUM_VALUE")              == LocENUM_VALUE
      check scanName("INPUT_OBJECT")            == LocINPUT_OBJECT
      check scanName("INPUT_FIELD_DEFINITION")  == LocINPUT_FIELD_DEFINITION

    test "strings":
      check scan("\"basic string\"") == tokString
      scan("\"\\n\\t\"", "\n\t", tokString)
      scan("\"\"\"\\\"\"\"\"\"\"", "\"\"\"", tokBlockString)
      check scan("\"\"\"") == tokError
      scan("\"\"\"\"\"\"", "", tokBlockString)
      scan("\"\"", "", tokString)

      scan("\"\"\"\"P\"\"\"", "\"P", tokBlockString)
      scan("\"\"\"\"\"P\"\"\"", "\"\"P", tokBlockString)

    test "numbers":
      scan("-10", "-10", tokInt)
      scan("10", "10", tokInt)
      scan("-0", "-0", tokInt)
      check scan("-00") == tokError
      check scan("00") == tokError
      scan("10.0", "10.0", tokFloat)
      scan("10.1", "10.1", tokFloat)
      scan("10.1e1", "10.1e1", tokFloat)
      scan("10.1e-1", "10.1e-1", tokFloat)
      scan("10.1e+1", "10.1e+1", tokFloat)
      scan("10.1E1", "10.1E1", tokFloat)
      scan("10.1E-1", "10.1E-1", tokFloat)
      scan("10.1E+1", "10.1E+1", tokFloat)

    test "misc":
      check scan("\"\\uabcdef\"") == tokError
      check scan("#hello") == tokEof

proc suite3() =
  suite "lexing documents":
    var fileNames: seq[string]
    for fileName in walkDirRec("tests" / "schemas"):
      fileNames.add fileName

    for fileName in fileNames:
      test fileName:
        var stream = memFileInput(fileName)
        var names = newNameCache()
        var lex = Lexer.init(stream, names)

        while true:
          lex.next()
          case lex.tok
          of tokEof:
            check true
            break
          of tokError:
            echo "error ", lex.error
            check false
          else:
            discard

        stream.close()

suite1()
suite2()
suite3()
