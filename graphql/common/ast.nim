# nim-graphql
# Copyright (c) 2021-2025 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  std/[tables, hashes],
  results,
  ./types, ./names

type
  NodeKind* = enum
    nkEmpty             = "Empty"

    # value nodes
    nkNull              = "Null"
    nkInt               = "Int"
    nkFloat             = "Float"
    nkString            = "String"
    nkBoolean           = "Boolean"
    nkEnum              = "Enum"
    nkList              = "List"
    nkInput             = "Input"
    nkVariable          = "Variable"
    nkMap               = "Map"

    nkName              = "Name"
    nkSym               = "Symbol"
    nkInputField        = "InputField"
    nkDirective         = "Directive"
    nkPair              = "Pair"
    nkVarDef            = "VarDef"
    nkArguments         = "Arguments"    # nkVarDef, nkPair, nkInputValue
    nkMembers           = "Members"      # nkEnumVal, nkFieldDef, nkDirective,
                                         # nkInputValue, union members,
                                         # directive locations, definitions

    # typeref
    nkNamedType         = "NamedType"
    nkListType          = "ListType"
    nkNonNullType       = "NonNullType"

    # query related
    nkInlineFragment    = "InlineFragment"
    nkFragmentSpread    = "FragmentSpread"
    nkSelectionSet      = "SelectionSet"
    nkField             = "Field"

    nkQuery             = "Query"
    nkMutation          = "Mutation"
    nkSubscription      = "Subscription"
    nkFragment          = "Fragment"

    # type system
    nkExtend            = "Extend"
    nkInputValue        = "InputValue"
    nkImplement         = "Implement"
    nkEnumVal           = "EnumVal"

    nkFieldDef          = "FieldDef"
    nkSchemaDef         = "SchemaDef"
    nkScalarDef         = "ScalarDef"
    nkObjectDef         = "ObjectDef"
    nkInterfaceDef      = "InterfaceDef"
    nkUnionDef          = "UnionDef"
    nkEnumDef           = "EnumDef"
    nkInputObjectDef    = "InputObjectDef"
    nkDirectiveDef      = "DirectiveDef"

  Node* = ref NodeObj

  NodeObj* {.acyclic.} = object of RootObj
    pos* {.requiresInit.}: Pos
    case kind*: NodeKind
    of nkInt: intVal*: string
    of nkFloat: floatVal*: string
    of nkBoolean: boolVal*: bool
    of nkString:
      stringVal*: string
    of nkEnum, nkVariable, nkName, nkNamedType:
      name*: Name
    of nkSym:
      sym*: Symbol
    of nkMap:
      typeName*: Name
      map*: seq[tuple[key: string, val: Node]]
    else:
      sons*: seq[Node]

  SymKind* = enum
    skQuery         = "query"
    skMutation      = "mutation"
    skSubscription  = "subscription"
    skFragment      = "fragment"
    skSchema        = "schema"
    skScalar        = "scalar"
    skObject        = "object"
    skInterface     = "interface"
    skUnion         = "union"
    skEnum          = "enum"
    skInputObject   = "input object"
    skDirective     = "directive"
    skVariable      = "variable"

  SymFlag* = enum
    sfBuiltin      # for introspection types
    sfRepeatable   # for directives
    sfUsed         # for variables
    sfHasVariables # for operations

  DirLoc* = enum
    # ExecutableDirectiveLocation
    dlQUERY                  = "QUERY"
    dlMUTATION               = "MUTATION"
    dlSUBSCRIPTION           = "SUBSCRIPTION"
    dlFIELD                  = "FIELD"
    dlFRAGMENT_DEFINITION    = "FRAGMENT_DEFINITION"
    dlFRAGMENT_SPREAD        = "FRAGMENT_SPREAD"
    dlINLINE_FRAGMENT        = "INLINE_FRAGMENT"
    dlVARIABLE_DEFINITION    = "VARIABLE_DEFINITION"

    # TypeSystemDirectiveLocation
    dlSCHEMA                 = "SCHEMA"
    dlSCALAR                 = "SCALAR"
    dlOBJECT                 = "OBJECT "
    dlFIELD_DEFINITION       = "FIELD_DEFINITION"
    dlARGUMENT_DEFINITION    = "ARGUMENT_DEFINITION"
    dlINTERFACE              = "INTERFACE"
    dlUNION                  = "UNION"
    dlENUM                   = "ENUM"
    dlENUM_VALUE             = "ENUM_VALUE"
    dlINPUT_OBJECT           = "INPUT_OBJECT"
    dlINPUT_FIELD_DEFINITION = "INPUT_FIELD_DEFINITION"

  NodeResult* = Result[Node, string]
  # Should  be identical to CoercionProc in graphql.nim
  ScalarProc* = proc(ctx: RootRef, typeNode, node: Node): NodeResult {.cdecl, gcsafe, noSideEffect.}

  Symbol* = ref SymObj

  SymObj* {.acyclic.} = object
    case kind* : SymKind
    of skDirective:
      dirLocs*: set[DirLoc] # Directive locations
    of skScalar:
      coerce*: ScalarProc # this proc for variables
      scalar*: ScalarProc # this one for args/input fields/response
    of skEnum:
      coerceEnum*: ScalarProc # this proc for variables
      enumVals*: Table[Name, Node]
    of skInputObject:
      inputFields*: Table[Name, Node]
    of skInterface:
      types*: seq[Node] # possible types that implements this interface
      interfaceFields*: Table[Name, Node]
    of skObject:
      objectFields*: Table[Name, Node]
    of skQuery, skMutation,
      skSubscription, skFragment:
      vars*: Table[Name, Node]
      exec*: RootRef # this is an ExecRef
      astCopy*: Node
    else: nil
    name* : Name
    ast*  : Node
    flags*: set[SymFlag]

  QueryDocument* = object
    root*: Node

  SchemaDocument* = object
    root*: Node

  FullDocument* = object
    root*: Node

