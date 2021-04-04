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

proc respMap*(pos: Pos): Node =
  Node(kind: nkMap, pos: pos)

proc respList*(pos: Pos): Node =
  Node(kind: nkList, pos: pos)

proc respNull*(pos: Pos): Node =
  Node(kind: nkNull, pos: pos)

proc resp*(x: string, pos: Pos): Node =
  Node(kind: nkString, stringVal: x, pos: pos)

proc resp*(x: int, pos: Pos): Node =
  Node(kind: nkInt, intVal: $x, pos: pos)

proc resp*(x: bool, pos: Pos): Node =
  Node(kind: nkBoolean, boolVal: x, pos: pos)

proc resp*(x: float64, pos: Pos): Node =
  Node(kind: nkFloat, floatVal: $x, pos: pos)

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
    doAssert(false, "unreachable code")
