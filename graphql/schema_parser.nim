# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  ./lexer,
  ./common_parser, ./common/[names, ast]

export
  common_parser.Parser,
  common_parser.ParserError,
  common_parser.ParserFlag,
  common_parser.init,
  ast

proc operationKind*(q: var Parser, opKind: var Node) =
  if currToken == tokName and currName in OperationNames:
    opKind ::= name
  else:
    q.parserError(errUnexpectedName, "valid operation names")

proc operationTypeDef(q: var Parser, op: var Node) =
  opKind := operationKind
  expect tokColon
  opName := namedType
  op = newTree(nkPair, opKind, opName)

proc schemaDef(q: var Parser, desc: Node, extMode: bool, def: var Node) =
  var schemaName: Node
  expect kwSchema:
    # always the same name, ensure only one schema
    # during validation pass
    schemaName = newNameNode(q.lex.name, q.pos)

  dirs := directives(true)

  var members = q.emptyNode
  if extMode:
    expectOptional tokLCurly:
      members = newNode(nkMembers)
      repeatUntil(q.conf.maxSchemaElems, tokRCurly):
        opType := operationTypeDef
        members <- opType
  else:
    expect tokLCurly
    members = newNode(nkMembers)
    repeatUntil(q.conf.maxSchemaElems, tokRCurly):
      opType := operationTypeDef
      members <- opType

  def = newTree(nkSchemaDef, desc, schemaName, dirs, members)

proc scalarTypeDef(q: var Parser, desc: Node, def: var Node) =
  expect kwScalar
  scalarName := resName
  dirs       := directives(true)
  def = newTree(nkScalarDef, desc, scalarName, dirs)

proc description(q: var Parser, desc: var Node) =
  if currToken in DescriptionTokens:
    desc = newNode(nkString)
    desc.stringVal = q.lex.token
    nextToken

proc inputValueDef(q: var Parser, arg: var Node) =
  desc := description
  argName := resName
  expect tokColon
  rgReset(rgTypeRef)
  argType := typeRef

  var defVal = q.emptyNode
  expectOptional tokEqual:
    rgReset(rgValueLiteral)
    defVal ::= valueLiteral(true)

  dirs := directives(true)
  arg = newTree(nkInputValue, desc, argName, argType, defVal, dirs)

proc argumentDefs(q: var Parser, args: var Node) =
  if currToken == tokLParen:
    args = newNode(nkArguments)
  repeatOptional(q.conf.maxArguments, tokLParen, tokRParen):
    arg := inputValueDef
    args <- arg

proc fieldDef(q: var Parser, field: var Node) =
  desc := description
  fieldName := resName
  args := argumentDefs
  expect tokColon
  rgReset(rgTypeRef)
  fieldType := typeRef
  dirs := directives(true)
  field = newTree(nkFieldDef, desc, fieldName, args, fieldType, dirs)

proc fieldDefs(q: var Parser, fields: var Node) =
  if currToken == tokLCurly:
    fields = newNode(nkMembers)
  repeatOptional(q.conf.maxFields, tokLCurly, tokRCurly):
    field := fieldDef
    fields <- field

proc implementsInterfaces(q: var Parser, names: var Node) =
  expectOptional kwImplements:
    names = newNode(nkImplement)
    repeat(q.conf.maxChoices, tokAmp):
      name := namedType
      names <- name

proc objectTypeDef(q: var Parser, desc: Node, def: var Node) =
  expect kwType
  objName := resName
  ifaces  := implementsInterfaces
  dirs    := directives(true)
  fields  := fieldDefs
  def = newTree(nkObjectDef, desc, objName, ifaces, dirs, fields)

proc interfaceTypeDef(q: var Parser, desc: Node, def: var Node) =
  expect kwInterface
  defName := resName
  ifaces  := implementsInterfaces
  dirs    := directives(true)
  fields  := fieldDefs
  def = newTree(nkInterfaceDef, desc, defName, ifaces, dirs, fields)

proc unionMemberTypes(q: var Parser, names: var Node) =
  expectOptional tokEqual:
    names = newNode(nkMembers)
    repeat(q.conf.maxChoices, tokPipe):
      name := namedType
      names <- name

proc unionTypeDef(q: var Parser, desc: Node, def: var Node) =
  expect kwUnion
  defName := resName
  dirs    := directives(true)
  members := unionMemberTypes
  def = newTree(nkUnionDef, desc, defName, dirs, members)

