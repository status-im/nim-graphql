# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  parseopt, strutils

type
  ConfigStatus* = enum
    ## Configuration status flags
    Success,                      ## Success
    EmptyOption,                  ## No options in category
    ErrorUnknownOption,           ## Unknown option in command line found
    ErrorParseOption,             ## Error in parsing command line option
    ErrorIncorrectOption,         ## Option has incorrect value
    Error                         ## Unspecified error

  Configuration = ref object
    testFile*: string
    unit*: string
    convertPath*: string

{.push gcsafe, raises: [].}

var testConfig {.threadvar.}: Configuration

proc initConfiguration(): Configuration =
  result = new Configuration

proc getConfiguration*(): Configuration {.gcsafe.} =
  if isNil(testConfig):
    testConfig = initConfiguration()
  result = testConfig

proc processArguments*(msg: var string): ConfigStatus =
  var
    opt = initOptParser()
    config = getConfiguration()

  result = Success
  for kind, key, value in opt.getopt():
    case kind
    of cmdArgument:
      config.testFile = key
    of cmdLongOption, cmdShortOption:
      case key.toLowerAscii()
      of "unit", "u": config.unit = value
      of "convert", "c": config.convertPath = value
      else:
        msg = "Unknown option " & key
        if value.len > 0: msg = msg & " : " & value
        result = ErrorUnknownOption
        break
    of cmdEnd:
      doAssert(false)

{.pop.}
