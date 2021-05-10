# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  std/[tables, sets, os],
  stew/results,
  ./common/[ast, names, errors, ast_helper],
  ./graphql

const
  introsKeywords = {introsSchema, introsType, introsTypeName}

proc `$$`(node: Node): string =
  case node.kind
  of nkNonNullType:
    return $$(node[0]) & "!"
  of nkListType:
    return "[" & $$(node[0]) & "]"
  of nkSym:
    return $node.sym.name
  of nkNamedType:
    return $node.name
  else:
    unreachable()

proc `$$`(kind: set[NodeKind] | set[SymKind]): string =
  if card(kind) == 1:
    let res = $kind
    substr(res, 1, res.len-2)
  else:
    $kind

proc assignRootOp(ctx: GraphqlRef, name: Name, sym: Node) =
  case toKeyword(name)
  of kwRootQuery, kwQuery: ctx.rootQuery = sym
  of kwRootMutation, kwMutation: ctx.rootMutation = sym
  of kwRootSubscription, kwSubscription: ctx.rootSubs = sym
  else: discard

template noNameDup(n: Node, names: HashSet[Name]) =
  invalid n.name in names:
    ctx.error(ErrDuplicateName, n)
  names.incl n.name

proc getName(node: Node): Name =
  case node.kind
  of NamedNodes: return node.name
  of nkSym: return node.sym.name
  else: unreachable()

template noCyclic(n: Node, names: var HashSet[Name]) =
  invalid getName(n) in names:
    ctx.error(ErrCyclicReference, n)
  names.incl getName(n)

template noCyclicSetup(visited: untyped, n: Node) =
  var visited {.inject.} = initHashSet[Name]()
  visited.incl getName(n)

proc findType(ctx: GraphqlRef, name: Node, types: set[SymKind]): Node =
  let sym = findType(name.name)
  invalid sym.isNil:
    ctx.error(ErrTypeUndefined, name)
  invalid sym.sym.kind notin types:
    ctx.error(ErrTypeMismatch, name, sym.sym.kind, $$types)
  sym

proc findType(ctx: GraphqlRef, name: Node, typ: SymKind): Node =
  let sym = findType(name.name)
  invalid sym.isNil:
    ctx.error(ErrTypeUndefined, name)
  invalid sym.sym.kind != typ:
    ctx.error(ErrTypeMismatch, name, sym.sym.kind, typ)
  sym

proc findOp(ctx: GraphqlRef, name: Node, typ: SymKind): Node =
  let sym = findOp(name.name)
  invalid sym.isNil:
    ctx.error(ErrTypeUndefined, name)
  invalid sym.sym.kind != typ:
    ctx.error(ErrTypeMismatch, name, sym.sym.kind, typ)
  sym

proc isWhatType(ctx: GraphqlRef, parent: Node, idx: int, whatTypes: set[SymKind]) =
  let node = parent[idx]
  case node.kind
  of nkNonNullType:
    visit isWhatType(node, 0, whatTypes)
  of nkListType:
    visit isWhatType(node, 0, whatTypes)
  of nkNamedType:
    sym := findType(node, whatTypes)
    # dup sym, for better error message
    parent[idx] = newSymNode(sym.sym, node.pos)
  else:
    unreachable()

template isOutputType(ctx: GraphqlRef, node: Node, idx: int) =
  ctx.isWhatType(node, idx, OutputTypes)

template isInputType(ctx: GraphqlRef, node: Node, idx: int) =
  ctx.isWhatType(node, idx, InputTypes)

proc findField(ctx: GraphqlRef, T: type, sym: Symbol, name: Node): T =
  # for object, interface, and input object only!
  let field = sym.getField(name.name)
  invalid field.isNil:
    ctx.error(ErrNotPartOf, name, sym.name)
  T(field)

proc findField(name: Name, inputVal: Node): Node =
  for n in inputVal:
    if n[0].name == name:
      return n

proc findField(ctx: GraphqlRef, sym: Symbol, name, iName: Node): ObjectField =
  let field = sym.getField(name.name)
  invalid field.isNil:
    ctx.error(ErrFieldIsRequired, name, sym.name, iName)
  ObjectField(field)

proc findArg(ctx: GraphqlRef, parentType, fieldName, argName: Node, targs: Arguments): Argument =
  for arg in targs:
    if arg.name.name == argName.name:
      return arg
  ctx.error(ErrFieldArgUndefined, argName, fieldName, parentType)

proc findArg(ctx: GraphqlRef, dirName, argName: Node, targs: Arguments): Argument =
  for arg in targs:
    if arg.name.name == argName.name:
      return arg
  ctx.error(ErrDirArgUndefined, argName, dirName)

proc coerceVar(ctx: GraphqlRef, nameNode, locType, parent: Node, idx: int) =
  var inVal = parent[idx]
  let coerce = ctx.getCoercion(locType)
  if coerce.isNil:
    # skip coercion if not available
    return
  let res = ctx.coerce(locType, inVal)
  invalid res.isErr:
    ctx.error(ErrScalarError, nameNode, inVal, res.error)
  parent[idx] = res.get()

proc coerceEnum(ctx: GraphqlRef, locType, nameNode, parent: Node, idx: int, isVar: bool) =
  if isVar:
    visit coerceVar(nameNode, locType, parent, idx)
  let inVal = parent[idx]
  invalid inVal.kind != nkEnum:
    if inval.kind == nkList:
      ctx.error(ErrTypeMismatch, nameNode, inVal.kind, locType)
    else:
      ctx.error(ErrEnumError, nameNode, inVal, inVal.kind, locType)

  # desc, enumval, dirs
  invalid locType.sym.enumVals.getOrDefault(inVal.name).isNil:
    ctx.error(ErrNotPartOf, inVal, locType)

proc findVar(ctx: GraphqlRef, val: Node, scope: Node): Variable =
  let varsym = scope.sym.vars.getOrDefault(val.name)
  invalid varsym.isNil:
    ctx.error(ErrNotPartOf, val, scope)
  varsym.sym.flags.incl sfUsed
  Variable(varsym.sym.ast)

proc areTypesCompatible(varType, locType: Node): bool =
  if locType.kind == nkNonNullType:
    if varType.kind != nkNonNullType:
      return false
    let nullableLocType = locType[0]
    let nullableVarType = varType[0]
    return areTypesCompatible(nullableVarType, nullableLocType)

  if varType.kind == nkNonNullType:
    let nullableVarType = varType[0]
    return areTypesCompatible(nullableVarType, locType)

  if locType.kind == nkListType:
    if varType.kind != nkListType:
      return false
    let itemLocType = locType[0]
    let itemVarType = varType[0]
    return areTypesCompatible(itemVarType, itemlocType)

  if varType.kind == nkListType:
    return false

  varType.kind == locType.kind and
    varType.kind == nkSym and
    varType.sym.name == locType.sym.name

