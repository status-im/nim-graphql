# nim-graphql
# Copyright (c) 2021-2025 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

type
  Pos* = object
    line*: uint16
    col*: uint16

  LoopGuard* = object
    maxLoop*: int
    desc*: string

func `<`*(a: Pos, b: Pos): bool =
  if a.line == b.line:
    return a.col < b.col
  a.line < b.line
