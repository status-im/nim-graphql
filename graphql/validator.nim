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
  ./context

const
  introsKeywords = {introsSchema, introsType, introsTypeName}

proc error(ctx: ContextRef, msg: string) =
  ctx.errKind     = ErrInternal
  ctx.err.level   = elFatal
  ctx.err.message = msg

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

proc assignRootOp(ctx: ContextRef, name: Name, sym: Node) =
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

proc findType(ctx: ContextRef, name: Node, types: set[SymKind]): Symbol =
  let sym = findType(name.name)
  invalid sym.isNil:
    ctx.error(ErrTypeUndefined, name)
  invalid sym.kind notin types:
    ctx.error(ErrTypeMismatch, name, sym.kind, $$types)
  sym

proc findType(ctx: ContextRef, name: Node, typ: SymKind): Symbol =
  let sym = findType(name.name)
  invalid sym.isNil:
    ctx.error(ErrTypeUndefined, name)
  invalid sym.kind != typ:
    ctx.error(ErrTypeMismatch, name, sym.kind, typ)
  sym

proc findOp(ctx: ContextRef, name: Node, typ: SymKind): Symbol =
  let sym = findOp(name.name)
  invalid sym.isNil:
    ctx.error(ErrTypeUndefined, name)
  invalid sym.kind != typ:
    ctx.error(ErrTypeMismatch, name, sym.kind, typ)
  sym

proc isWhatType(ctx: ContextRef, parent: Node, idx: int, whatTypes: set[SymKind]) =
  let node = parent[idx]
  case node.kind
  of nkNonNullType:
    visit isWhatType(node, 0, whatTypes)
  of nkListType:
    visit isWhatType(node, 0, whatTypes)
  of nkNamedType:
    sym := findType(node, whatTypes)
    parent[idx] = newSymNode(sym, node.pos)
  else:
    unreachable()

template isOutputType(ctx: ContextRef, node: Node, idx: int) =
  ctx.isWhatType(node, idx, OutputTypes)

template isInputType(ctx: ContextRef, node: Node, idx: int) =
  ctx.isWhatType(node, idx, InputTypes)

proc nullableType(node: Node): bool =
  case node.kind
  of nkNonNullType:
    case node[0].kind
    of nkListType:
      return true
    of nkSym:
      return false
    else:
      unreachable()
  of nkListType, nkSym, nkNamedType:
    return true
  else:
    unreachable()

proc getScalar(ctx: ContextRef, sym: Symbol): ScalarRef =
  if sym.scalar.isNil:
    let scalar = findScalar(sym.name)
    sym.scalar = scalar
    scalar
  else:
    sym.scalar

proc findField(ctx: ContextRef, T: type, sym: Symbol, name: Node): T =
  # for object, interface, and input object only!
  let field = sym.fields.getOrDefault(name.name)
  invalid field.isNil:
    ctx.error(ErrNotPartOf, name, sym.name)
  T(field)

proc findField(name: Name, inputVal: Node): Node =
  for n in inputVal:
    if n[0].name == name:
      return n

proc findArg(ctx: ContextRef, parentType, fieldName, argName: Node, targs: Arguments): Argument =
  for arg in targs:
    if arg.name.name == argName.name:
      return arg
  ctx.error(ErrFieldArgUndefined, argName, fieldName, parentType)

proc findArg(ctx: ContextRef, dirName, argName: Node, targs: Arguments): Argument =
  for arg in targs:
    if arg.name.name == argName.name:
      return arg
  ctx.error(ErrDirArgUndefined, argName, dirName)

proc findArg(name: Node, args: Args): Arg =
  for arg in args:
    if arg.name.name == name.name:
      return arg
  return Arg(nil)

proc findArg(name: Node, args: Arguments): Node =
  for arg in args:
    if arg.name.name == name.name:
      return arg.typ
  return nil

proc coerceEnum(ctx: ContextRef, sym: Symbol, inVal: Node) =
  invalid inVal.kind != nkEnum:
    ctx.error(ErrTypeMismatch, inVal, inVal.kind, sym.name)

  if sym.fields.len == 0:
    for x in sym.ast[3]:
      sym.fields[x[1].name] = x

  # desc, enumval, dirs
  invalid sym.fields.getOrDefault(inVal.name).isNil:
    ctx.error(ErrNotPartOf, inVal, sym.name)