proc variableUsageAllowed(ctx: GraphqlRef, nameNode: Node, varDef: Variable,
                          varName, locType, locDefVal: Node) =
  let varType = varDef.typ
  if locType.kind == nkNonNullType and varType.kind != nkNonNullType:
    let defVal = varDef.defVal
    let hasNonNullVariableDefaultValue = defVal.kind notin {nkEmpty, nkNull}
    let hasLocationDefaultValue = locDefVal.kind != nkEmpty
    invalid not hasNonNullVariableDefaultValue and not hasLocationDefaultValue:
      ctx.error(ErrNotNullable, varName, nameNode, "variable")
    let nullableLocType = locType[0]
    if not areTypesCompatible(varType, nullableLocType):
      ctx.error(ErrTypeMismatch, varName, $$varType, $$nullableLocType)
    return
  if not areTypesCompatible(varType, locType):
    ctx.error(ErrTypeMismatch, varName, $$varType, $$locType)

proc inputCoercion(ctx: GraphqlRef, nameNode, locType, locDefVal,
                   parent: Node; idx: int, scope = Node(nil), isVar = false)

proc coerceInputObject(ctx: GraphqlRef, nameNode: Node,
                       sym: Symbol, inVal: Node, scope: Node, isVar: bool) =
  invalid inVal.kind != nkInput:
    ctx.error(ErrTypeMismatch, nameNode, inVal.kind, sym.name)

  # desc, name, dirs, fields
  let inp = InputObject(sym.ast)
  let fields = inp.fields
  var names = initHashSet[Name]()
  for field in inVal:
    # name, value
    let name = field[0]
    let val = field[1]
    noNameDup(name, names)
    inputField := findField(InputField, sym, name)
    let locType = inputField.typ
    let dv = inputField.defVal
    var isVar = isVar # shadowing to modify
    if val.kind == nkVariable:
      isVar = true
      if scope.sym.kind == skFragment and val.name notin scope.sym.vars:
        # the variable probably used by other op
        continue
      varDef := findVar(val, scope)
      visit variableUsageAllowed(name, varDef, val, locType, dv)
      let rtVal = ctx.varTable.getOrDefault(val.name)
      if rtVal.isNil:
        let defVal = varDef.defVal
        if defVal.kind == nkEmpty:
          field[1] = dv
        else:
          field[1] = defVal
      else:
        field[1] = rtVal
    visit inputCoercion(name, locType, dv, field, 1, scope, isVar)

  for field in fields:
    let name = field.name
    let valField = findField(name.name, inVal)
    if not valField.isNil: continue
    let dv = field.defVal
    invalid not nullableType(field.typ) and dv.kind == nkEmpty:
      ctx.error(ErrFieldNotinArg, nameNode, name)
    if dv.kind != nkEmpty:
      inVal <- newTree(nkInputField, name, dv)

proc coerceVariable(ctx: GraphqlRef, nameNode, locType, locDefVal,
                    parent: Node; idx: int, scope: Node) =
  let inVal = parent[idx]
  varDef := findVar(inVal, scope)
  visit variableUsageAllowed(nameNode, varDef, inVal, locType, locDefVal)
  let defVal = varDef.defVal
  let rtVal = ctx.varTable.getOrDefault(inVal.name)
  if rtVal.isNil:
    if defVal.kind != nkEmpty:
      parent[idx] = defVal
    else:
      invalid not nullableType(locType):
        ctx.error(ErrValueError, nameNode, nkEmpty)
      parent[idx] = defVal
  else:
    rtVal.pos = inVal.pos
    parent[idx] = rtVal

proc inputCoercion(ctx: GraphqlRef, nameNode, locType, locDefVal,
                   parent: Node; idx: int, scope = Node(nil), isVar = false) =
  var inVal = parent[idx]
  var isVar = isVar # shadowing to modify

  case inVal.kind
  of nkEmpty:
    return
  of nkVariable:
    isVar = true
    doAssert(not scope.isNil)
    if scope.sym.kind == skFragment and inVal.name notin scope.sym.vars:
      # the variable probably used by other op
      return
    visit coerceVariable(nameNode, locType, locDefVal, parent, idx, scope)
    inVal = parent[idx] # probably updated by coerceVariable
    if inVal.kind == nkEmpty:
      return
  else:
    discard

  case locType.kind
  of nkNonNullType:
    invalid inVal.kind == nkNull:
      ctx.error(ErrValueError, nameNode, nkNull)
    visit inputCoercion(nameNode, locType[0], locDefVal, parent, idx, scope, isVar)
  of nkListType:
    case inVal.kind:
    of nkNull:
      return
    of nkList:
      for i in 0..<inVal.len:
        invalid locType[0].kind == nkListType and inVal[i].kind != nkList:
          ctx.error(ErrValueError, nameNode, nkList)
        visit inputCoercion(nameNode, locType[0], locDefVal, inVal, i, scope, isVar):
    else:
      var newList = newTree(nkList, inVal)
      parent[idx] = newList
      visit inputCoercion(nameNode, locType[0], locDefVal, newList, 0, scope, isVar)
  of nkSym:
    let sym = locType.sym
    if inVal.kind == nkNull:
      return
    case sym.kind
    of skScalar:
      if isVar:
        visit coerceVar(nameNode, locType, parent, idx)
        inVal = parent[idx] # probably updated by coerceVar
      scalar := getScalar(locType)
      let res = ctx.scalar(locType, inVal)
      invalid res.isErr:
        ctx.error(ErrScalarError, nameNode, inVal, res.error)
      parent[idx] = res.get()
    of skEnum:
      visit coerceEnum(locType, nameNode, parent, idx, isVar):
    of skInputObject:
      visit coerceInputObject(nameNode, sym, inVal, scope, isVar):
    else:
      unreachable()
  else:
    unreachable()

proc visitOp(ctx: GraphqlRef, parent: Node, idx: int, sk: SymKind) =
  # name, vars, dirs, sels, [typeCond]
  let node = parent[idx]
  let name = node[0]
  doAssert(name.kind == nkName)

  invalid findOp(name.name) != nil:
    ctx.error(ErrDuplicateName, name)

  let symNode = newSymNode(sk, name.name, node, name.pos)
  ctx.opTable[name.name] = symNode
  parent[idx] = symNode

proc visitType(ctx: GraphqlRef, parent: Node, idx: int, sk: SymKind) =
  # desc, name, ...
  let node = parent[idx]
  let name = node[1]
  doAssert(name.kind == nkName)

  invalid findType(name.name) != nil:
    ctx.error(ErrDuplicateName, name)

  let symNode = newSymNode(sk, name.name, node, name.pos)
  ctx.typeTable[name.name] = symNode
  parent[idx] = symNode

  let sym = symNode.sym
  case sk
  of skEnum:
    let vals = Enum(node).values
    for val in vals:
      sym.enumVals[val.name.name] = Node(val)
  of skInputObject:
    let fields = InputObject(node).fields
    for field in fields:
      sym.inputFields[field.name.name] = Node(field)
  else:
    discard

