# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  pkg/[unittest2],
  ../graphql/common/[respstream, response, ast],
  ../graphql/builtin/[json_respstream, toml_respstream]

proc suite1() =
  suite "json response stream test suite":
    test "write raw string":
      var n = JsonRespStream.new()
      n.writeRaw("hello")
      check n.len == 5
      check n.getString() == "hello"

    test "write string":
      var n = JsonRespStream.new()
      n.write("hello")
      check n.getString() == "\"hello\""

    test "write bool":
      var n = JsonRespStream.new()
      n.write(true)
      check n.getString() == "true"

    test "write int":
      var n = JsonRespStream.new()
      n.write(123)
      check n.getString() == "123"

    test "write null":
      var n = JsonRespStream.new()
      n.writeNull()
      check n.getString() == "null"

    test "write float":
      var n = JsonRespStream.new()
      n.write(123.1)
      check n.getString() == "123.1"

    test "write array":
      var n = JsonRespStream.new()
      respList(n):
        n.write("hello")
        n.write(true)
        n.write(123)
        n.write(123.4)
        n.writeNull()
      check n.getString() == "[\"hello\",true,123,123.4,null]"

    test "write array in array":
      var n = JsonRespStream.new()
      respList(n):
        n.write("hello")
        n.write(true)
        n.write(123)
        respList(n):
          n.write(123.4)
          n.writeNull()
      check n.getString() == "[\"hello\",true,123,[123.4,null]]"

    test "write object in array":
      var n = JsonRespStream.new()
      respList(n):
        n.write("hello")
        n.write(true)
        n.write(123)
        n.write(123.4)
        n.writeNull()
        respMap(n):
          n.field("one")
          n.write(123)
      check n.getString() == "[\"hello\",true,123,123.4,null,{\"one\":123}]"

    test "write objects in array":
      var n = JsonRespStream.new()
      respList(n):
        respMap(n):
          n.field("hello")
          n.write(true)
          n.field("world")
          n.writeNull()
        respMap(n):
          n.field("one")
          n.write(123)
      check n.getString() == "[{\"hello\":true,\"world\":null},{\"one\":123}]"

    test "write object":
      var n = JsonRespStream.new()
      respMap(n):
        n.field("one")
        n.write("hello")
        n.field("two")
        n.write(true)
        n.field("three")
        n.write(123)
        n.field("four")
        n.write(123.4)
        n.field("five")
        n.writeNull()
      check n.getString() == "{\"one\":\"hello\",\"two\":true,\"three\":123,\"four\":123.4,\"five\":null}"

    test "write array in object":
      var n = JsonRespStream.new()
      respMap(n):
        n.field("one")
        n.write("hello")
        n.field("two")
        n.write(true)
        n.field("three")
        n.write(123)
        n.field("four")
        respList(n):
          n.write(123.4)
          n.writeNull()
      check n.getString() == "{\"one\":\"hello\",\"two\":true,\"three\":123,\"four\":[123.4,null]}"

    test "write object in object":
      var n = JsonRespStream.new()
      respMap(n):
        n.field("one")
        n.write("hello")
        n.field("two")
        n.write(true)
        n.field("three")
        n.write(123)
        n.field("obj")
        respMap(n):
          n.field("four")
          n.write(123.4)
          n.field("five")
          n.writeNull()
      check n.getString() == "{\"one\":\"hello\",\"two\":true,\"three\":123,\"obj\":{\"four\":123.4,\"five\":null}}"