proc inputCoercion(ctx: ContextRef, nameNode, locType, locDefVal, parent: Node; idx: int, scope = Node(nil))

proc findVar(ctx: ContextRef, val: Node, scope: Node): Variable =
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

proc variableUsageAllowed(ctx: ContextRef, varDef: Variable, varName, locType, locDefVal: Node) =
  let varType = varDef.typ
  if locType.kind == nkNonNullType and varType.kind != nkNonNullType:
    let defVal = varDef.defVal
    let hasNonNullVariableDefaultValue = defVal.kind notin {nkEmpty, nkNull}
    let hasLocationDefaultValue = locDefVal.kind != nkEmpty
    invalid not hasNonNullVariableDefaultValue and not hasLocationDefaultValue:
      ctx.error(ErrNotNullable, varName, "variable")
    let nullableLocType = locType[0]
    if not areTypesCompatible(varType, nullableLocType):
      ctx.error(ErrTypeMismatch, varName, $$varType, $$nullableLocType)
    return
  if not areTypesCompatible(varType, locType):
    ctx.error(ErrTypeMismatch, varName, $$varType, $$locType)

proc coerceInputObject(ctx: ContextRef, nameNode: Node, sym: Symbol, inVal: Node, scope: Node) =
  invalid inVal.kind != nkInput:
    ctx.error(ErrTypeMismatch, inVal, inVal.kind, nkInput)

  # desc, name, dirs, fields
  let inp = InputObject(sym.ast)
  let fields = inp.fields
  if sym.fields.len == 0:
    for field in fields:
      # desc, name, type, defVal, dirs
      sym.fields[field.name.name] = field.Node

  var names = initHashSet[Name]()
  for field in inVal:
    # name, value
    let name = field[0]
    let val = field[1]
    noNameDup(name, names)
    inputField := findField(InputField, sym, name)
    let locType = inputField.typ
    let dv = inputField.defVal
    if val.kind == nkVariable:
      varDef := findVar(val, scope)
      visit variableUsageAllowed(varDef, val, locType, dv)
      let rtVal = ctx.varTable.getOrDefault(val.name)
      if rtVal.isNil:
        let defVal = varDef.defVal
        if defVal.kind == nkEmpty:
          field[1] = dv
        else:
          field[1] = defVal
      else:
        field[1] = rtVal
    visit inputCoercion(name, locType, dv, field, 1, scope)

  for field in fields:
    let name = field.name
    let valField = findField(name.name, inVal)
    if not valField.isNil: continue
    let dv = field.defVal
    invalid not nullableType(field.typ) and dv.kind == nkEmpty:
      ctx.error(ErrFieldNotinArg, nameNode, name)
    if dv.kind != nkEmpty:
      inVal.sons.add newTree(nkPair, name, dv)

proc coerceVariable(ctx: ContextRef, nameNode, locType, locDefVal, parent: Node; idx: int, scope: Node) =
  let varName = parent[idx]
  varDef := findVar(varName, scope)
  visit variableUsageAllowed(varDef, varName, locType, locDefVal)
  let defVal = varDef.defVal
  let rtVal = ctx.varTable.getOrDefault(varName.name)
  if rtVal.isNil:
    if defVal.kind != nkEmpty:
      parent[idx] = defVal
    else:
      invalid not nullableType(locType):
        ctx.error(ErrValueError, nameNode, nkEmpty)
      parent[idx] = defVal
  else:
    parent[idx] = rtVal

proc inputCoercion(ctx: ContextRef, nameNode, locType, locDefVal, parent: Node; idx: int, scope = Node(nil)) =
  var inVal = parent[idx]
  case inVal.kind
  of nkEmpty:
    return
  of nkVariable:
    doAssert(not scope.isNil)
    if scope.sym.kind == skFragment and
      inVal.name notin scope.sym.vars:
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
    visit inputCoercion(nameNode, locType[0], locDefVal, parent, idx, scope)
  of nkListType:
    case inVal.kind:
    of nkNull:
      return
    of nkList:
      for i in 0..<inVal.len:
        invalid locType[0].kind == nkListType and inVal[i].kind != nkList:
          ctx.error(ErrValueError, nameNode, nkList)
        visit inputCoercion(nameNode, locType[0], locDefVal, inVal, i, scope):
    else:
      var newList = newTree(nkList, inVal)
      parent[idx] = newList
      visit inputCoercion(nameNode, locType[0], locDefVal, newList, 0, scope)
  of nkSym:
    let sym = locType.sym
    if inVal.kind == nkNull:
      return
    case sym.kind
    of skScalar:
      let scalar = ctx.getScalar(sym)
      invalid scalar.isNil:
        ctx.error(ErrNoImpl, locType, "scalar")
      let res = scalar.parseLit(inVal)
      invalid res.isErr:
        ctx.error(ErrScalarError, inVal, res.error)
      parent[idx] = res.get()
    of skEnum:
      visit coerceEnum(sym, inVal):
    of skInputObject:
      visit coerceInputObject(nameNode, sym, inVal, scope):
    else:
      unreachable()
  else:
    unreachable()