proc dirArgs(ctx: GraphqlRef, scope, dirName: Node, args: Args, targs: Arguments) =
  for arg in args:
    targ := findArg(dirName, arg.name, targs)
    visit inputCoercion(arg.name, targ.typ, targ.defVal, arg.Node, 1, scope)

  for targ in targs:
    let typ = targ.typ
    let defVal = targ.defVal
    if not nullableType(typ) and defVal.kind == nkEmpty:
      let arg = findArg(targ.name, args)
      invalid Node(arg).isNil:
        ctx.error(ErrNoArg, dirName, targ.name)

proc directivesUsage(ctx: GraphqlRef, dirs: Dirs, dirLoc: DirLoc, scope = Node(nil)) =
  var names = initHashSet[Name]()
  for dir in dirs:
    let name = dir.name
    case name.kind
    of nkName:
      symNode := findType(name, skDirective)
      let sym  = symNode.sym
      invalid name.name in names and sfRepeatable notin sym.flags:
        ctx.error(ErrDuplicateName, name)
      names.incl name.name
      invalid dirLoc notin sym.dirLocs:
        ctx.error(ErrDirectiveMisLoc, name, dirLoc)
      # dup sym, for better error message
      Node(dir)[0] = newSymNode(sym, name.pos)
      let tDir = Directive(sym.ast)
      visit dirArgs(scope, name, dir.args, tDir.args)
    of nkSym:
      invalid name.sym.name in names and sfRepeatable notin name.sym.flags:
        ctx.error(ErrDuplicateName, name)
      names.incl name.sym.name
      let tDir = Directive(name.sym.ast)
      visit dirArgs(scope, tDir.name, dir.args, tDir.args)
    else:
      unreachable()

proc validateArgs(ctx: GraphqlRef, args: Arguments) =
  # desc, argName, argType, defVal, dirs
  var names = initHashSet[Name]()
  for arg in args:
    let name = arg.name
    noNameDup(name, names)
    visit isInputType(arg.Node, 2)
    visit inputCoercion(name, arg.typ, arg.defVal, arg.Node, 3)
    visit directivesUsage(arg.dirs, dlARGUMENT_DEFINITION)

proc visitSchema(ctx: GraphqlRef, node: Schema) =
  # desc, name, dirs, members
  let members = node.members
  var names = initHashSet[Name]()
  for n in members:
    doAssert(n.kind == nkPair)
    let opKind = n[0]
    let opName = n[1]
    noNameDup(opKind, names)
    sym := findType(opName, skObject)
    ctx.assignRootOp(opKind.name, sym)

  visit directivesUsage(node.dirs, dlSCHEMA)

proc visitScalar(ctx: GraphqlRef, node: Scalar) =
  # desc, name, dirs
  visit directivesUsage(node.dirs, dlSCALAR)

proc visitImplements(ctx: GraphqlRef, imp: Node) =
  var names = initHashSet[Name]()
  # check object implements valid interface
  for i, name in imp:
    doAssert(name.kind == nkNamedType)
    noNameDup(name, names)
    imp[i] ::= findType(name, skInterface)

proc visitFields(ctx: GraphqlRef, fields: ObjectFields, sym: Symbol) =
  var names = initHashSet[Name]()
  for field in fields:
    # desc, name, args, type, dirs
    let name = field.name
    sym.setField(name.name, field.Node)
    noNameDup(name, names)
    visit validateArgs(field.args)
    visit isOutputType(field.Node, 3)
    visit directivesUsage(field.dirs, dlFIELD_DEFINITION)

proc visitObject(ctx: GraphqlRef, obj: Object, symNode: Node) =
  # desc, name, ifaces, dirs, fields
  let sym = symNode.sym
  ctx.assignRootOp(sym.name, symNode)
  visit visitImplements(obj.implements)
  visit directivesUsage(obj.dirs, dlOBJECT)
  visit visitFields(obj.fields, sym)

proc sameType(this: Node, that: Node): bool =
  case this.kind
  of nkNonNullType, nkListType:
    if this.kind != that.kind:
      return false
    return sameType(this[0], that[0])
  of nkSym:
    if this.kind != that.kind:
      return false
    if this.sym.kind != that.sym.kind:
      return false
    if this.sym.name != that.sym.name:
      return false
    return true
  else:
    unreachable()
  return true

func isUnionMember(typ, uniType: Node): bool =
  let uni = Union(uniType.sym.ast)
  let members = uni.members
  for n in members:
    if n.sym.name == typ.sym.name:
      return true

func hasImplement(fieldType, thatType: Node): bool =
  # this can be object or interface
  # but it doesn't matter here
  let obj = Object(fieldType.sym.ast)
  let impls = obj.implements
  for n in impls:
    let iface = Interface(n.sym.ast)
    if iface.name.name == thatType.sym.name:
      return true

proc validFieldType(fieldType, thatType: Node): bool =
  case fieldType.kind
  of nkNonNullType:
    let nullableType = fieldType[0]
    let thatNullableType = if thatType.kind == nkNonNullType:
                              thatType[0]
                           else:
                              thatType
    return validFieldType(nullableType, thatNullableType)
  of nkListType:
    if thatType.kind != nkListType:
      return false
    let itemType = fieldType[0]
    let thatItemType = thatType[0]
    return validFieldType(itemType, thatItemType)
  of nkSym:
    if thatType.kind != nkSym:
      return false
    if fieldType.sym.kind == thatType.sym.kind:
      return fieldType.sym.name == thatType.sym.name
    elif fieldType.sym.kind == skObject and thatType.sym.kind == skUnion:
      return isUnionMember(fieldType, thatType)
    elif fieldType.sym.kind in {skObject, skInterface} and thatType.sym.kind == skInterface:
      return hasImplement(fieldType, thatType)
    else:
      return false
  else:
    unreachable()

proc isValidImplementation(ctx: GraphqlRef, impls: Node, symNode: Node) =
  for n in impls:
    let iface = Interface(n.sym.ast)
    # desc, name, ifaces, dirs, fields
    let thatFields = iface.fields
    let thatName = iface.name
    for thatField in thatFields:
      # desc, name, args, type, dirs
      let thatFieldName = thatField.name
      thisField := findField(symNode.sym, thatFieldName, iface.name)
      let thatArgs = thatField.args
      let thisArgs = thisField.args
      var args = initHashSet[Name]()
      for arg in thatArgs:
        # desc, argName, argType, defVal, dirs
        let argName = arg.name
        let argType = arg.typ
        let thisArgType = findArg(argName, thisArgs)
        invalid thisArgType.isNil:
          ctx.error(ErrNoArg, thisField.name, argName)
        invalid not sameType(thisArgType, argType):
          ctx.error(ErrArgTypeMismatch, argName, thisField.name, thatName)
        args.incl argName.name

      for arg in thisArgs:
        let argName = arg.name
        let argType = arg.typ
        invalid argName.name notin args and not nullableType(argType):
          ctx.error(ErrValueError, argName, nkNull)

      invalid not validFieldType(thisField.typ, thatField.typ):
        ctx.error(ErrIncompatType, thisField.name, thatName)

    visit isValidImplementation(iface.implements, symNode)

