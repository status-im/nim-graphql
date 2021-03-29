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
  common_parser.errDesc,
  ast

# forward declaration
proc selectionSet(q: var Parser, sels: var Node)

proc variableDef(q: var Parser, varDef: var Node) =
  varName := variable
  expect tokColon
  rgReset(rgTypeRef)
  varType := typeRef

  var defVal = q.emptyNode
  expectOptional tokEqual:
    rgReset(rgValueLiteral)
    defVal ::= valueLiteral(true)

  dirs := directives(true)
  varDef = newTree(nkVarDef, varName, varType, defVal, dirs)

proc variableDefs(q: var Parser, vars: var Node) =
  if currToken == tokLParen:
    vars = newNode(nkArguments)
  repeatOptional(q.conf.maxArguments, tokLParen, tokRParen):
    varDef := variableDef
    vars <- varDef

proc fragmentName(q: var Parser, fragName: var Node) =
  if isKeyword(kwOn):
    q.parserError(errUnexpectedName, "valid fragment name")
    return

  fragName ::= name

proc fragment(q: var Parser, sel: var Node) =
  expect tokEllipsis
  let hasTypeCondition = isKeyword kwOn

  if hasTypeCondition:
    nextToken
    typeCond := namedType
    dirs     := directives(false)
    rgReset(rgSelectionSet)
    sels     := selectionSet
    sel = newTree(nkInlineFragment, typeCond, dirs, sels)
  elif currToken == tokName:
    fragName := fragmentName
    dirs     := directives(false)
    sel = newTree(nkFragmentSpread, fragName, dirs)
  else:
    q.parserError(errUnexpectedToken, "'on' or valid fragment name")

proc field(q: var Parser, sel: var Node) =
  fieldName := name

  var alias = q.emptyNode
  expectOptional tokColon:
    alias = fieldName
    fieldName ::= name

  args := arguments(false)
  dirs := directives(false)

  var sels = q.emptyNode
  if currToken == tokLCurly:
    # no need for rgReset here
    sels ::= selectionSet

  sel = newTree(nkField, alias, fieldName, args, dirs, sels)

proc selection(q: var Parser, sel: var Node) =
  if currToken == tokEllipsis:
    sel ::= fragment
  else:
    sel ::= field

proc selectionSet(q: var Parser, sels: var Node) =
  rgCheck(rgSelectionSet, q.conf.maxRecursionLimit)
  sels = newNode(nkSelectionSet)
  expect tokLCurly
  repeatUntil(q.conf.maxFields, tokRCurly):
    sel := selection
    sels <- sel

proc operationType(q: var Parser, opKind: var NodeKind) =
  if currToken == tokName and currName in OperationNames:
    opKind = NodeKind(q.lex.name.id - kwQuery.int + nkQuery.int)
    nextToken
  else:
    q.parserError(errUnexpectedName, "valid operation names")

proc operationDef*(q: var Parser, defs: var Node) =
  if currToken == tokLCurly:
    rgReset(rgSelectionSet)
    sels := selectionSet
    defs = newTree(nkQuery,
      newNameNode(q.lex.names.anonName, q.pos),
      q.emptyNode,
      q.emptyNode,
      sels)
    return

  var kind: NodeKind
  kind ::= operationType

  var opName: Node
  if currToken == tokName:
    opName ::= name
  else:
    opName = newNameNode(q.lex.names.anonName, q.pos)

  vars := variableDefs
  dirs := directives(false)
  rgReset(rgSelectionSet)
  sels := selectionSet
  defs = newTree(kind, opName, vars, dirs, sels)

proc fragmentDef*(q: var Parser, def: var Node) =
  expect kwFragment
  fragName := fragmentName

  var vars = q.emptyNode
  if pfExperimentalFragmentVariables in q.flags:
    vars ::= variableDefs

  expect kwOn
  typeCond := namedType
  dirs     := directives(false)
  rgReset(rgSelectionSet)
  sels     := selectionSet
  def = newTree(nkFragment, fragName, vars, typeCond, dirs, sels)

proc definition(q: var Parser, def: var Node) =
  case currToken
  of tokLCurly:
    def ::= operationDef
  of tokName:
    case currName
    of OperationNames:
      def ::= operationDef
    of kwFragment:
      def ::= fragmentDef
    else:
      q.parserError(errUnexpectedName, "valid operation type or fragment")
  else:
    q.parserError(errUnexpectedToken, "fragment or operation definition")

proc parseDocument*(q: var Parser, doc: var QueryDocument) =
  nextToken
  doc.root = newNode(nkMembers)
  if currToken == tokEof:
    return
  repeatUntil(q.conf.maxDefinitions, tokEof):
    def := definition
    doc.root <- def
