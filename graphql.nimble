# nim-graphql
# Copyright (c) 2021-2024 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

mode = ScriptMode.Verbose

packageName   = "graphql"
version       = "0.2.30"
author        = "Status Research & Development GmbH"
description   = "GraphQL parser, server and client implementation"
license       = "Apache License 2.0"
skipDirs      = @["tests", "resources", "fuzzer", "docs", "playground"]

requires "nim >= 1.6.0",
         "faststreams",
         "stew",
         "json_serialization",
         "chronicles",
         "https://github.com/status-im/nim-zlib",
         "unittest2",
         "https://github.com/status-im/nim-chronos#head",
         "https://github.com/status-im/nim-bearssl#head"

proc test(args, path: string, shouldRun = true) =
  # Compilation language is controlled by TEST_LANG
  let nimc = getEnv("NIMC", "nim") # Which nim compiler to use
  let lang = getEnv("NIMLANG", "c") # Which backend (c/cpp/js)
  let flags = getEnv("NIMFLAGS", "") # Extra flags for the compiler
  let verbose = getEnv("V", "") notin ["", "0"]

  let run = if shouldRun: " -r" else: ""
  let cfg = " --styleCheck:usages --styleCheck: error" &
            (if verbose: "" else: " --verbosity:0 --hints:off") & run &
            " -d:unittest2DisableParamFiltering"

  exec nimc & " " & lang & " " & cfg & " " & flags & " " & args & " " & path
  if (NimMajor, NimMinor) > (1, 6):
    exec nimc & " " & lang & " " & cfg & " --mm:refc " & flags & " " & args & " " & path

task test, "Run all tests":
  test "--threads:off", "tests/test_all"
  test "--threads:on", "tests/test_all"
  test "--threads:off -d:release", "tests/test_all"
  test "--threads:on -d:release", "tests/test_all"
  test "--threads:off -d:release -d:tls", "tests/test_httpserver"
  test "--threads:on -d:release -d:tls", "tests/test_httpserver"
  test "-d:release", "playground/swserver", false
  test "-d:release", "playground/tests/test_all"
  test "--threads:on -d:release", "playground/tests/test_all"

proc playground(server: string) =
  exec "nim c -r -d:release playground/swserver " & server

task ethereum, "run Ethereum playground server":
  playground("ethereum")

task starwars, "run starwars playground server":
  playground("starwars")