proc objectObject(ctx: GraphqlRef, symNode: Node) =
  # desc, name, ifaces, dirs, fields
  let node = Object(symNode.sym.ast)
  visit isValidImplementation(node.implements, symNode)

proc cyclicInterface(ctx: GraphqlRef, impls: Node, visited: var HashSet[Name]) =
  for n in impls:
    let imp = Interface(n.sym.ast)
    let name = imp.name
    noCyclic(name, visited)
    visit cyclicInterface(imp.implements, visited)

proc hasImplements(astNode: Node, name: Name): bool =
  let impls = Object(astNode).implements
  for n in impls:
    if n.sym.name == name:
      return true
    if hasImplements(n.sym.ast, name):
      return true

proc fillPossibleTypes(ctx: GraphqlRef, symNode: Node) =
  if symNode.sym.types.len > 0:
    return

  let name = symNode.sym.name
  for sym in values(ctx.typeTable):
    if sym.sym.kind notin {skObject, skInterface}:
      continue
    if hasImplements(sym.sym.ast, name):
      symNode.sym.types.add sym

proc interfaceInterface(ctx: GraphqlRef, symNode: Node) =
  # desc, name, ifaces, dirs, fields
  let node = Interface(symNode.sym.ast)
  noCyclicSetup(visited, symNode)
  visit cyclicInterface(node.implements, visited)
  visit isValidImplementation(node.implements, symNode)
  ctx.fillPossibleTypes(symNode)

proc visitInterface(ctx: GraphqlRef, node: Interface, sym: Symbol) =
  # desc, name, ifaces, dirs, fields
  visit visitImplements(node.implements)
  visit directivesUsage(node.dirs, dlINTERFACE)
  visit visitFields(node.fields, sym)

proc visitUnion(ctx: GraphqlRef, node: Union) =
  # desc, name, dirs, members

  # only object can be union member
  var names = initHashSet[Name]()
  let members = node.members
  for i, name in members:
    noNameDup(name, names)
    members[i] ::= findType(name, skObject)

  # validate directives
  visit directivesUsage(node.dirs, dlUNION)

proc visitEnum(ctx: GraphqlRef, node: Enum) =
  # desc, name, dirs, vals

  # no duplicate enum value for this enum
  var names = initHashSet[Name]()
  let vals = node.values
  for val in vals:
    let name = val.name
    noNameDup(name, names)
    visit directivesUsage(val.dirs, dlENUM_VALUE)

  # validate directives
  visit directivesUsage(node.dirs, dlENUM)

proc inputInput(ctx: GraphqlRef, node: Node, visited: var HashSet[Name], nullableCount: int) =
  case node.kind
  of nkNonNullType:
    visit inputInput(node[0], visited, nullableCount)
  of nkListType:
    visit inputInput(node[0], visited, nullableCount)
  of nkSym:
    if node.sym.name in visited:
      invalid nullableCount == 0:
        ctx.error(ErrCyclicReference, node)
      # stop the recursion and return
      return
    visited.incl node.sym.name
    if node.sym.kind != skInputObject:
      return
    let inp = InputObject(node.sym.ast)
    let fields = inp.fields
    for field in fields:
      let typ = field.typ
      let nCount = nullableType(typ).int
      visit inputInput(typ, visited, nullableCount + nCount)
  else:
    unreachable()

proc inputInput(ctx: GraphqlRef, symNode: Node) =
  let inp = InputObject(symNode.sym.ast)
  let fields = inp.fields
  for field in fields:
    # desc, name, type, defVal, dirs
    let name = field.name
    let typ  = field.typ
    let nullableCount = nullableType(typ).int
    noCyclicSetup(visited, symNode)
    visit inputInput(typ, visited, nullableCount)
    visit inputCoercion(name, typ, field.defVal, field.Node, 3)

proc visitInputObject(ctx: GraphqlRef, inp: InputObject) =
  # desc, name, dirs, fields
  visit directivesUsage(inp.dirs, dlINPUT_OBJECT)

  var names = initHashSet[Name]()
  let fields = inp.fields
  for field in fields:
    # desc, name, type, defVal, dirs
    let name = field.name
    noNameDup(name, names)
    visit isInputType(field.Node, 2)
    visit directivesUsage(field.dirs, dlINPUT_FIELD_DEFINITION)

proc directiveFlags(ctx: GraphqlRef, symNode: Node) =
  if symNode.kind == nkEmpty:
    return

  let sym = symNode.sym
  let dir = Directive(sym.ast)
  # desc, name, args, repeatable, locs
  if dir.repeatable.kind != nkEmpty:
    sym.flags.incl sfRepeatable

  let locs = dir.locs
  for n in locs:
    let loc = DirLoc(n.name.id - LocQUERY.int)
    sym.dirLocs.incl loc

proc cyclicDirective(ctx: GraphqlRef, node: Node, visited: var HashSet[Name]) =
  # simply look into every nodes
  # because it's very complicated
  # if we use specialized code for each schema type
  # referenced by the arguments' directives
  case node.kind:
  of NoSonsNodes - {nkSym}:
    discard
  of nkSym:
    let sym = node.sym
    if sym.kind == skDirective:
      noCyclic(node, visited)
    visit cyclicDirective(sym.ast, visited)
  else:
    for n in node:
      visit cyclicDirective(n, visited)

proc directiveDirective(ctx: GraphqlRef, symNode: Node) =
  let dir = Directive(symNode.sym.ast)
  let args = dir.args
  for arg in args:
    # desc, argName, argType, defVal, dirs
    noCyclicSetup(va, symNode)
    visit cyclicDirective(arg.dirs.Node, va)
    noCyclicSetup(vb, symNode)
    visit cyclicDirective(arg.typ, vb)

proc visitDirective(ctx: GraphqlRef, node: Directive) =
  visit validateArgs(node.args)

proc visitTypeCond(ctx: GraphqlRef, parent: Node, idx: int) =
  let node = parent[idx]
  case node.kind
  of nkNamedType:
    sym := findType(node, TypeConds)
    # dup sym, for better error message
    parent[idx] = newSymNode(sym.sym, node.pos)
  of nkSym:
    discard
  else:
    unreachable()

proc fragmentInOp(ctx: GraphqlRef, sels: Node, visited: var HashSet[Name], scope: Node)

