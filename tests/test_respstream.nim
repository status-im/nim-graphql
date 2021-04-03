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
  ../graphql/common/respstream,
  ../graphql/builtin/[json_respstream, toml_respstream]

proc suite1() =
  suite "json response stream test suite":
    test "write string":
      var n = newJsonRespStream()
      n.write("hello")
      check n.getOutput() == "\"hello\""

    test "write bool":
      var n = newJsonRespStream()
      n.write(true)
      check n.getOutput() == "true"

    test "write int":
      var n = newJsonRespStream()
      n.write(123)
      check n.getOutput() == "123"

    test "write null":
      var n = newJsonRespStream()
      n.writeNull()
      check n.getOutput() == "null"

    test "write float":
      var n = newJsonRespStream()
      n.write(123.1)
      check n.getOutput() == "123.1"

    test "write array":
      var n = newJsonRespStream()
      respList(n):
        n.write("hello")
        n.write(true)
        n.write(123)
        n.write(123.4)
        n.writeNull()
      check n.getOutput() == "[\"hello\",true,123,123.4,null]"

    test "write array in array":
      var n = newJsonRespStream()
      respList(n):
        n.write("hello")
        n.write(true)
        n.write(123)
        respList(n):
          n.write(123.4)
          n.writeNull()
      check n.getOutput() == "[\"hello\",true,123,[123.4,null]]"

    test "write object in array":
      var n = newJsonRespStream()
      respList(n):
        n.write("hello")
        n.write(true)
        n.write(123)
        n.write(123.4)
        n.writeNull()
        respMap(n):
          n.fieldName("one")
          n.write(123)
      check n.getOutput() == "[\"hello\",true,123,123.4,null,{\"one\":123}]"

    test "write object":
      var n = newJsonRespStream()
      respMap(n):
        n.fieldName("one")
        n.write("hello")
        n.fieldName("two")
        n.write(true)
        n.fieldName("three")
        n.write(123)
        n.fieldName("four")
        n.write(123.4)
        n.fieldName("five")
        n.writeNull()
      check n.getOutput() == "{\"one\":\"hello\",\"two\":true,\"three\":123,\"four\":123.4,\"five\":null}"

    test "write array in object":
      var n = newJsonRespStream()
      respMap(n):
        n.fieldName("one")
        n.write("hello")
        n.fieldName("two")
        n.write(true)
        n.fieldName("three")
        n.write(123)
        n.fieldName("four")
        respList(n):
          n.write(123.4)
          n.writeNull()
      check n.getOutput() == "{\"one\":\"hello\",\"two\":true,\"three\":123,\"four\":[123.4,null]}"

    test "write object in object":
      var n = newJsonRespStream()
      respMap(n):
        n.fieldName("one")
        n.write("hello")
        n.fieldName("two")
        n.write(true)
        n.fieldName("three")
        n.write(123)
        n.fieldName("obj")
        respMap(n):
          n.fieldName("four")
          n.write(123.4)
          n.fieldName("five")
          n.writeNull()
      check n.getOutput() == "{\"one\":\"hello\",\"two\":true,\"three\":123,\"obj\":{\"four\":123.4,\"five\":null}}"

