# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  ./ast, ./types, ./names

proc respMap*(name: Name): Node =
  Node(kind: nkMap, pos: Pos(), typeName: name)

proc respList*(): Node =
  Node(kind: nkList, pos: Pos())

proc respNull*(): Node =
  Node(kind: nkNull, pos: Pos())

proc resp*(): Node =
  Node(kind: nkEmpty, pos: Pos())

proc resp*(x: Symbol): Node =
  Node(kind: nkSym, sym: x, pos: Pos())

proc resp*(x: string): Node =
  Node(kind: nkString, stringVal: x, pos: Pos())

proc resp*(x: int): Node =
  Node(kind: nkInt, intVal: $x, pos: Pos())

proc resp*(x: bool): Node =
  Node(kind: nkBoolean, boolVal: x, pos: Pos())

proc resp*(x: float64): Node =
  Node(kind: nkFloat, floatVal: $x, pos: Pos())