proc validateSpreadUsage(ctx: GraphqlRef, parent: Node, idx: int, visited: var HashSet[Name], scope: Node) =
  let name = parent[idx]
  case name.kind
  of nkName:
    noCyclic(name, visited)
    sym := findOp(name, skFragment)
    sym.sym.flags.incl sfUsed
    # dup sym, but replace pos
    # for better
    parent[idx] = newSymNode(sym.sym, name.pos)
    let frag = Fragment(sym.sym.ast)
    visit fragmentInOp(frag.sels, visited, scope)
  of nkSym:
    let frag = Fragment(name.sym.ast)
    noCyclic(name, visited)
    visit fragmentInOp(frag.sels, visited, scope)
  else:
    unreachable()

proc fragmentInOp(ctx: GraphqlRef, sels: Node, visited: var HashSet[Name], scope: Node) =
  for field in sels:
    # the `visited` shadowing here is to prevent
    # wrong cyclic detectection for each branch.
    # Visited branch should not affect next branch
    var visited = visited
    case field.kind
    of nkFragmentSpread:
      # fragName, dirs
      let frag = FragmentSpread(field)
      visit validateSpreadUsage(field, 0, visited, scope)
      visit directivesUsage(frag.dirs, dlFRAGMENT_SPREAD, scope)
    of nkInlineFragment:
      # typeCond, dirs, sels
      let frag = InlineFragment(field)
      visit visitTypeCond(field, 0)
      visit directivesUsage(frag.dirs, dlINLINE_FRAGMENT, scope)
      visit fragmentInOp(frag.sels, visited, scope)
    of nkField:
      # alias, name, args, dirs, sels
      let field = Field(field)
      var names = initHashSet[Name]()
      let args = field.args
      for arg in args:
        let name = arg.name
        noNameDup(name, names)
      visit directivesUsage(field.dirs, dlFIELD, scope)
      visit fragmentInOp(field.sels, visited, scope)
    else:
      unreachable()

proc validVarDef(ctx: GraphqlRef, nameNode, locType, defVal: Node) =
  let rtVal = ctx.varTable.getOrDefault(nameNode.name)
  if rtVal.isNil and defVal.kind == nkEmpty:
    invalid not nullableType(locType):
      ctx.error(ErrValueError, nameNode, nkEmpty)

proc validateVariables(ctx: GraphqlRef, vars: Variables, sym: Symbol) =
  var names = initHashSet[Name]()
  for varDef in vars:
    # name, type, defVal, dirs
    let name = varDef.name
    noNameDup(name, names)
    visit isInputType(varDef.Node, 1)
    visit validVarDef(name, varDef.typ, varDef.defVal)
    visit inputCoercion(name, varDef.typ, varDef.defVal, varDef.Node, 2)
    visit directivesUsage(varDef.dirs, dlVARIABLE_DEFINITION)
    sym.vars[name.name] = newSymNode(skVariable, name.name, varDef.Node, name.pos)

proc visitQuery(ctx: GraphqlRef, symNode: Node) =
  # name, vars, dirs, sels
  let node = Query(symNode.sym.ast)
  visit validateVariables(node.vars, symNode.sym)
  visit directivesUsage(node.dirs, dlQUERY, symNode)
  noCyclicSetup(visited, symNode)
  visit fragmentInOp(node.sels, visited, symNode)

proc visitMutation(ctx: GraphqlRef, symNode: Node) =
  # name, vars, dirs, sels
  let node = Mutation(symNode.sym.ast)
  visit validateVariables(node.vars, symNode.sym)
  visit directivesUsage(node.dirs, dlMUTATION, symNode)
  noCyclicSetup(visited, symNode)
  visit fragmentInOp(node.sels, visited, symNode)

proc visitSubscription(ctx: GraphqlRef, symNode: Node) =
  # name, vars, dirs, sels
  let node = Subscription(symNode.sym.ast)
  visit validateVariables(node.vars, symNode.sym)
  visit directivesUsage(node.dirs, dlSUBSCRIPTION, symNode)
  noCyclicSetup(visited, symNode)
  visit fragmentInOp(node.sels, visited, symNode)

proc visitFragment(ctx: GraphqlRef, symNode: Node) =
  # name, vars, typeCond, dirs, sels
  let node = Fragment(symNode.sym.ast)
  visit validateVariables(node.vars, symNode.sym)
  visit visitTypeCond(node.Node, 2)
  visit directivesUsage(node.dirs, dlFRAGMENT_DEFINITION, symNode)
  noCyclicSetup(visited, symNode)
  visit fragmentInOp(node.sels, visited, symNode)

proc getInnerType(node: Node): Node =
  case node.kind:
  of nkSym:
    return node
  of nkListType, nkNonNullType:
    return getInnerType(node[0])
  else:
    unreachable()

proc getPossibleTypes(ctx: GraphqlRef, node: Node): HashSet[Symbol] =
  case node.sym.kind
  of skObject:
    result.incl node.sym
  of skInterface:
    ctx.fillPossibleTypes(node)
    for n in node.sym.types:
      result.incl n.sym
  of skUnion:
    let members = Union(node.sym.ast).members
    for n in members:
      result.incl n.sym
  else:
    unreachable()

proc applicableType(ctx: GraphqlRef, name: Node, typ: Node, parentType: Node) =
  let ta = ctx.getPossibleTypes(typ)
  let tb = ctx.getPossibleTypes(parentType)
  if ta.intersection(tb).len == 0:
    ctx.error(ErrNotPartOf, name, parentType)

proc fieldArgs(ctx: GraphqlRef, scope, parentType, fieldName: Node, args: Args, targs: Arguments) =
  for arg in args:
    targ := findArg(parentType, fieldName, arg.name, targs)
    visit inputCoercion(arg.name, targ.typ, targ.defVal, arg.Node, 1, scope)

  for targ in targs:
    let typ = targ.typ
    let defVal = targ.defVal
    if not nullableType(typ) and defVal.kind == nkEmpty:
      let arg = findArg(targ.name, args)
      invalid Node(arg).isNil:
        ctx.error(ErrNoArg, fieldName, targ.name)
      # no need to check for null here
      # already handled by inputCoercion above

proc fieldRef(field: Field, typ: Node, parentType: Node): FieldRef =
  let respName = if field.alias.kind != nkEmpty: field.alias else: field.name
  var res = FieldRef(
    respName: respName,
    field: field,
    typ: typ,
    parentType: parentType
  )
  res

proc fieldSelection(ctx: GraphqlRef, scope, sels, parentType: Node, fieldSet: var FieldSet)

