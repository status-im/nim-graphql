# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  std/[tables, hashes],
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
    nkCustomScalar      = "CustomScalar"

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

  NodeObj* {.acyclic.} = object
    pos* {.requiresInit.}: Pos
    case kind*: NodeKind
    of nkInt: intVal*: string
    of nkFloat: floatVal*: string
    of nkBoolean: boolVal*: bool
    of nkString, nkCustomScalar:
      stringVal*: string
    of nkEnum, nkVariable, nkName, nkNamedType:
      name*: Name
    of nkSym:
      sym*: Symbol
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
    sfBuiltin
    sfRepeatable # directive
    sfUsed

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

  ScalarParam* = object
    outNode*: Node
    expectedTypes*: set[NodeKind]

  ScalarProc* = proc(node: Node, output: var ScalarParam): bool

  ScalarRef* = ref ScalarObj

  ScalarObj* = object
    parseLit*: ScalarProc

  Symbol* = ref SymObj

  SymObj* {.acyclic.} = object
    case kind* : SymKind
    of skDirective:
      dirLocs*: set[DirLoc] # Directive locations
    of skScalar:
      scalar*: ScalarRef
    of skEnum, skInputObject,
      skInterface, skObject:
      fields*: Table[Name, Node]
    of skQuery, skMutation,
      skSubscription, skFragment:
      vars*: Table[Name, Node]
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
  BasicNodes*  = { nkInt, nkFloat, nkBoolean, nkString, nkSym, nkCustomScalar, nkNull }
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

template len*(n: Node): int =
  n.sons.len

template `[]`*(n: Node, i: int): Node =
  n.sons[i]

template `[]=`*(n: Node, i: int, x: Node) =
  n.sons[i] = x

iterator items*(n: Node): Node =
  for x in n.sons:
    yield x

iterator pairs*(n: Node): (int, Node) =
  for i in 0 ..< n.sons.len:
    yield (i, n.sons[i])

proc treeTraverse(n: Node; res: var string; level = 0; indented = false) =
  if level > 0:
    if indented:
      res.add("\n")
      for i in 0 .. level-1:
        res.add("  ")
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
  of nkString, nkCustomScalar:
    res.add(" " & $n.stringVal)
  of nkEnum, nkVariable, nkName, nkNamedType:
    res.add(" " & $n.name)
  of nkSym:
    res.add(" " & $n.sym.name)
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
  of nkString, nkCustomScalar:
    result = $n.stringVal
  of nkEnum, nkVariable, nkName, nkNamedType:
    result = $n.name
  of nkSym:
    result = $n.sym.name
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