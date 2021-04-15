# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  strutils,
  ./types

type
  ErrorLevel* = enum
    elNone    = "no error"
    elError   = "Error"
    elFatal   = "Fatal"
    elWarning = "Warning"
    elHint    = "Hint"

  ErrorDesc* = object
    level*: ErrorLevel
    pos*: Pos
    message*: string

proc `$`*(x: ErrorDesc): string =
  "[$1, $2]: $3: $4" % [$x.pos.line,
    $x.pos.col, $x.level, x.message]