proc visitOp(ctx: ContextRef, parent: Node, idx: int, sk: SymKind) =
  # name, vars, dirs, sels, [typeCond]
  let node = parent[idx]
  let name = node[0]
  doAssert(name.kind == nkName)

  invalid findOp(name.name) != nil:
    ctx.error(ErrDuplicateName, name)

  let sym = newSymNode(sk, name.name, node, name.pos)
  ctx.opTable[name.name] = sym.sym
  parent[idx] = sym

proc visitType(ctx: ContextRef, parent: Node, idx: int, sk: SymKind) =
  # desc, name, ...
  let node = parent[idx]
  let name = node[1]
  doAssert(name.kind == nkName)

  invalid findType(name.name) != nil:
    ctx.error(ErrDuplicateName, name)

  let sym = newSymNode(sk, name.name, node, name.pos)
  ctx.typeTable[name.name] = sym.sym
  parent[idx] = sym

proc dirArgs(ctx: ContextRef, scope, dirName: Node, args: Args, targs: Arguments) =
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

proc directivesUsage(ctx: ContextRef, dirs: Dirs, dirLoc: DirLoc, scope = Node(nil)) =
  var names = initHashSet[Name]()
  for dir in dirs:
    let name = dir.name
    case name.kind
    of nkName:
      sym := findType(name, skDirective)
      invalid name.name in names and sfRepeatable notin sym.flags:
        ctx.error(ErrDuplicateName, name)
      names.incl name.name
      invalid dirLoc notin sym.dirLocs:
        ctx.error(ErrDirectiveMisLoc, name, dirLoc)
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

proc validateArgs(ctx: ContextRef, args: Arguments) =
  # desc, argName, argType, defVal, dirs
  var names = initHashSet[Name]()
  for arg in args:
    let name = arg.name
    noNameDup(name, names)
    visit isInputType(arg.Node, 2)
    visit inputCoercion(name, arg.typ, arg.defVal, arg.Node, 3)
    visit directivesUsage(arg.dirs, dlARGUMENT_DEFINITION)

proc visitSchema(ctx: ContextRef, node: Schema) =
  # desc, name, dirs, members
  let members = node.members
  var names = initHashSet[Name]()
  for n in members:
    doAssert(n.kind == nkPair)
    let opKind = n[0]
    let opName = n[1]
    noNameDup(opKind, names)
    sym := findType(opName, skObject)
    let name = sym.ast[1]
    let symNode = newSymNode(sym, name.pos)
    ctx.assignRootOp(opKind.name, symNode)

  visit directivesUsage(node.dirs, dlSCHEMA)

proc visitScalar(ctx: ContextRef, node: Scalar) =
  # desc, name, dirs
  visit directivesUsage(node.dirs, dlSCALAR)

proc visitImplements(ctx: ContextRef, imp: Node) =
  var names = initHashSet[Name]()
  # check object implements valid interface
  for i, name in imp:
    doAssert(name.kind == nkNamedType)
    noNameDup(name, names)
    sym := findType(name, skInterface)
    imp[i] = newSymNode(sym, name.pos)

proc visitFields(ctx: ContextRef, fields: ObjectFields, sym: Symbol) =
  var names = initHashSet[Name]()
  for field in fields:
    # desc, name, args, type, dirs
    let name = field.name
    sym.fields[name.name] = field.Node
    noNameDup(name, names)
    visit validateArgs(field.args)
    visit isOutputType(field.Node, 3)
    visit directivesUsage(field.dirs, dlFIELD_DEFINITION)

proc visitObject(ctx: ContextRef, obj: Object, symNode: Node) =
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