proc suite2() =
  suite "toml response stream test suite":
    test "write raw string":
      var n = TomlRespStream.new()
      n.field("one")
      n.writeRaw("123")
      check n.len == 10
      check n.getString() == "one = 123\n"

    test "write string":
      var n = TomlRespStream.new()
      n.field("one")
      n.write("hello")
      check n.getString() == "one = \"hello\"\n"

    test "write int":
      var n = TomlRespStream.new()
      n.field("one")
      n.write(123)
      check n.getString() == "one = 123\n"

    test "write bool":
      var n = TomlRespStream.new()
      n.field("one")
      n.write(true)
      check n.getString() == "one = true\n"

    test "write float":
      var n = TomlRespStream.new()
      n.field("one")
      n.write(123.4)
      check n.getString() == "one = 123.4\n"

    test "write null":
      var n = TomlRespStream.new()
      n.field("one")
      n.writeNull
      check n.getString() == ""

    test "write array":
      var n = TomlRespStream.new()
      n.field("array")
      respList(n):
        n.write("one")
        n.write(2)
        n.writeNull()
        n.write(true)
        n.write(123.4)
      check n.getString() == "array = [\"one\", 2, true, 123.4]\n"

    test "write map":
      var n = TomlRespStream.new()
      n.field("map")
      respMap(n):
        n.field("one")
        n.write("one")
        n.field("two")
        n.write(2)
        n.field("three")
        n.writeNull()
        n.field("four")
        n.write(true)
        n.field("five")
        n.write(123.4)
      check n.getString() == "[map]\n  one = \"one\"\n  two = 2\n  four = true\n  five = 123.4\n\n"

    test "write inline map":
      var n = TomlRespStream.new()
      n.field("map")
      respMap(n):
        n.field("inline")
        respMap(n):
          n.field("one")
          n.write("one")
          n.field("two")
          n.write(2)
          n.field("three")
          n.writeNull()
          n.field("four")
          n.write(true)
          n.field("five")
          n.write(123.4)
      check n.getString() == "[map]\n  inline = {one = \"one\", two = 2, four = true, five = 123.4}\n\n"

    test "write inline map in inline map in map":
      var n = TomlRespStream.new()
      n.field("map")
      respMap(n):
        n.field("inline")
        respMap(n):
          n.field("one")
          n.write("one")
          n.field("two")
          n.write(2)
          n.field("three")
          n.writeNull()
          n.field("inmap")
          respMap(n):
            n.field("four")
            n.write(true)
            n.field("five")
            n.write(123.4)
      check n.getString() == "[map]\n  inline = {one = \"one\", two = 2, inmap = {four = true, five = 123.4}}\n\n"

    test "write array in map":
      var n = TomlRespStream.new()
      n.field("map")
      respMap(n):
        n.field("array")
        respList(n):
          n.write("one")
          n.write(2)
          n.writeNull()
          n.write(true)
          n.write(123.4)
      check n.getString() == "[map]\n  array = [\"one\", 2, true, 123.4]\n\n"

    test "write array in array in map":
      var n = TomlRespStream.new()
      n.field("map")
      respMap(n):
        n.field("array")
        respList(n):
          n.write("one")
          n.write(2)
          n.writeNull()
          n.write(true)
          n.write(123.4)
          respList(n):
            n.write(456)
      check n.getString() == "[map]\n  array = [\"one\", 2, true, 123.4, [456]]\n\n"

    test "write array in inline map in map pos 2":
      var n = TomlRespStream.new()
      n.field("map")
      respMap(n):
        n.field("inline")
        respMap(n):
          n.field("one")
          n.write(2)
          n.field("two")
          respList(n):
            n.write(456)
      check n.getString() == "[map]\n  inline = {one = 2, two = [456]}\n\n"

    test "write array in inline map in map pos 1":
      var n = TomlRespStream.new()
      n.field("map")
      respMap(n):
        n.field("inline")
        respMap(n):
          n.field("two")
          respList(n):
            n.write(456)
          n.field("one")
          n.write(2)
      check n.getString() == "[map]\n  inline = {two = [456], one = 2}\n\n"

    test "write inline map in array in map pos 2":
      var n = TomlRespStream.new()
      n.field("map")
      respMap(n):
        n.field("array")
        respList(n):
          n.write(2)
          respMap(n):
            n.field("four")
            n.write(true)
            n.field("five")
            n.write(123.4)
      check n.getString() == "[map]\n  array = [2, {four = true, five = 123.4}]\n\n"

    test "write inline map in array in map pos 1":
      var n = TomlRespStream.new()
      n.field("map")
      respMap(n):
        n.field("array")
        respList(n):
          respMap(n):
            n.field("four")
            n.write(true)
            n.field("five")
            n.write(123.4)
          n.write(2)
      check n.getString() == "[map]\n  array = [{four = true, five = 123.4}, 2]\n\n"

proc suite3() =
  suite "response stream serialization from node":
    var map = respMap(nil)
    var list = respList()
    list.add respNull()
    list.add resp(123)
    list.add resp(123.4)
    map["1"] = list
    map["2"] = resp("hello")
    map["3"] = resp(123)
    map["4"] = resp(true)
    map["5"] = resp(456.7)

    test "json serialization":
      var resp = JsonRespStream.new()
      resp.serialize(map)
      check resp.getString() == "{\"1\":[null,123,123.4],\"2\":\"hello\",\"3\":123,\"4\":true,\"5\":456.7}"

    test "toml serialization":
      var resp = TomlRespStream.new()
      resp.serialize(map)
      const toml_out = "[]\n  1 = [123, 123.4]\n  2 = \"hello\"\n  3 = 123\n  4 = true\n  5 = 456.7\n\n"
      check resp.getString() == toml_out

suite1()
suite2()
suite3()
