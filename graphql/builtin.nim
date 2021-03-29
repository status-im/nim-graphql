# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  ./common/[ast]

proc scalarInt(node: Node, param: var ScalarParam): bool =
  # TODO: validate 32 bit int
  param.expectedTypes = {nkInt}
  if node.kind == nkInt:
    param.outNode = node
    return true
  return false

proc scalarFloat(node: Node, param: var ScalarParam): bool =
  # TODO: validate 64 bit float
  param.expectedTypes = {nkInt, nkFloat}
  case node.kind
  of nkInt:
    param.outNode = Node(pos: node.pos, kind: nkFloat, floatVal: node.intVal)
    return true
  of nkFloat:
    param.outNode = node
    return true
  else:
    return false

proc scalarString(node: Node, param: var ScalarParam): bool =
  param.expectedTypes = {nkString}
  if node.kind == nkString:
    param.outNode = node
    return true
  return false

proc scalarBoolean(node: Node, param: var ScalarParam): bool =
  param.expectedTypes = {nkBoolean}
  if node.kind == nkBoolean:
    param.outNode = node
    return true
  return false

proc scalarID(node: Node, param: var ScalarParam): bool =
  param.expectedTypes = {nkInt, nkString}
  case node.kind
  of nkInt:
    param.outNode = Node(
      pos: node.pos,
      kind: nkCustomScalar,
      stringVal: node.intVal
    )
    return true
  of nkString:
    param.outNode = Node(
      pos: node.pos,
      kind: nkCustomScalar,
      stringVal: node.stringVal
    )
    return true
  else:
    return false

const
  builtinScalars* = {
    "Int": scalarInt,
    "Float": scalarFloat,
    "String": scalarString,
    "Boolean": scalarBoolean,
    "ID": scalarID
  }