proc isValidImplementation(ctx: ContextRef, impls: Node, symNode: Node) =
  for n in impls:
    let iface = Interface(n.sym.ast)
    # desc, name, ifaces, dirs, fields
    let thatFields = iface.fields
    let thatName = iface.name
    for thatField in thatFields:
      # desc, name, args, type, dirs
      let thatFieldName = thatField.name
      thisField := findField(ObjectField, symNode.sym, thatFieldName)
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

proc objectObject(ctx: ContextRef, symNode: Node) =
  # desc, name, ifaces, dirs, fields
  let node = Object(symNode.sym.ast)
  visit isValidImplementation(node.implements, symNode)

proc cyclicInterface(ctx: ContextRef, impls: Node, visited: var HashSet[Name]) =
  for n in impls:
    let imp = Interface(n.sym.ast)
    let name = imp.name
    noCyclic(name, visited)
    visit cyclicInterface(imp.implements, visited)

proc interfaceInterface(ctx: ContextRef, symNode: Node) =
  # desc, name, ifaces, dirs, fields
  let node = Interface(symNode.sym.ast)
  noCyclicSetup(visited, symNode)
  visit cyclicInterface(node.implements, visited)
  visit isValidImplementation(node.implements, symNode)

proc visitInterface(ctx: ContextRef, node: Interface, sym: Symbol) =
  # desc, name, ifaces, dirs, fields
  visit visitImplements(node.implements)
  visit directivesUsage(node.dirs, dlINTERFACE)
  visit visitFields(node.fields, sym)

proc visitUnion(ctx: ContextRef, node: Union) =
  # desc, name, dirs, members

  # only object can be union member
  var names = initHashSet[Name]()
  let members = node.members
  for i, name in members:
    noNameDup(name, names)
    sym := findType(name, skObject)
    members[i] = newSymNode(sym, name.pos)

  # validate directives
  visit directivesUsage(node.dirs, dlUNION)

proc visitEnum(ctx: ContextRef, node: Enum) =
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

proc inputInput(ctx: ContextRef, node: Node, visited: var HashSet[Name], nullableCount: int) =
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

proc inputInput(ctx: ContextRef, symNode: Node) =
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

proc visitInputObject(ctx: ContextRef, inp: InputObject) =
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

proc directiveFlags(ctx: ContextRef, symNode: Node) =
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

proc cyclicDirective(ctx: ContextRef, node: Node, visited: var HashSet[Name]) =
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

proc directiveDirective(ctx: ContextRef, symNode: Node) =
  let dir = Directive(symNode.sym.ast)
  let args = dir.args
  for arg in args:
    # desc, argName, argType, defVal, dirs
    noCyclicSetup(va, symNode)
    visit cyclicDirective(arg.dirs.Node, va)
    noCyclicSetup(vb, symNode)
    visit cyclicDirective(arg.typ, vb)

proc visitDirective(ctx: ContextRef, node: Directive) =
  visit validateArgs(node.args)

proc visitTypeCond(ctx: ContextRef, parent: Node, idx: int) =
  let node = parent[idx]
  case node.kind
  of nkNamedType:
    sym := findType(node, TypeConds)
    parent[idx] = newSymNode(sym, node.pos)
  of nkSym:
    discard
  else:
    unreachable()

proc fragmentInOp(ctx: ContextRef, sels: Node, visited: var HashSet[Name], scope: Node)

proc validateSpreadUsage(ctx: ContextRef, parent: Node, idx: int, visited: var HashSet[Name], scope: Node) =
  let name = parent[idx]
  case name.kind
  of nkName:
    noCyclic(name, visited)
    sym := findOp(name, skFragment)
    sym.flags.incl sfUsed
    parent[idx] = newSymNode(sym, name.pos)
    let frag = Fragment(sym.ast)
    visit fragmentInOp(frag.sels, visited, scope)
  of nkSym:
    let frag = Fragment(name.sym.ast)
    noCyclic(name, visited)
    visit fragmentInOp(frag.sels, visited, scope)
  else:
    unreachable()

proc fragmentInOp(ctx: ContextRef, sels: Node, visited: var HashSet[Name], scope: Node) =
  for field in sels:
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

proc validateVariables(ctx: ContextRef, vars: Variables, sym: Symbol) =
  var names = initHashSet[Name]()
  for varDef in vars:
    # name, type, defVal, dirs
    let name = varDef.name
    noNameDup(name, names)
    visit isInputType(varDef.Node, 1)
    visit inputCoercion(name, varDef.typ, varDef.defVal, varDef.Node, 2)
    visit directivesUsage(varDef.dirs, dlVARIABLE_DEFINITION)
    sym.vars[name.name] = newSymNode(skVariable, name.name, varDef.Node, name.pos)