proc enumVal(q: var Parser, val: var Node) =
  const
    InvalidEnumVals = {
      kwTrue,
      kwFalse,
      kwNull
    }

  if currName notin InvalidEnumVals:
    val ::= name
  else:
    q.parserError(errUnexpectedName, "valid enum value")

proc enumValDef(q: var Parser, def: var Node) =
  desc := description
  val  := enumVal
  dirs := directives(true)
  def = newTree(nkEnumVal, desc, val, dirs)

proc enumValDefs(q: var Parser, vals: var Node) =
  if currToken == tokLCurly:
    vals = newNode(nkMembers)
  repeatOptional(q.conf.maxEnumVals, tokLCurly, tokRCurly):
    val := enumValDef
    vals <- val

proc enumTypeDef(q: var Parser, desc: Node, def: var Node) =
  expect kwEnum
  defName := resName
  dirs    := directives(true)
  vals    := enumValDefs
  def = newTree(nkEnumDef, desc, defName, dirs, vals)

proc inputFieldDefs(q: var Parser, fields: var Node) =
  if currToken == tokLCurly:
    fields = newNode(nkMembers)
  repeatOptional(q.conf.maxFields, tokLCurly, tokRCurly):
    field := inputValueDef
    fields <- field

proc inputObjectTypeDef(q: var Parser, desc: Node, def: var Node) =
  expect kwInput
  defName := resName
  dirs    := directives(true)
  fields  := inputFieldDefs
  def = newTree(nkInputObjectDef, desc, defName, dirs, fields)

proc directiveLocation(q: var Parser, loc: var Node) =
  const validLoc = {LocQUERY..LocINPUT_FIELD_DEFINITION}
  if currToken == tokName and currName in validLoc:
    loc ::= name
  else:
    q.parserError(errInvalidDirectiveLoc, "valid directive location")

proc directiveLocations(q: var Parser, locs: var Node) =
  locs = newNode(nkMembers)
  repeat(q.conf.maxChoices, tokPipe):
    loc := directiveLocation
    locs <- loc

proc directiveDef(q: var Parser, desc: Node, def: var Node) =
  expect kwDirective
  expect tokAt
  defName := resName
  args    := argumentDefs

  var repeatable = q.emptyNode
  if isKeyWord(kwRepeatable):
    repeatable ::= name

  expect kwOn
  locs := directiveLocations
  def = newTree(nkDirectiveDef, desc, defName, args, repeatable, locs)

proc typeSystemImpl(q: var Parser, extMode: bool, def: var Node) =
  # Many definitions begin with a description
  var desc = q.emptyNode
  if not extMode:
    desc ::= description

  case currName
  of kwSchema:
    def ::= schemaDef(desc, extMode)
  of kwScalar:
    def ::= scalarTypeDef(desc)
  of kwType:
    def ::= objectTypeDef(desc)
  of kwInterface:
    def ::= interfaceTypeDef(desc)
  of kwUnion:
    def ::= unionTypeDef(desc)
  of kwEnum:
    def ::= enumTypeDef(desc)
  of kwInput:
    def ::= inputObjectTypeDef(desc)
  of kwDirective:
    if not extMode:
      def ::= directiveDef(desc)
    else:
      q.parserError(errUnexpectedName, "extendable type, except directive")
  else:
    q.parserError(errUnexpectedName, "valid typedef type")

template typeSystemDef*(q: var Parser, exts: var Node) =
  typeSystemImpl(q, extMode = false, exts)

template typeSystemExt*(q: var Parser, exts: var Node) =
  typeSystemImpl(q, extMode = true, exts)

proc definition(q: var Parser, def: var Node) =
  case currToken
  of tokName:
    case currName
    of TypeSystemNames:
      def ::= typeSystemDef
    of kwExtend:
      def = Node(kind: nkExtend, pos: q.pos)
      nextToken
      ext := typeSystemExt
      def <- ext
    else:
      q.parserError(errUnexpectedName, "type definition or type extension")
  of DescriptionTokens:
    def ::= typeSystemDef
  else:
    q.parserError(errUnexpectedToken, "description or type definition")

proc parseDocument*(q: var Parser, doc: var SchemaDocument) =
  nextToken
  doc.root = newNode(nkMembers)
  if currToken == tokEof:
    return
  repeatUntil(q.conf.maxDefinitions, tokEof):
    def := definition
    doc.root <- def
