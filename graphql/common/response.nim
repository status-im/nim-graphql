# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  ./ast, ./respstream, ./types

proc respMap*(): Node =
  Node(kind: nkMap, pos: Pos())

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

proc serialize*(n: Node, resp: RespStream) =
  case n.kind
  of nkNull:
    resp.writeNull
  of nkBoolean:
    resp.write(n.boolVal)
  of nkInt:
    resp.write(n.intVal)
  of nkFloat:
    resp.write(n.floatVal)
  of nkString:
    resp.write(n.stringVal)
  of nkList:
    respList(resp):
      for x in n:
        serialize(x, resp)
  of nkMap:
    respMap(resp):
      for k, v in n.mapPair:
        resp.fieldName(k)
        serialize(v, resp)
  else:
    doAssert(false, $n.kind & " sould not appear in resp stream")