proc visitQuery(ctx: ContextRef, symNode: Node) =
  # name, vars, dirs, sels
  let node = Query(symNode.sym.ast)
  visit validateVariables(node.vars, symNode.sym)
  visit directivesUsage(node.dirs, dlQUERY, symNode)
  noCyclicSetup(visited, symNode)
  visit fragmentInOp(node.sels, visited, symNode)

proc visitMutation(ctx: ContextRef, symNode: Node) =
  # name, vars, dirs, sels
  let node = Mutation(symNode.sym.ast)
  visit validateVariables(node.vars, symNode.sym)
  visit directivesUsage(node.dirs, dlMUTATION, symNode)
  noCyclicSetup(visited, symNode)
  visit fragmentInOp(node.sels, visited, symNode)

proc visitSubscription(ctx: ContextRef, symNode: Node) =
  # name, vars, dirs, sels
  let node = Subscription(symNode.sym.ast)
  visit validateVariables(node.vars, symNode.sym)
  visit directivesUsage(node.dirs, dlSUBSCRIPTION, symNode)
  noCyclicSetup(visited, symNode)
  visit fragmentInOp(node.sels, visited, symNode)

proc visitFragment(ctx: ContextRef, symNode: Node) =
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

proc getPossibleTypes(ctx: ContextRef, node: Node): HashSet[Symbol] =
  case node.sym.kind
  of skObject:
    result.incl node.sym
  of skInterface:
    for sym in values(ctx.typeTable):
      if sym.kind notin {skObject, skInterface}:
        continue
      let obj = Object(sym.ast)
      let impls = obj.implements
      for n in impls:
        if n.sym.name == node.sym.name:
          result.incl sym
  of skUnion:
    let uni = Union(node.sym.ast)
    let members = uni.members
    for n in members:
      result.incl n.sym
  else:
    unreachable()

proc applicableType(ctx: ContextRef, name: Node, typ: Node, parentType: Node) =
  let ta = ctx.getPossibleTypes(typ)
  let tb = ctx.getPossibleTypes(parentType)
  if ta.intersection(tb).len == 0:
    ctx.error(ErrNotPartOf, name, parentType)

proc fieldArgs(ctx: ContextRef, scope, parentType, fieldName: Node, args: Args, targs: Arguments) =
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

proc fieldForName(field: Field, typ: Node, parentType: Node): FieldForName =
  let respName = if field.alias.kind != nkEmpty: field.alias else: field.name
  var res = FieldForName(
    respName: respName,
    field: field,
    typ: typ,
    parentType: parentType
  )
  res

proc fieldSelection(ctx: ContextRef, scope, sels, parentType: Node, fieldSet: var FieldSet)

proc fieldSelection(ctx: ContextRef, scope, parentType: Node, fieldSet: var FieldSet, field: Field) =
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
  let ffn = fieldForName(field, target.typ, parentType)
  fieldSet.add ffn
  visit fieldSelection(scope, fieldSels, fieldType, ffn.fieldSet)

proc skipField(ctx: ContextRef, dirs: Dirs): bool =
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

proc fieldSelection(ctx: ContextRef, scope, sels, parentType: Node, fieldSet: var FieldSet) =
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
        return
      visit fieldSelection(scope, parentType, fieldSet, field)
    else:
      unreachable()

proc sameResponseShape(fieldA, fieldB: FieldForName): bool =
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
    if fieldA.merged: continue
    for y, subFieldB in mergedSet:
      if x == y: continue
      if fieldB.merged: continue
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

proc identicalArguments(fieldA, fieldB: FieldForName): bool =
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

proc fieldInSetCanMerge(ctx: ContextRef, fieldSet: FieldSet) =
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
        return

proc validateVarUsage(ctx: ContextRef, symNode: Node) =
  for v in values(symNode.sym.vars):
    invalid sfUsed notin v.sym.flags:
      ctx.error(ErrNotUsed, v)

proc skipOrInclude(field: FieldForName) =
  # recursively remove merged field in fieldset
  var s = newSeq[FieldForName]()
  for n in field.fieldSet:
    if n.merged:
      continue
    skipOrInclude(n)
    s.add n
  swap(field.fieldSet, s)