proc fieldSelection(ctx: GraphqlRef, scope, parentType: Node, fieldSet: var FieldSet, field: Field) =
  let name = field.name
  invalid parentType.sym.kind notin {skInterface, skObject}:
    ctx.error(ErrNotPartOf, name, parentType)
  target := findField(ObjectField, parentType.sym, name)
  visit fieldArgs(scope, parentType, name, field.args, target.args)
  let fieldType = getInnerType(target.typ)
  let fieldSels = field.sels
  invalid fieldType.sym.kind in {skInterface, skObject} and fieldSels.len == 0:
    let obj = Object(fieldType.sym.ast)
    ctx.error(ErrRequireSelection, name, obj.name)
  let ffn = fieldRef(field, target.typ, parentType)
  fieldSet.add ffn
  visit fieldSelection(scope, fieldSels, fieldType, ffn.fieldSet)

proc skipField(ctx: GraphqlRef, dirs: Dirs): bool =
  for dir in dirs:
    case toKeyword(dir.name.sym.name)
    of kwSkip:
      let args = dir.args
      for arg in args:
        if toKeyword(arg.name.name) == kwIf and arg.val.boolVal:
          return true
    of kwInclude:
      let args = dir.args
      for arg in args:
        if toKeyword(arg.name.name) == kwIf and not arg.val.boolVal:
          return true
    else:
      discard

proc fieldSelection(ctx: GraphqlRef, scope, sels, parentType: Node, fieldSet: var FieldSet) =
  for field in sels:
    case field.kind
    of nkFragmentSpread:
      # name, dirs
      let spread = FragmentSpread(field)
      if ctx.skipField(spread.dirs): continue
      let name = spread.name
      let frag = Fragment(name.sym.ast)
      visit directivesUsage(frag.dirs, dlFRAGMENT_DEFINITION, scope)
      visit applicableType(name, frag.typeCond, parentType)
      visit fieldSelection(scope, frag.sels, frag.typeCond, fieldSet)
    of nkInlineFragment:
      # typeCond, dirs, sels
      let frag = InlineFragment(field)
      if ctx.skipField(frag.dirs): continue
      let typ = frag.typeCond
      visit applicableType(typ, typ, parentType)
      visit fieldSelection(scope, frag.sels, typ, fieldSet)
    of nkField:
      # alias, name, args, dirs, sels
      let field = Field(field)
      if ctx.skipField(field.dirs): continue
      let name = field.name
      if toKeyword(name.name) in introsKeywords:
        visit fieldSelection(scope, ctx.rootIntros, fieldSet, field)
        continue
      visit fieldSelection(scope, parentType, fieldSet, field)
    else:
      unreachable()

proc sameResponseShape(fieldA, fieldB: FieldRef): bool =
  var typeA = fieldA.typ
  var typeB = fieldB.typ

  while true:
    if typeA.kind == nkNonNullType or typeB.kind == nkNonNullType:
      if nullableType(typeA) or nullableType(typeB):
        return false
      typeA = typeA[0]
      typeB = typeB[0]

    if typeA.kind == nkListType or typeB.kind == nkListType:
      if typeA.kind != nkListType or typeB.kind != nkListType:
        return false
      typeA = typeA[0]
      typeB = typeB[0]
      continue
    break

  if typeA.sym.kind in {skScalar, skEnum} or typeB.sym.kind in {skScalar, skEnum}:
    if typeA.sym.kind != typeB.sym.kind: return false
    return typeA.sym.name == typeB.sym.name

  assert(typeA.sym.kind in {skObject, skInterface, skUnion})
  assert(typeB.sym.kind in {skObject, skInterface, skUnion})
  var mergedSet = fieldA.fieldSet
  mergedSet.add fieldB.fieldSet
  for x, subFieldA in mergedSet:
    if subFieldA.merged:
      continue
    for y, subFieldB in mergedSet:
      if x == y: continue
      if subFieldB.merged:
        continue
      if subFieldA.respName.name != subFieldB.respName.name:
        continue
      if not sameResponseShape(subFieldB, subFieldA):
        return false
  return true

proc litEquals(a, b: Node): bool =
  if a.kind != b.kind:
    return false

  case a.kind
  of nkEmpty, nkNull:
    return true
  of nkBoolean:
    return a.boolVal == b.boolVal
  of nkInt:
    return a.intVal == b.intVal
  of nkFloat:
    return a.floatVal == b.floatVal
  of nkString:
    return a.stringVal == b.stringVal
  of nkEnum, nkVariable, nkName, nkNamedType:
    return a.name == b.name
  of nkSym:
    return a.sym.name == b.sym.name
  else:
    if a.len != b.len:
      return false
    for i in 0 ..< a.len:
      if not litEquals(a[i], b[i]):
        return false
    return true

proc identicalArguments(fieldA, fieldB: FieldRef): bool =
  let argsA = fieldA.field.args
  let argsB = fieldB.field.args

  if Node(argsA).len != Node(argsB).len:
    return false

  for arga in argsA:
    let argb = findArg(arga.name, argsB)
    if Node(argb).isNil:
      return false
    if not litEquals(arga.val, argb.val):
      return false
  return true

proc fieldInSetCanMerge(ctx: GraphqlRef, fieldSet: FieldSet) =
  for x, fieldA in fieldSet:
    if fieldA.merged: continue
    for y, fieldB in fieldSet:
      if x == y: continue
      if fieldB.merged: continue
      if fieldA.respName.name != fieldB.respName.name:
        continue

      invalid not sameResponseShape(fieldA, fieldB):
        ctx.error(ErrMergeConflict, fieldA.respName, "return type mismatch")
      if sameType(fieldA.parentType, fieldB.parentType) or
        (fieldA.parentType.sym.kind != skObject and fieldB.parentType.sym.kind != skObject):
        invalid fieldA.field.name.name != fieldB.field.name.name:
          ctx.error(ErrMergeConflict, fieldA.field.name, "alias lie about field name")
        invalid not identicalArguments(fieldA, fieldB):
          ctx.error(ErrMergeConflict, fieldA.field.name, "not identical sets of arguments")
        var mergedSet = fieldA.fieldSet
        mergedSet.add fieldB.fieldSet
        visit fieldInSetCanMerge(mergedSet)
        fieldB.merged = true
        fieldA.fieldSet = system.move(mergedSet)

proc validateVarUsage(ctx: GraphqlRef, symNode: Node) =
  for v in values(symNode.sym.vars):
    invalid sfUsed notin v.sym.flags:
      ctx.error(ErrNotUsed, v)

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
    # modification, they already filled by inputCoercion
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

proc fillArgs(fieldName: Name, parent: Symbol, args: Args): Node =
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
  res

proc fillArgs(field: FieldRef) =
  ## replace args node with ordered and filled args
  let fieldName = field.field.name
  let parentType = field.parentType.sym
  Node(field.field)[2] = fillArgs(fieldName.name, parentType, field.field.args)

proc skipOrInclude(field: FieldRef) =
  # recursively remove merged field in fieldset
  var fieldSet = newSeq[FieldRef]()
  for n in field.fieldSet:
    if n.merged:
      continue
    skipOrInclude(n)
    n.fillArgs()
    fieldSet.add n
  # replace the old fieldSet with reduced fieldSet
  field.fieldSet = system.move(fieldSet)