const
  BasicNodes*  = { nkInt, nkFloat, nkBoolean, nkString, nkSym, nkNull }
  NamedNodes*  = { nkEnum, nkVariable, nkName, nkNamedType }
  NoSonsNodes* = BasicNodes + NamedNodes
  TypeNodes*   = { nkNamedType, nkListType, nkNonNullType }

  TypeDefNodes* = {
    nkSchemaDef,
    nkScalarDef,
    nkObjectDef,
    nkInterfaceDef,
    nkUnionDef,
    nkEnumDef,
    nkInputObjectDef,
    nkDirectiveDef
    }

  InputTypes*  = { skScalar, skEnum, skInputObject }
  OutputTypes* = { skScalar, skObject, skInterface, skUnion, skEnum }
  TypeConds*   = { skObject, skInterface, skUnion }

  unreachableCode* = "unreachableCode"

{.push gcsafe, raises: [] .}

template unreachable*() =
  assert(false, unreachableCode)

proc hash*(sym: Symbol): Hash =
  hash(sym.name)

proc newTree*(kind: NodeKind; children: varargs[Node]): Node =
  result = Node(kind: kind, pos: Pos())
  if children.len > 0:
    result.pos = children[0].pos
  result.sons = @children

proc newNameNode*(name: Name, pos = Pos()): Node =
  Node(kind: nkName, name: name, pos: pos)

proc newSym*(kind: SymKind, name: Name, ast: Node): Symbol =
  Symbol(kind: kind, name: name, ast: ast)

proc newSymNode*(kind: SymKind, name: Name, ast: Node, pos = Pos()): Node =
  Node(kind: nkSym, pos: pos, sym: newSym(kind, name, ast))

proc newSymNode*(sym: Symbol, pos = Pos()): Node =
  Node(kind: nkSym, pos: pos, sym: sym)

template `<-`*(n, son: Node) =
  n.sons.add son

template add*(n, son: Node) =
  n.sons.add son

template len*(n: Node): int =
  n.sons.len

template `[]`*(n: Node, i: int): Node =
  n.sons[i]

template `[]=`*(n: Node, i: int, x: Node) =
  n.sons[i] = x

template `[]=`*(n: Node, k: string, v: Node) =
  n.map.add((k, v))

iterator items*(n: Node): Node =
  for x in n.sons:
    yield x

iterator pairs*(n: Node): (int, Node) =
  for i in 0 ..< n.sons.len:
    yield (i, n.sons[i])

iterator mapPair*(n: Node): (string, Node) =
  for i in 0 ..< n.map.len:
    yield n.map[i]

proc treeTraverse(n: Node; res: var string; level = 0; indented = false) =
  proc indent(res: var string, level: int) =
    for i in 0 .. level-1:
      res.add("  ")

  if level > 0:
    if indented:
      res.add("\n")
      indent(res, level)
    else:
      res.add(" ")

  res.add($n.kind)

  case n.kind
  of nkEmpty, nkNull:
    discard
  of nkBoolean:
    res.add(" " & $n.boolVal)
  of nkInt:
    res.add(" " & $n.intVal)
  of nkFloat:
    res.add(" " & $n.floatVal)
  of nkString:
    res.add(" " & $n.stringVal)
  of nkEnum, nkVariable, nkName, nkNamedType:
    res.add(" " & $n.name)
  of nkSym:
    res.add(" " & $n.sym.name)
  of nkMap:
    res.add(" " & $n.typeName & " \n")
    for k, v in n.mapPair:
      if indented:
        indent(res, level)
      res.add(" " & k & ": ")
      treeTraverse(v, res, level+1, false)
      res.add("\n")
  else:
    for j in 0 ..< n.len:
      n[j].treeTraverse(res, level+1, indented)