proc skipOrInclude(ctx: ContextRef, fieldSet: FieldSet, opSym, opType: Node) =
  var exec = ExecRef(opSym: opSym, opType: opType)
  for n in fieldSet:
    if n.merged:
      continue
    skipOrInclude(n)
    exec.fieldSet.add n
  ctx.execTable[opSym.sym.name] = exec

proc fragmentFragment(ctx: ContextRef, symNode: Node) =
  let node = Fragment(symNode.sym.ast)
  # name, vars, typeCond, dirs, sels
  var fieldSet: FieldSet
  visit fieldSelection(symNode, node.sels, node.typeCond, fieldSet)
  visit fieldInSetCanMerge(fieldSet)
  invalid sfUsed notin symNode.sym.flags:
    ctx.error(ErrNotUsed, symNode)
  visit validateVarUsage(symNode)

proc queryQuery(ctx: ContextRef, symNode: Node) =
  invalid ctx.rootQuery.isNil:
    ctx.error(ErrNoRoot, symNode, "Query or schema:query")

  let node = Query(symNode.sym.ast)
  var fieldSet: FieldSet
  visit fieldSelection(symNode, node.sels, ctx.rootQuery, fieldSet)
  visit fieldInSetCanMerge(fieldSet)
  visit validateVarUsage(symNode)
  ctx.skipOrInclude(fieldSet, symNode, ctx.rootQuery)

proc mutationMutation(ctx: ContextRef, symNode: Node) =
  invalid ctx.rootMutation.isNil:
    ctx.error(ErrNoRoot, symNode, "Mutation or schema:mutation")

  let node = Mutation(symNode.sym.ast)
  var fieldSet: FieldSet
  visit fieldSelection(symNode, node.sels, ctx.rootMutation, fieldSet)
  visit fieldInSetCanMerge(fieldSet)
  visit validateVarUsage(symNode)
  ctx.skipOrInclude(fieldSet, symNode, ctx.rootMutation)

proc countRootFields(sels: Node, root = true): int =
  var count = 0
  for field in sels:
    case field.kind
    of nkFragmentSpread:
      # name, dirs
      let spread = FragmentSpread(field)
      let name = spread.name
      let frag = Fragment(name.sym.ast)
      if root: inc(count, countRootFields(frag.sels, false))
    of nkInlineFragment:
      # typeCond, dirs, sels
      let frag = InlineFragment(field)
      if root: inc(count, countRootFields(frag.sels, false))
    of nkField:
      # alias, name, args, dirs, sels
      inc count
    else:
      unreachable()
  return count

proc subscriptionSubscription(ctx: ContextRef, symNode: Node) =
  invalid ctx.rootSubs.isNil:
    ctx.error(ErrNoRoot, symNode, "Subscription or schema:suscription")

  let node = Subscription(symNode.sym.ast)
  var fieldSet: FieldSet
  visit fieldSelection(symNode, node.sels, ctx.rootSubs, fieldSet)
  visit fieldInSetCanMerge(fieldSet)
  invalid countRootFields(node.sels) > 1:
    ctx.error(ErrOnlyOne, node.Node, "root selection")
  visit validateVarUsage(symNode)
  ctx.skipOrInclude(fieldSet, symNode, ctx.rootSubs)

proc extendDirs(sym: Symbol, idx: int, tDirs: Node, dirs: Dirs) =
  if tDirs.kind == nkEmpty:
    sym.ast[idx] = Node(dirs)
  else:
    for dir in dirs:
      tDirs.sons.add dir.Node

proc extendSchema(ctx: ContextRef, sym: Symbol, node: Node) =
  # desc, name, dirs, members
  let tSchema = Schema(sym.ast)
  let tDirs   = Node(tSchema.dirs)
  let schema  = Schema(node)
  let dirs    = schema.dirs
  extendDirs(sym, 2, tDirs, dirs)
  let members = schema.members
  let tMembers = tSchema.members
  for n in members:
    tMembers.sons.add n

proc extendScalar(ctx: ContextRef, sym: Symbol, node: Node) =
  # desc, name, dirs
  let tScalar = Scalar(sym.ast)
  let tDirs   = Node(tScalar.dirs)
  let scalar  = Scalar(node)
  let dirs    = scalar.dirs
  extendDirs(sym, 2, tDirs, dirs)

