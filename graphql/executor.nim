# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  std/[tables, strutils],
  stew/[results],
  ./common/[names, ast, ast_helper, response, respstream],
  ./graphql, ./validator

template `@=`(dest: untyped, validator: untyped) =
  let dest {.inject.} = callValidator(ctx, validator)
  if ctx.errKind != ErrNone:
    return respNull()

template invalidNull*(cond: untyped, body: untyped) =
  if cond:
    body
    return respNull()

proc name(field: FieldRef): string =
  $field.respName.name

proc coerceScalar(ctx: GraphqlRef, fieldName, fieldType, resval: Node): Node =
  scalar @= getScalar(fieldType)
  let res = ctx.scalar(fieldType, resval)
  if res.isErr:
    ctx.error(ErrScalarError, fieldName, resval, res.error)
    respNull()
  else:
    res.get()

proc coerceEnum(ctx: GraphqlRef, fieldName, fieldType, resval: Node): Node =
  if resval.kind != nkString:
    ctx.error(ErrScalarError, fieldName, resval,
              "expect '$1' got '$2'" % [$fieldType, $resval.kind])
    return respNull()
  let name = ctx.names.insert(resval.stringVal)
  if fieldType.sym.enumVals.hasKey(name):
    return resval
  respNull()

proc getTypeName(ctx: GraphqlRef, field: FieldRef, node: Node): Name =
  case node.kind
  of nkString:
    result = ctx.names.insert(node.stringVal)
  of nkSym:
    result = node.sym.name
  of nkName, nkNamedType:
    result = node.name
  of nkMap:
    result = node.typeName
  else:
    ctx.fatal(ErrIncompatType, field.respName, field.field.name,
              resObjValidKind,  node.kind)

proc resolveAbstractType(ctx: GraphqlRef, field: FieldRef,
                         fieldType: Node, resval: Node): Node =
  typeName := getTypeName(field, resval)

  if fieldType.sym.kind == skUnion:
    let members = Union(fieldType.sym.ast).members
    for n in members:
      if n.sym.name == typeName:
        return n
  else:
    for n in fieldType.sym.types:
      if n.sym.name == typeName:
        return n

  ctx.fatal(ErrIncompatType, field.field.name, fieldType, resval.typeName)

proc executeSelectionSet(ctx: GraphqlRef, fieldSet: FieldSet,
                         parentFieldType, objectType, parent: Node): Node

proc completeValue(ctx: GraphqlRef, fieldType: Node,
                   field: FieldRef, resval: Node): Node =
  if fieldType.kind == nkNonNullType:
    let innerType = fieldType[0]
    result ::= completeValue(innerType, field, resval)
    invalid result.kind == nkNull:
      ctx.fatal(ErrNotNullable, field.respName, field.field.name)
    return

  if resval.kind == nkNull:
    return resval

  if fieldType.kind == nkListType:
    invalid resval.kind != nkList:
      ctx.fatal(ErrIncompatType, field.respName,
                field.field.name, nkList, resval.kind)
    let innerType = fieldType[0]
    var res = respList()
    let index = resp(0)
    ctx.path.add index
    for i, resItem in resval:
      index.intVal = $i # replace path node with the current index
      let resultItem = ctx.completeValue(innerType, field, resItem)
      if resultItem.kind == nkMap and resultItem.map.len == 0:
        # if the resultItem have no fields, it means it is not
        # matching the current fragment type, don't put it
        # in the list
        continue
      res.add resultItem
      if ctx.errKind != ErrNone:
        break
    return res

  doAssert(fieldType.kind == nkSym,
           "internal error, requires fieldType == nkSym")

  case fieldType.sym.kind
  of skScalar:
    result ::= coerceScalar(field.respName, fieldType, resval)
  of skEnum:
    result ::= coerceEnum(field.respName, fieldType, resval)
  of skObject:
    result ::= executeSelectionSet(field.fieldSet,
                                   fieldType, fieldType, resval)
  of skInterface, skUnion:
    objectType @= resolveAbstractType(field, fieldType, resval)
    result ::= executeSelectionSet(field.fieldSet,
                                   fieldType, objectType, resval)
  else:
    unreachable()