proc treeRepr*(n: Node): string =
  result = ""
  n.treeTraverse(result, indented = true)

proc `$`*(n: Node): string =
  case n.kind
  of nkEmpty:
    result = ":empty:"
  of nkNull:
    result = "null"
  of nkBoolean:
    result = $n.boolVal
  of nkInt:
    result = $n.intVal
  of nkFloat:
    result = $n.floatVal
  of nkString:
    result = '\"' & n.stringVal & '\"'
  of nkEnum, nkVariable, nkName, nkNamedType:
    result = $n.name
  of nkSym:
    result = $n.sym.name
  of nkMap:
    result = $n.typeName
  else:
    result = $n.kind

proc toSymKind*(kind: NodeKind): SymKind =
  case kind
  of nkSchemaDef: return skSchema
  of nkScalarDef: return skScalar
  of nkObjectDef: return skObject
  of nkInterfaceDef: return skInterface
  of nkUnionDef: return skUnion
  of nkEnumDef: return skEnum
  of nkInputObjectDef: return skInputObject
  of nkDirectiveDef: return skDirective
  else: doAssert(false)

proc nullableType*(node: Node): bool =
  case node.kind
  of nkNonNullType:
    case node[0].kind
    of nkListType:
      return true
    of nkSym, nkNamedType:
      return false
    else:
      unreachable()
  of nkListType, nkSym, nkNamedType:
    return true
  else:
    unreachable()

proc copyTree*(n: Node): Node =
  if n.isNil:
    return
  result = Node(kind: n.kind, pos: n.pos)
  case n.kind
  of nkInt:     result.intVal    = n.intVal
  of nkFloat:   result.floatVal  = n.floatVal
  of nkBoolean: result.boolVal   = n.boolVal
  of nkString:  result.stringVal = n.stringVal
  of nkEnum, nkVariable, nkName, nkNamedType:
    result.name = n.name
  of nkSym:
    result.sym = n.sym
  of nkMap:
    result.typeName = n.typeName
    for c in n.map:
      result[c.key] = copyTree(c.val)
  else:
    for c in n.sons:
      result.sons.add copyTree(c)

proc compareTree*(a: Node, b: Node): bool =
  if a.isNil:
    if b.isNil: return true
    return false
  elif b.isNil:
    return false
  elif a.kind != b.kind:
    return false

  case a.kind
  of nkInt:
    if a.intVal != b.intVal:
      return false
  of nkFloat:
    if a.floatVal != b.floatVal:
      return false
  of nkBoolean:
    if a.boolVal != b.boolVal:
      return false
  of nkString:
    if a.stringVal != b.stringVal:
      return false
  of nkEnum, nkVariable, nkName, nkNamedType:
    if a.name != b.name:
      return false
  of nkSym:
    if a.sym != b.sym:
      return false
  of nkMap:
    if a.typeName != b.typeName:
      return false

    var
      aFields = initTable[string, Node]()
      bFields = initTable[string, Node]()

    for x in a.map:
      if x.val.kind != nkNull:
        aFields[x.key] = x.val

    for x in b.map:
      if x.val.kind != nkNull:
        bFields[x.key] = x.val

    if aFields.len != bFields.len:
      return false

    for key, val in aFields:
      var bVal = bFields.getOrDefault(key, Node(nil))
      if bVal.isNil:
        return false
      if not compareTree(val, bVal):
        return false
  else:
    if a.sons.len != b.sons.len:
      return false
    for i, x in a.sons:
      if not compareTree(x, b.sons[i]):
        return false

  true

proc getField*(sym: Symbol, name: Name): Node =
  case sym.kind
  of skInterface:
    return sym.interfaceFields.getOrDefault(name)
  of skObject:
    return sym.objectFields.getOrDefault(name)
  of skInputObject:
    return sym.inputFields.getOrDefault(name)
  else:
    unreachable()

proc setField*(sym: Symbol, name: Name, node: Node) =
  case sym.kind
  of skObject:
    sym.objectFields[name] = node
  of skInterface:
    sym.interfaceFields[name] = node
  else:
    unreachable()

{.pop.}