proc skipOrInclude(ctx: GraphqlRef, fieldSet: FieldSet, opType: Node): ExecRef =
  var exec = ExecRef(opType: opType)
  for n in fieldSet:
    if n.merged:
      continue
    skipOrInclude(n)
    n.fillArgs()
    exec.fieldSet.add n
  exec

proc fragmentFragment(ctx: GraphqlRef, symNode: Node) =
  let node = Fragment(symNode.sym.ast)
  # name, vars, typeCond, dirs, sels
  var fieldSet: FieldSet
  visit fieldSelection(symNode, node.sels, node.typeCond, fieldSet)
  visit fieldInSetCanMerge(fieldSet)
  invalid sfUsed notin symNode.sym.flags:
    ctx.error(ErrNotUsed, symNode)
  visit validateVarUsage(symNode)

proc queryQuery(ctx: GraphqlRef, symNode: Node): ExecRef =
  invalid ctx.rootQuery.isNil:
    ctx.error(ErrNoRoot, symNode, "Query or schema:query")

  let node = Query(symNode.sym.ast)
  var fieldSet: FieldSet
  visit fieldSelection(symNode, node.sels, ctx.rootQuery, fieldSet)
  visit fieldInSetCanMerge(fieldSet)
  visit validateVarUsage(symNode)
  ctx.skipOrInclude(fieldSet, ctx.rootQuery)

proc mutationMutation(ctx: GraphqlRef, symNode: Node): ExecRef =
  invalid ctx.rootMutation.isNil:
    ctx.error(ErrNoRoot, symNode, "Mutation or schema:mutation")

  let node = Mutation(symNode.sym.ast)
  var fieldSet: FieldSet
  visit fieldSelection(symNode, node.sels, ctx.rootMutation, fieldSet)
  visit fieldInSetCanMerge(fieldSet)
  visit validateVarUsage(symNode)
  ctx.skipOrInclude(fieldSet, ctx.rootMutation)

proc countRootFields(ctx: GraphqlRef, sels: Node, root = true): int =
  var count = 0
  for field in sels:
    case field.kind
    of nkFragmentSpread:
      # name, dirs
      let spread = FragmentSpread(field)
      let name = spread.name
      let frag = Fragment(name.sym.ast)
      fieldsCount := countRootFields(frag.sels, false)
      if root: inc(count, fieldsCount)
    of nkInlineFragment:
      # typeCond, dirs, sels
      let frag = InlineFragment(field)
      fieldsCount := countRootFields(frag.sels, false)
      if root: inc(count, fieldsCount)
    of nkField:
      # alias, name, args, dirs, sels
      let dirs = Field(field).dirs
      for dir in dirs:
        let name = dir.name
        invalid toKeyword(name.sym.name) in {kwSkip, kwInclude}:
          ctx.error(ErrDirNotAllowed, name)
      let name = Field(field).name
      if toKeyword(name.name) notin introsKeywords:
        inc count
    else:
      unreachable()
  return count

proc subscriptionSubscription(ctx: GraphqlRef, symNode: Node): ExecRef =
  invalid ctx.rootSubs.isNil:
    ctx.error(ErrNoRoot, symNode, "Subscription or schema:suscription")

  let node = Subscription(symNode.sym.ast)
  var fieldSet: FieldSet
  visit fieldSelection(symNode, node.sels, ctx.rootSubs, fieldSet)
  visit fieldInSetCanMerge(fieldSet)
  rootFieldsCount := countRootFields(node.sels)
  invalid rootFieldsCount != 1:
    ctx.error(ErrOnlyOne, node.Node, "root subscription field")
  visit validateVarUsage(symNode)
  ctx.skipOrInclude(fieldSet, ctx.rootSubs)

proc extendDirs(sym: Symbol, idx: int, tDirs: Node, dirs: Dirs) =
  if tDirs.kind == nkEmpty:
    sym.ast[idx] = Node(dirs)
  else:
    for dir in dirs:
      tDirs <- dir.Node

proc extendSchema(ctx: GraphqlRef, sym: Symbol, node: Node) =
  # desc, name, dirs, members
  let tSchema = Schema(sym.ast)
  let tDirs   = Node(tSchema.dirs)
  let schema  = Schema(node)
  let dirs    = schema.dirs
  extendDirs(sym, 2, tDirs, dirs)
  let members = schema.members
  let tMembers = tSchema.members
  for n in members:
    tMembers <- n

proc extendScalar(ctx: GraphqlRef, sym: Symbol, node: Node) =
  # desc, name, dirs
  let tScalar = Scalar(sym.ast)
  let tDirs   = Node(tScalar.dirs)
  let scalar  = Scalar(node)
  let dirs    = scalar.dirs
  extendDirs(sym, 2, tDirs, dirs)

proc extendImplements(sym: Symbol, idx: int, tImpl, impl: Node) =
  if tImpl.kind == nkEmpty:
    sym.ast[idx] = impl
  else:
    for imp in impl:
      tImpl <- imp

proc extendObjectDef(ctx: GraphqlRef, sym: Symbol, node: Node) =
  # desc, name, impls, dirs, fields
  let tObj  = Object(sym.ast)
  let tDirs = Node(tObj.dirs)
  let obj   = Object(node)
  let dirs  = obj.dirs
  let tImpl = tObj.implements
  let impl  = obj.implements
  extendImplements(sym, 2, tImpl, impl)
  extendDirs(sym, 3, tDirs, dirs)
  let fields = Node(obj.fields)
  let tFields = Node(tObj.fields)
  for n in fields:
    tFields <- n

proc extendInterfaceDef(ctx: GraphqlRef, sym: Symbol, node: Node) =
  # desc, name, impls, dirs, fields
  let tIface  = Interface(sym.ast)
  let tDirs   = Node(tIface.dirs)
  let iface   = Interface(node)
  let dirs    = iface.dirs
  let tImpl   = tIface.implements
  let impl    = iface.implements
  extendImplements(sym, 2, tImpl, impl)
  extendDirs(sym, 3, tDirs, dirs)
  let fields = Node(iface.fields)
  let tFields = Node(tIface.fields)
  for n in fields:
    tFields <- n

proc extendUnionDef(ctx: GraphqlRef, sym: Symbol, node: Node) =
  # desc, name, dirs, members
  let tUni  = Union(sym.ast)
  let tDirs = Node(tUni.dirs)
  let uni   = Union(node)
  let dirs  = uni.dirs
  extendDirs(sym, 2, tDirs, dirs)
  let members = uni.members
  let tMembers = tUni.members
  for n in members:
    tMembers <- n

