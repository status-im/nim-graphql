# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  std/strutils,
  stew/results,
  ../common/[ast]

proc scalarInt(node: Node): ScalarResult =
  # TODO: validate 32 bit int
  if node.kind == nkInt:
    ok(node)
  else:
    err("expect int, but got '$1'" % [$node.kind])

proc scalarFloat(node: Node): ScalarResult =
  # TODO: validate 64 bit float
  case node.kind
  of nkInt:
    let n = Node(pos: node.pos, kind: nkFloat, floatVal: node.intVal)
    ok(n)
  of nkFloat:
    ok(node)
  else:
    err("expect int or float, but got '$1'" % [$node.kind])

proc scalarString(node: Node): ScalarResult =
  if node.kind == nkString:
    ok(node)
  else:
    err("expect string, but got '$1'" % [$node.kind])

proc scalarBoolean(node: Node): ScalarResult =
  if node.kind == nkBoolean:
    ok(node)
  else:
    err("expect boolean, but got '$1'" % [$node.kind])

proc scalarID(node: Node): ScalarResult =
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
