# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  std/json,
  json_serialization

type
  ServerResponse* = object
    errors*: JsonNode
    data*: JsonNode    
  
proc decodeResponse*(input: string): ServerResponse =
  Json.decode(input, ServerResponse)

proc removeWhitespaces*(x: string): string =
  # TODO: do not remove white spaces in string/multiline string
  const whites = {' ', '\t', '\r', '\n'}
  for c in x:
    if c notin whites:
      result.add c