proc extendImplements(sym: Symbol, idx: int, tImpl, impl: Node) =
  if tImpl.kind == nkEmpty:
    sym.ast[idx] = Node(impl)
  else:
    for imp in impl:
      tImpl.sons.add imp

proc extendObjectDef(ctx: ContextRef, sym: Symbol, node: Node) =
  # desc, name, impls, dirs, fields
  let tObj  = Object(sym.ast)
  let tDirs = Node(tObj.dirs)
  let obj   = Object(node)
  let dirs  = obj.dirs
  let tImpl = Node(tObj.implements)
  let impl  = Node(obj.implements)
  extendImplements(sym, 2, tImpl, impl)
  extendDirs(sym, 3, tDirs, dirs)
  let fields = Node(obj.fields)
  let tFields = Node(tObj.fields)
  for n in fields:
    tFields.sons.add n

proc extendInterfaceDef(ctx: ContextRef, sym: Symbol, node: Node) =
  # desc, name, impls, dirs, fields
  let tIface  = Interface(sym.ast)
  let tDirs   = Node(tIface.dirs)
  let iface   = Interface(node)
  let dirs    = iface.dirs
  let tImpl   = Node(tIface.implements)
  let impl    = Node(iface.implements)
  extendImplements(sym, 2, tImpl, impl)
  extendDirs(sym, 3, tDirs, dirs)
  let fields = Node(iface.fields)
  let tFields = Node(tIface.fields)
  for n in fields:
    tFields.sons.add n

proc extendUnionDef(ctx: ContextRef, sym: Symbol, node: Node) =
  # desc, name, dirs, members
  let tUni  = Union(sym.ast)
  let tDirs = Node(tUni.dirs)
  let uni   = Union(node)
  let dirs  = uni.dirs
  extendDirs(sym, 2, tDirs, dirs)
  let members = uni.members
  let tMembers = tUni.members
  for n in members:
    tMembers.sons.add n

proc extendEnumDef(ctx: ContextRef, sym: Symbol, node: Node) =
  # desc, name, dirs, values
  let tEnum   = Enum(sym.ast)
  let tDirs   = Node(tEnum.dirs)
  let enumDef = Enum(node)
  let dirs    = enumDef.dirs
  extendDirs(sym, 2, tDirs, dirs)
  let values  = Node(enumDef.values)
  let tValues = Node(tEnum.values)
  for n in values:
    tValues.sons.add n

proc extendInputObjectDef(ctx: ContextRef, sym: Symbol, node: Node) =
  # desc, name, dirs, fields
  let tInput = InputObject(sym.ast)
  let tDirs  = Node(tInput.dirs)
  let input  = InputObject(node)
  let dirs   = input.dirs
  extendDirs(sym, 2, tDirs, dirs)
  let fields = Node(input.fields)
  let tFields = Node(tInput.fields)
  for n in fields:
    tFields.sons.add n

proc visitExtension(ctx: ContextRef, root: Node, idx: int) =
  # skip the 'extend'
  let node = root[idx][0]
  doAssert(node.kind in TypeDefNodes)

  let name = node[1]
  sym := findType(name, toSymKind(node.kind))

  case node.kind
  of nkSchemaDef:     visit extendSchema(sym, node)
  of nkScalarDef:     visit extendScalar(sym, node)
  of nkObjectDef:     visit extendObjectDef(sym, node)
  of nkInterfaceDef:  visit extendInterfaceDef(sym, node)
  of nkUnionDef:      visit extendUnionDef(sym, node)
  of nkEnumDef:       visit extendEnumDef(sym, node)
  of nkInputObjectDef:visit extendInputObjectDef(sym, node)
  else:
    unreachable()

proc secondPass(ctx: ContextRef, root: Node) =
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
      visit visitQuery(n)
    of skMutation:
      inc opCount
      visit visitMutation(n)
    of skSubscription:
      inc opCount
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
    of skQuery:       visit queryQuery(n)
    of skMutation:    visit mutationMutation(n)
    of skSubscription:visit subscriptionSubscription(n)
    else:
      discard

  # validate anon op
  let anonSym = findOp(ctx.names.anonName)
  invalid anonSym.isNil.not and opCount > 1:
    ctx.error(ErrOnlyOne, anonSym.ast[0], "anonymous operation")

proc validate*(ctx: ContextRef, root: Node) =
  if root.kind != nkMembers:
    ctx.error("expect nkMembers")
    return

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
