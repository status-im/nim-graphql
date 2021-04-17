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
  ./graphql

template `@=`(dest: untyped, validator: untyped) =
  let dest {.inject.} = callValidator(ctx, validator)
  if ctx.errKind != ErrNone:
    return respNull()

template invalidNull*(cond: untyped, body: untyped) =
  if cond:
    body
    return respNull()

proc getOperation(ctx: GraphqlRef, opName: string): ExecRef =
  let name = if opName.len == 0: ctx.names.anonName
             else: ctx.names.insert(opName)
  let op = ctx.execTable.getOrDefault(name)
  invalid op.isNil:
    ctx.fatal(ErrOperationNotFound, ctx.emptyNode, name)
  op

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

proc findField(name: Name, input: Node): Node =
  for n in input:
    if n[0].name == name:
      return n

proc fillValue(argType: Node, argVal: Node): Node =
  ## input object fields should arrive at resolver in exact
  ## order as defined in the schema and their missing field
  ## should be filled using default value or empty node.

  if argType.kind == nkNonNullType:
    return fillValue(argType[0], argVal)

  if argType.kind == nkListType:
    let innerType = argType[0]
    for i, n in argVal:
      argVal[i] = fillValue(innerType, n)
    return argVal

  if argVal.kind != nkInput:
    # all other basic datatypes need no ordering or
    # modification, they already filled by the validator
    return argVal

  var res = Node(kind: nkInput, pos: argVal.pos)
  let sym = argType.sym
  assert(sym.kind == skInputObject)
  let tFields = InputObject(sym.ast).fields
  for tField in tFields:
    let iField = findField(tField.name.name, argVal)
    if iField.isNil:
      let val = fillValue(tField.typ, tField.defVal)
      res <- newTree(nkInputField, tField.name, val)
    else:
      let val = fillValue(tField.typ, iField[1])
      res <- newTree(nkInputField, iField[0], val)
  res

proc fillArgs(fieldName: Name, parent: Symbol, args: Args): Args =
  ## params should arrive at resolver in exact order
  ## as defined in the schema and their missing arg should be
  ## filled using default value or empty node.

  let field = getField(parent, fieldName).ObjectField
  let targs = field.args
  var res = Node(kind: nkArguments, pos: Node(args).pos)
  for targ in targs:
    let arg = findArg(targ.name, args)
    if Node(arg).isNil:
      let val = fillValue(targ.typ, targ.defVal)
      res <- newTree(nkPair, targ.name, val)
    else:
      let val = fillValue(targ.typ, arg.val)
      res <- newTree(nkPair, arg.name, val)
  Args(res)

proc executeField(ctx: GraphqlRef, field: FieldRef, parent: Node): Node =
  let parentTypeName = field.parentType.sym.name
  let fieldName = field.field.name
  let resolverSet = ctx.resolver.getOrDefault(parentTypeName)
  invalidNull resolverSet.isNil:
    ctx.fatal(ErrTypeUndefined, field.respName, parentTypeName)
  let resolver = resolverSet.resolvers.getOrDefault(fieldName.name)
  invalidNull resolver.isNil:
    ctx.fatal(ErrNoImpl, field.respName, fieldName, parentTypeName)

  let parentType = field.parentType.sym
  let args = fillArgs(fieldName.name, parentType, field.field.args)
  let res = resolver(resolverSet.ud, args, parent)
  invalidNull res.isErr:
    ctx.fatal(ErrValueError, field.respName, field.name, res.error)

  result ::= completeValue(field.typ, field, res.get)

proc skip(fieldType, parentType: Node, objectName, rootIntros: Name): bool =
  let name = parentType.sym.name
  if name == rootIntros:
    # never skip "__type", "__schema", or "__typename"
    return false
  if fieldType.kind == nkSym and fieldType.sym.kind == skUnion:
    # skip fragment on union that does not match queried type
    return objectName != name

proc executeSelectionSet(ctx: GraphqlRef, fieldSet: FieldSet,
                         parentFieldType, objectType, parent: Node): Node =

  let rootIntros = ctx.rootIntros.sym.name
  let objectName = objectType.sym.name
  let currName = resp($fieldSet[0].respName)
  ctx.path.add currName
  result = respMap(objectName)
  for n in fieldSet:
    if skip(parentFieldType, n.parentType, objectName, rootIntros):
      continue
    currName.stringVal = $n.respName # replace the path name
    let field = ctx.executeField(n, parent)
    result[n.name] = field
    if ctx.errKind != ErrNone:
      break

proc executeQuery(ctx: GraphqlRef, exec: ExecRef, resp: RespStream) =
  let parent = respMap(exec.opType.sym.name)
  let res = ctx.executeSelectionSet(exec.fieldSet,
                       exec.opType, exec.opType, parent)
  serialize(res, resp)

proc executeMutation(ctx: GraphqlRef, exec: ExecRef, resp: RespStream) =
  let parent = respMap(exec.opType.sym.name)
  let res = ctx.executeSelectionSet(exec.fieldSet,
                       exec.opType, exec.opType, parent)
  serialize(res, resp)

proc executeSubscription(ctx: GraphqlRef, exec: ExecRef, resp: RespStream) =
  discard

proc executeRequestImpl(ctx: GraphqlRef, resp: RespStream, opName = "") =
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
    ctx.executeRequestImpl(resp, opName)
  if resp.len == 0:
    # no output, write a null literal
    resp.writeNull()
  if ctx.errKind == ErrNone:
    ok()
  else:
    err(ctx.errors)