proc extendEnumDef(ctx: GraphqlRef, sym: Symbol, node: Node) =
  # desc, name, dirs, values
  let tEnum   = Enum(sym.ast)
  let tDirs   = Node(tEnum.dirs)
  let enumDef = Enum(node)
  let dirs    = enumDef.dirs
  extendDirs(sym, 2, tDirs, dirs)
  let values  = Node(enumDef.values)
  let tValues = Node(tEnum.values)
  for n in values:
    tValues <- n

proc extendInputObjectDef(ctx: GraphqlRef, sym: Symbol, node: Node) =
  # desc, name, dirs, fields
  let tInput = InputObject(sym.ast)
  let tDirs  = Node(tInput.dirs)
  let input  = InputObject(node)
  let dirs   = input.dirs
  extendDirs(sym, 2, tDirs, dirs)
  let fields = Node(input.fields)
  let tFields = Node(tInput.fields)
  for n in fields:
    tFields <- n

proc visitExtension(ctx: GraphqlRef, root: Node, idx: int) =
  # skip the 'extend'
  let node = root[idx][0]
  doAssert(node.kind in TypeDefNodes)

  let name = node[1]
  sym := findType(name, toSymKind(node.kind))

  case node.kind
  of nkSchemaDef:     visit extendSchema(sym.sym, node)
  of nkScalarDef:     visit extendScalar(sym.sym, node)
  of nkObjectDef:     visit extendObjectDef(sym.sym, node)
  of nkInterfaceDef:  visit extendInterfaceDef(sym.sym, node)
  of nkUnionDef:      visit extendUnionDef(sym.sym, node)
  of nkEnumDef:       visit extendEnumDef(sym.sym, node)
  of nkInputObjectDef:visit extendInputObjectDef(sym.sym, node)
  else:
    unreachable()

proc secondPass(ctx: GraphqlRef, root: Node) =
  var opCount = 0 # validate anon op

  for n in root:
    if n.kind != nkSym:
      # skip extension
      continue
    let sym = n.sym
    case sym.kind
    of skSchema:      visit visitSchema(Schema(sym.ast))
    of skScalar:      visit visitScalar(Scalar(sym.ast))
    of skObject:      visit visitObject(Object(sym.ast), n)
    of skInterface:   visit visitInterface(Interface(sym.ast), sym)
    of skUnion:       visit visitUnion(Union(sym.ast))
    of skEnum:        visit visitEnum(Enum(sym.ast))
    of skInputObject: visit visitInputObject(InputObject(sym.ast))
    of skDirective:   visit visitDirective(Directive(sym.ast))
    of skQuery:
      inc opCount
      let vars = Query(sym.ast).vars
      if Node(vars).kind != nkEmpty:
        sym.astCopy = copyTree(sym.ast)
        sym.flags.incl sfHasVariables
      visit visitQuery(n)
    of skMutation:
      inc opCount
      let vars = Mutation(sym.ast).vars
      if Node(vars).kind != nkEmpty:
        sym.astCopy = copyTree(sym.ast)
        sym.flags.incl sfHasVariables
      visit visitMutation(n)
    of skSubscription:
      inc opCount
      let vars = Subscription(sym.ast).vars
      if Node(vars).kind != nkEmpty:
        sym.astCopy = copyTree(sym.ast)
        sym.flags.incl sfHasVariables
      visit visitSubscription(n)
    of skFragment:    visit visitFragment(n)
    else:
      discard

  # third pass
  for n in root:
    if n.kind != nkSym:
      # skip extension
      continue
    case n.sym.kind
    of skFragment:    visit fragmentFragment(n)
    of skInputObject: visit inputInput(n)
    of skDirective:   visit directiveDirective(n)
    of skInterface:   visit interfaceInterface(n)
    of skObject:      visit objectObject(n)
    of skQuery:
      if sfHasVariables notin n.sym.flags:
        n.sym.exec ::= queryQuery(n)
    of skMutation:
      if sfHasVariables notin n.sym.flags:
        n.sym.exec ::= mutationMutation(n)
    of skSubscription:
      if sfHasVariables notin n.sym.flags:
        n.sym.exec ::= subscriptionSubscription(n)
    else:
      discard

  # validate anon op
  let anonSym = findOp(ctx.names.anonName)
  invalid anonSym.isNil.not and opCount > 1:
    ctx.error(ErrOnlyOne, anonSym.sym.ast[0], "anonymous operation")

proc validate*(ctx: GraphqlRef, root: Node) =
  # reset errors before new validation
  ctx.errKind = ErrNone
  ctx.path = nil
  ctx.errors.setLen(0)

  assert(root.kind == nkMembers, "expect nkMembers")
  execInstrument(iValidationBegin, ctx.emptyNode, root)
  for i, n in root:
    case n.kind
    of nkQuery:          visit visitOp(root, i, skQuery)
    of nkMutation:       visit visitOp(root, i, skMutation)
    of nkSubscription:   visit visitOp(root, i, skSubscription)
    of nkFragment:       visit visitOp(root, i, skFragment)
    of nkSchemaDef:      visit visitType(root, i, skSchema)
    of nkScalarDef:      visit visitType(root, i, skScalar)
    of nkObjectDef:      visit visitType(root, i, skObject)
    of nkInterfaceDef:   visit visitType(root, i, skInterface)
    of nkUnionDef:       visit visitType(root, i, skUnion)
    of nkEnumDef:        visit visitType(root, i, skEnum)
    of nkInputObjectDef: visit visitType(root, i, skInputObject)
    of nkDirectiveDef:
      visit visitType(root, i, skDirective)
      ctx.directiveFlags(root[i])
    of nkExtend:         visit visitExtension(root, i)
    else:
      unreachable()

  ctx.secondPass(root)

proc pickOpName(ctx: GraphqlRef, opName: string): Name =
  if opName.len != 0:
    return ctx.names.insert(opName)

  result = ctx.names.anonName
  var sym: Symbol
  var i = 0
  for name, opSym in ctx.opTable:
    if opSym.sym.kind != skFragment:
      result = name
      sym = opSym.sym
      inc i

  invalid i > 1:
    ctx.fatal(ErrNoRoot, sym.ast)

proc validateOpWithVars(ctx: GraphqlRef, n: Node): ExecRef =
  case n.sym.kind
  of skQuery:
    visit visitQuery(n)
    result ::= queryQuery(n)
  of skMutation:
    visit visitMutation(n)
    result ::= mutationMutation(n)
  of skSubscription:
    visit visitSubscription(n)
    result ::= subscriptionSubscription(n)
  else:
    unreachable()

proc getOperation*(ctx: GraphqlRef, opName: string): Node =
  name := pickOpName(opName)
  let op = ctx.opTable.getOrDefault(name)
  invalid op.isNil:
    ctx.fatal(ErrOperationNotFound, ctx.emptyNode, name)

  if sfHasVariables in op.sym.flags:
    op.sym.ast = copyTree(op.sym.astCopy)
    op.sym.exec ::= validateOpWithVars(op)

  execInstrument(iExecBegin, ctx.emptyNode, op)
  op
