# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  std/[parseopt, strutils, uri],
  stew/results, chronos

type
  Schema* = enum
    starwars
    ethereum

  Configuration* = ref object
    bindAddress*: TransportAddress
    schema*: Schema

var testConfig {.threadvar.}: Configuration

const
  defaultAddress = initTAddress("127.0.0.1:8547")

proc initConfiguration(): Configuration =
  result = new Configuration
  result.bindAddress = defaultAddress
  result.schema = starwars

proc getConfiguration*(): Configuration {.gcsafe.} =
  if isNil(testConfig):
    testConfig = initConfiguration()
  result = testConfig

proc processArguments*(): Result[Configuration, string] =
  var
    opt = initOptParser()
    config = getConfiguration()

  for kind, key, value in opt.getopt():
    case kind
    of cmdArgument:
      try:
        config.schema = parseEnum[Schema](key)
      except Exception as e:
        return err(e.msg)
    of cmdLongOption, cmdShortOption:
      case key.toLowerAscii()
      of "bind", "b":
        try:
          config.bindAddress = initTAddress(value)
        except Exception as e:
          return err(e.msg)
      else:
        var msg = "Unknown option " & key
        if value.len > 0: msg = msg & " : " & value
        return err(msg)
    of cmdEnd:
      doAssert(false)

  ok(config)
