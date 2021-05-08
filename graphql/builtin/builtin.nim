# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  std/[strutils, parseutils],
  stew/results,
  ../common/[ast],
  ../graphql

proc validateInt32(x: string): Result[void, string] =
  var pos  = 0
  var sign = if x[0] == '-':
               inc pos
               -1
             else:
               1
  var b = 0.int64
  while pos < x.len:
    b = b * 10 + int64(x[pos]) - int64('0')
    if b > high(uint32).int64:
      break
    inc pos

  if sign == 1 and b > high(int32).int64:
    return err("Int overflow")

  if sign * b < low(int32).int64:
    return err("Int overflow")

  ok()

proc scalarInt(ctx: GraphqlRef, typeNode, node: Node): NodeResult {.cdecl, gcsafe, nosideEffect.} =
  if node.kind == nkInt:
    let res = validateInt32(node.intVal)
    if res.isErr:
      err(res.error)
    else:
      ok(node)
  else:
    err("expect int, but got '$1'" % [$node.kind])

proc scalarFloat(ctx: GraphqlRef, typeNode, node: Node): NodeResult {.cdecl, gcsafe, nosideEffect.} =
  case node.kind
  of nkInt:
    let n = Node(pos: node.pos, kind: nkFloat, floatVal: node.intVal)
    ok(n)
  of nkFloat:
    var number: float
    let L = parseFloat(node.floatVal, number)
    if L != node.floatVal.len or L == 0:
      return err("'$1' is not a valid float" % [node.floatVal])
    ok(node)
  else:
    err("expect int or float, but got '$1'" % [$node.kind])

proc scalarString(ctx: GraphqlRef, typeNode, node: Node): NodeResult {.cdecl, gcsafe, nosideEffect.} =
  if node.kind == nkString:
    ok(node)
  else:
    err("expect string, but got '$1'" % [$node.kind])

proc scalarBoolean(ctx: GraphqlRef, typeNode, node: Node): NodeResult {.cdecl, gcsafe, nosideEffect.} =
  if node.kind == nkBoolean:
    ok(node)
  else:
    err("expect boolean, but got '$1'" % [$node.kind])

proc scalarID(ctx: GraphqlRef, typeNode, node: Node): NodeResult {.cdecl, gcsafe, nosideEffect.} =
  case node.kind
  of nkInt:
    let n = Node(
      pos: node.pos,
      kind: nkString,
      stringVal: node.intVal
    )
    ok(n)
  of nkString:
    ok(node)
  else:
    err("expect int or string, but got '$1'" % [$node.kind])

const
  builtinScalars* = {
    "Int": scalarInt,
    "Float": scalarFloat,
    "String": scalarString,
    "Boolean": scalarBoolean,
    "ID": scalarID
  }
