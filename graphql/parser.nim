# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  ./lexer, ./common/names,
  ./common_parser, ./schema_parser, ./query_parser,
  ./common/ast

export
  common_parser.Parser,
  common_parser.ParserError,
  common_parser.ParserFlag,
  common_parser.init,
  common_parser.defaultParserConf,
  ast

{.push gcsafe, raises: [IOError] .}

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
    of TypeSystemNames:
      def ::= typeSystemDef
    of kwExtend:
      def = Node(kind: nkExtend, pos: q.pos)
      nextToken
      ext := typeSystemExt
      def <- ext
    else:
      q.parserError(errUnexpectedName, "type or operation definition")
  of DescriptionTokens:
    def ::= typeSystemDef
  else:
    q.parserError(errUnexpectedToken, "type or operation definition")

proc parseDocument*(q: var Parser, doc: var FullDocument) =
  nextToken
  doc.root = newNode(nkMembers)
  if currToken == tokEof:
    return
  repeatUntil(q.conf.maxDefinitions, tokEof):
    def := definition
    doc.root <- def

{.pop.}
