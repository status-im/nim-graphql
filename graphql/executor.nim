# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  std/[tables],
  stew/[results],
  ./common/[names, ast, ast_helper, response, respstream],
  ./graphql

# errors
# data
# extensions

proc getOperation(ctx: GraphqlRef, opName: string): ExecRef =
  let name = if opName.len == 0: ctx.names.anonName
             else: ctx.names.insert(opName)
  let op = ctx.execTable.getOrDefault(name)
  invalid op.isNil:
    ctx.fatal(ErrOperationNotFound, name)
  op

proc name(field: FieldRef): string =
  $field.respName.name

proc coerceScalar(ctx: GraphqlRef, fieldType: Node, resval: Node): Node =
  scalar := getScalar(fieldType)
  let res = scalar.parseLit(resval)
  if res.isErr:
    respNull()
  else:
    res.get()

proc coerceEnum(ctx: GraphqlRef, fieldType: Node, resval: Node): Node =
  let name = ctx.names.insert(resval.stringVal)
  if fieldType.sym.enumVals.hasKey(name):
    return resval
  respNull()

proc resolveAbstractType(ctx: GraphqlRef, field: FieldRef, fieldType: Node, resval: Node): Node =
  invalid resval.kind != nkMap:
    ctx.fatal(ErrIncompatType, field.field.name, nkMap, resval.kind)

  if fieldType.sym.kind == skUnion:
    let members = Union(fieldType.sym.ast).members
    for n in members:
      if n.sym.name == resval.typeName:
        return n
  else:
    for n in fieldType.sym.types:
      if n.sym.name == resval.typeName:
        return n

  ctx.fatal(ErrIncompatType, field.field.name, fieldType, resval.typeName)

proc executeSelectionSet(ctx: GraphqlRef, fieldSet: FieldSet,
                         parentFieldType, objectType, parent: Node): Node

proc completeValue(ctx: GraphqlRef, fieldType: Node, field: FieldRef, resval: Node): Node =
  if fieldType.kind == nkNonNullType:
    let innerType = fieldType[0]
    result ::= completeValue(innerType, field, resval)
    invalid result.kind == nkNull:
      ctx.fatal(ErrNotNullable, field.field.name)
    return

  if resval.kind == nkNull:
    return resval

  if fieldType.kind == nkListType:
    invalid resval.kind != nkList:
      ctx.fatal(ErrIncompatType, field.field.name, nkList, resval.kind)
    let innerType = fieldType[0]
    var res = respList()
    for resItem in resval:
      resultItem := completeValue(innerType, field, resItem)
      res.add resultItem
    return res

  doAssert(fieldType.kind == nkSym, "internal error, requires fieldType == nkSym")

  case fieldType.sym.kind
  of skScalar:
    result ::= coerceScalar(fieldType, resval)
  of skEnum:
    result ::= coerceEnum(fieldType, resval)
  of skObject:
    result ::= executeSelectionSet(field.fieldSet, fieldType, fieldType, resval)
  of skInterface, skUnion:
    objectType := resolveAbstractType(field, fieldType, resval)
    result ::= executeSelectionSet(field.fieldSet, fieldType, objectType, resval)
  else:
    unreachable()

proc fillArgs(fieldName: Name, parent: Symbol, args: Args): Args =
  let field = getField(parent, fieldName).ObjectField
  let targs = field.args
  var res = Node(kind: nkArguments, pos: Node(args).pos)
  for targ in targs:
    let arg = findArg(targ.name, args)
    if Node(arg).isNil:
      res <- newTree(nkPair, targ.name, targ.defVal)
    else:
      res <- Node(arg)
  Args(res)

proc executeField(ctx: GraphqlRef, field: FieldRef, parent: Node): Node =
  let parentTypeName = field.parentType.sym.name
  let fieldName = field.field.name
  let resolverSet = ctx.resolver.getOrDefault(parentTypeName)
  invalid resolverSet.isNil:
    ctx.fatal(ErrTypeUndefined, parentTypeName)
  let resolver = resolverSet.resolvers.getOrDefault(fieldName.name)
  invalid resolver.isNil:
    ctx.fatal(ErrNoImpl, fieldName, parentTypeName)

  let parentType = field.parentType.sym
  let args = fillArgs(fieldName.name, parentType, field.field.args)
  let res = resolver(resolverSet.ud, args, parent)
  invalid res.isErr:
    ctx.fatal(ErrValueError, field.name, res.error)

  result ::= completeValue(field.typ, field, res.get)

proc skip(fieldType, parentType: Node, objectName, rootIntros: Name): bool =
  let name = parentType.sym.name
  if name == rootIntros:
    return false
  if fieldType.kind == nkSym and fieldType.sym.kind == skUnion:
    return objectName != name

proc executeSelectionSet(ctx: GraphqlRef, fieldSet: FieldSet,
                         parentFieldType, objectType, parent: Node): Node =

  let rootIntros = ctx.rootIntros.sym.name
  let objectName = objectType.sym.name
  result = respMap(objectName)
  for n in fieldSet:
    if skip(parentFieldType, n.parentType, objectName, rootIntros):
      continue
    field := executeField(n, parent)
    result[n.name] = field

proc executeQuery(ctx: GraphqlRef, exec: ExecRef, resp: RespStream) =
  res := executeSelectionSet(exec.fieldSet, exec.opType, exec.opType, nil)
  serialize(res, resp)

proc executeMutation(ctx: GraphqlRef, exec: ExecRef, resp: RespStream) =
  res := executeSelectionSet(exec.fieldSet, exec.opType, exec.opType, nil)
  serialize(res, resp)

proc executeSubscription(ctx: GraphqlRef, exec: ExecRef, resp: RespStream) =
  discard

proc executeRequestImpl(ctx: GraphqlRef, resp: RespStream, opName = "") =
  exec := getOperation(opName)
  case exec.opSym.sym.kind
  of skQuery:        visit executeQuery(exec, resp)
  of skMutation:     visit executeMutation(exec, resp)
  of skSubscription: visit executeSubscription(exec, resp)
  else:
    unreachable()

proc executeRequest*(ctx: GraphqlRef, resp: RespStream, opName = ""): ParseResult =
  ctx.executeRequestImpl(resp, opName)
  if ctx.errKind == ErrNone:
    ok()
  else:
    err(ctx.err)