proc executeField(ctx: GraphqlRef, field: FieldRef, parent: Node): Node =
  let parentTypeName = field.parentType.sym.name
  let fieldName = field.field.name
  let resolverSet = ctx.resolver.getOrDefault(parentTypeName)
  invalidNull resolverSet.isNil:
    ctx.fatal(ErrTypeUndefined, field.respName, parentTypeName)
  let resolver = resolverSet.resolvers.getOrDefault(fieldName.name)
  invalidNull resolver.isNil:
    ctx.fatal(ErrNoImpl, field.respName, fieldName, parentTypeName)

  let res = resolver(resolverSet.ud, field.field.args, parent)
  invalidNull res.isErr:
    ctx.fatal(ErrValueError, field.respName, field.name, res.error)

  result ::= completeValue(field.typ, field, res.get)

proc equalsOrImplement(objName: Name, parentType: Node): bool =
  if objName == parentType.sym.name:
    return true

  if parentType.sym.kind == skInterface:
    for n in parentType.sym.types:
      if n.sym.name == objName:
        return true

proc skip(fieldType, parentType: Node, objectName, rootIntros: Name): bool =
  let parent = parentType.sym.name
  if parent == rootIntros:
    # never skip "__type", "__schema", or "__typename"
    return false

  if fieldType.kind == nkSym and fieldType.sym.kind in {skUnion, skInterface}:
    # skip fragment on union that does not match queried type
    return not equalsOrImplement(objectName, parentType)

proc executeSelectionSet(ctx: GraphqlRef, fieldSet: FieldSet,
                         parentFieldType, objectType, parent: Node): Node =

  let rootIntros = ctx.rootIntros.sym.name
  let objectName = objectType.sym.name
  let currName = resp($fieldSet[0].respName)
  ctx.path.add currName
  result = respMap(objectName)
  var errKind = ErrNone
  for n in fieldSet:
    if skip(parentFieldType, n.parentType, objectName, rootIntros):
      continue
    currName.stringVal = $n.respName # replace the path name
    let field = ctx.executeField(n, parent)
    result[n.name] = field
    if ctx.errKind != ErrNone:
      # we don't want to stop when there is error
      errKind = ctx.errKind
      ctx.errKind = ErrNone

  # if there is error, keep it
  ctx.errKind = errKind
  
proc executeQuery(ctx: GraphqlRef, exec: ExecRef, resp: var Node) =
  let parent = respMap(exec.opType.sym.name)
  resp = ctx.executeSelectionSet(exec.fieldSet,
                       exec.opType, exec.opType, parent)

proc executeMutation(ctx: GraphqlRef, exec: ExecRef, resp: var Node) =
  let parent = respMap(exec.opType.sym.name)
  resp = ctx.executeSelectionSet(exec.fieldSet,
                       exec.opType, exec.opType, parent)

proc executeSubscription(ctx: GraphqlRef, exec: ExecRef, resp: var Node) =
  discard

proc executeRequestImpl(ctx: GraphqlRef, resp: var Node, opName = "") =
  ctx.path = respList()
  exec := getOperation(opName)
  case exec.opSym.sym.kind
  of skQuery:        visit executeQuery(exec, resp)
  of skMutation:     visit executeMutation(exec, resp)
  of skSubscription: visit executeSubscription(exec, resp)
  else:
    unreachable()

proc executeRequest*(ctx: GraphqlRef, resp: RespStream,
                     opName = ""): GraphqlResult {.gcsafe.} =
  {.gcsafe.}:
    var res = respNull()
    ctx.executeRequestImpl(res, opName)
    resp.serialize(res)

  if ctx.errKind == ErrNone:
    ok()
  else:
    err(ctx.errors)