proc suite2() =
  suite "toml response stream test suite":
    test "write string":
      var n = newTomlRespStream()
      n.fieldName("one")
      n.write("hello")
      check n.getOutput() == "one = \"hello\"\n"

    test "write int":
      var n = newTomlRespStream()
      n.fieldName("one")
      n.write(123)
      check n.getOutput() == "one = 123\n"

    test "write bool":
      var n = newTomlRespStream()
      n.fieldName("one")
      n.write(true)
      check n.getOutput() == "one = true\n"

    test "write float":
      var n = newTomlRespStream()
      n.fieldName("one")
      n.write(123.4)
      check n.getOutput() == "one = 123.4\n"

    test "write null":
      var n = newTomlRespStream()
      n.fieldName("one")
      n.writeNull
      check n.getOutput() == ""

    test "write array":
      var n = newTomlRespStream()
      n.fieldName("array")
      respList(n):
        n.write("one")
        n.write(2)
        n.writeNull()
        n.write(true)
        n.write(123.4)
      check n.getOutput() == "array = [\"one\", 2, true, 123.4]\n"

    test "write map":
      var n = newTomlRespStream()
      n.fieldName("map")
      respMap(n):
        n.fieldName("one")
        n.write("one")
        n.fieldName("two")
        n.write(2)
        n.fieldName("three")
        n.writeNull()
        n.fieldName("four")
        n.write(true)
        n.fieldName("five")
        n.write(123.4)
      check n.getOutput() == "[map]\n  one = \"one\"\n  two = 2\n  four = true\n  five = 123.4\n\n"

    test "write inline map":
      var n = newTomlRespStream()
      n.fieldName("map")
      respMap(n):
        n.fieldName("inline")
        respMap(n):
          n.fieldName("one")
          n.write("one")
          n.fieldName("two")
          n.write(2)
          n.fieldName("three")
          n.writeNull()
          n.fieldName("four")
          n.write(true)
          n.fieldName("five")
          n.write(123.4)
      check n.getOutput() == "[map]\n  inline = {one = \"one\", two = 2, four = true, five = 123.4}\n\n"

    test "write inline map in inline map in map":
      var n = newTomlRespStream()
      n.fieldName("map")
      respMap(n):
        n.fieldName("inline")
        respMap(n):
          n.fieldName("one")
          n.write("one")
          n.fieldName("two")
          n.write(2)
          n.fieldName("three")
          n.writeNull()
          n.fieldName("inmap")
          respMap(n):
            n.fieldName("four")
            n.write(true)
            n.fieldName("five")
            n.write(123.4)
      check n.getOutput() == "[map]\n  inline = {one = \"one\", two = 2, inmap = {four = true, five = 123.4}}\n\n"

    test "write array in map":
      var n = newTomlRespStream()
      n.fieldName("map")
      respMap(n):
        n.fieldName("array")
        respList(n):
          n.write("one")
          n.write(2)
          n.writeNull()
          n.write(true)
          n.write(123.4)
      check n.getOutput() == "[map]\n  array = [\"one\", 2, true, 123.4]\n\n"

    test "write array in array in map":
      var n = newTomlRespStream()
      n.fieldName("map")
      respMap(n):
        n.fieldName("array")
        respList(n):
          n.write("one")
          n.write(2)
          n.writeNull()
          n.write(true)
          n.write(123.4)
          respList(n):
            n.write(456)
      check n.getOutput() == "[map]\n  array = [\"one\", 2, true, 123.4, [456]]\n\n"

    test "write array in inline map in map pos 2":
      var n = newTomlRespStream()
      n.fieldName("map")
      respMap(n):
        n.fieldName("inline")
        respMap(n):
          n.fieldName("one")
          n.write(2)
          n.fieldName("two")
          respList(n):
            n.write(456)
      check n.getOutput() == "[map]\n  inline = {one = 2, two = [456]}\n\n"

    test "write array in inline map in map pos 1":
      var n = newTomlRespStream()
      n.fieldName("map")
      respMap(n):
        n.fieldName("inline")
        respMap(n):
          n.fieldName("two")
          respList(n):
            n.write(456)
          n.fieldName("one")
          n.write(2)
      check n.getOutput() == "[map]\n  inline = {two = [456], one = 2}\n\n"

    test "write inline map in array in map pos 2":
      var n = newTomlRespStream()
      n.fieldName("map")
      respMap(n):
        n.fieldName("array")
        respList(n):
          n.write(2)
          respMap(n):
            n.fieldName("four")
            n.write(true)
            n.fieldName("five")
            n.write(123.4)
      check n.getOutput() == "[map]\n  array = [2, {four = true, five = 123.4}]\n\n"

    test "write inline map in array in map pos 1":
      var n = newTomlRespStream()
      n.fieldName("map")
      respMap(n):
        n.fieldName("array")
        respList(n):
          respMap(n):
            n.fieldName("four")
            n.write(true)
            n.fieldName("five")
            n.write(123.4)
          n.write(2)
      check n.getOutput() == "[map]\n  array = [{four = true, five = 123.4}, 2]\n\n"

suite1()
suite2()
