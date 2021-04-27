# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  strutils,
  stew/shims/macros,
  faststreams/inputs,
  ./common/[types, names, errors, ast],
  ./lexer

type
  ParserError* = enum
    errNone
    errUnexpectedToken
    errUnexpectedName
    errExpectToken
    errExpectName
    errInvalidDirectiveLoc
    errInvalidName
    errRecursionLimit
    errLoopLimit

  ParserFlag* = enum
    pfExperimentalFragmentVariables
    pfAcceptReservedWords # any name prefixed with "__"
    pfJsonCompatibility # input object keys can be string
    pfJsonKeyToName

  RecursionGuard* = enum
    rgTypeRef       = "TypeDef"
    rgSelectionSet  = "SelectionSet"
    rgValueLiteral  = "ValueLiteral"

  ParserConf* = object
    lexerConf*        : LexConf
    maxRecursionLimit*: int
    maxListElems*     : int
    maxFields*        : int
    maxArguments*     : int
    maxSchemaElems*   : int
    maxEnumVals*      : int
    maxDefinitions*   : int
    maxChoices*       : int

  ParserConfInternal* = object
    maxRecursionLimit*: int
    maxListElems*     : LoopGuard
    maxFields*        : LoopGuard
    maxArguments*     : LoopGuard
    maxSchemaElems*   : LoopGuard
    maxEnumVals*      : LoopGuard
    maxDefinitions*   : LoopGuard
    maxChoices*       : LoopGuard

  Parser* = object
    lex*  : Lexer
    error*: ParserError
    flags*: set[ParserFlag]
    err*  : ErrorDesc
    conf* : ParserConfInternal
    emptyNode*: Node
    rgCount*  : array[RecursionGuard, int]

const
  OperationNames* = {
    kwQuery,
    kwMutation,
    kwSubscription
    }

  TypeSystemNames* = {
    kwSchema,
    kwScalar,
    kwType,
    kwInterface,
    kwUnion,
    kwEnum,
    kwInput,
    kwDirective
    }

  DescriptionTokens* = {
    tokString,
    tokBlockString
    }

proc defaultParserConf*(): ParserConf =
  result.lexerConf = defaultLexConf()
  result.maxRecursionLimit = 25
  result.maxListElems      = 128
  result.maxFields         = 128
  result.maxArguments      = 32
  result.maxSchemaElems    = 3
  result.maxEnumVals       = 64
  result.maxDefinitions    = 512
  result.maxChoices        = 64

proc toInternalConf(conf: ParserConf): ParserConfInternal =
  result.maxRecursionLimit = conf.maxRecursionLimit
  result.maxListElems   = LoopGuard(maxLoop: conf.maxListElems, desc: "max list elements")
  result.maxFields      = LoopGuard(maxLoop: conf.maxFields, desc: "max fields")
  result.maxArguments   = LoopGuard(maxLoop: conf.maxArguments, desc: "max arguments")
  result.maxSchemaElems = LoopGuard(maxLoop: conf.maxSchemaElems, desc: "max schema elements")
  result.maxEnumVals    = LoopGuard(maxLoop: conf.maxEnumVals, desc: "max enum values")
  result.maxDefinitions = LoopGuard(maxLoop: conf.maxDefinitions, desc: "max definitions")
  result.maxChoices     = LoopGuard(maxLoop: conf.maxChoices, desc: "max choices and concats")

proc init*(T: type Parser, stream: InputStream, conf = defaultParserConf()): T =
  let names = newNameCache()
  T(lex: Lexer.init(stream, names, conf.lexerConf),
    emptyNode: Node(kind: nkEmpty, pos: Pos()),
    conf: toInternalConf(conf)
   )

proc init*(T: type Parser, stream: InputStream, names: NameCache, conf = defaultParserConf()): T =
  T(lex: Lexer.init(stream, names, conf.lexerConf),
    emptyNode: Node(kind: nkEmpty, pos: Pos()),
    conf: toInternalConf(conf)
   )

template pos*(q: Parser): Pos =
  q.lex.pos()

template newNode*(nk: NodeKind): Node =
  Node(pos: q.pos, kind: nk)

template newNode*(nk: NodeKind, n: Name): Node =
  Node(pos: q.pos, kind: nk, name: n)

template currToken*: TokKind =
  q.lex.tok

template currName*: Keyword =
  toKeyword(q.lex.name)

proc parserError*(q: var Parser, err: ParserError, args: varargs[string, `$`]) =
  q.error = err
  if currToken == tokError:
    q.err = q.lex.err
    return

  q.err.pos = q.pos
  q.err.level = elError
  case err
  of errUnexpectedToken, errExpectToken:
    doAssert(args.len >= 1)
    q.err.message = "get $1, expect $2" % [$currToken, args[0]]
  of errUnexpectedName, errExpectName, errInvalidDirectiveLoc, errInvalidName:
    doAssert(args.len >= 1)
    if currToken != tokName:
      q.err.message = "get $1, expect $2" % [$currToken, args[0]]
    else:
      q.err.message = "get '$1', expect $2" % [q.lex.name.s, args[0]]
  of errRecursionLimit:
    doAssert(args.len >= 2)
    q.err.message = "recursion limit $1 reached for $2" % [args[0], args[1]]
  of errLoopLimit:
    doAssert(args.len >= 2)
    q.err.message = "loop limit $1 reached for $2" % [args[0], args[1]]
  else:
    doAssert(false, "unimplemented parser error " & $err)

template nextToken* =
  q.lex.next()

template isKeyword*(x: Keyword): bool =
  q.lex.tok == tokName and currName() == x

macro callParser*(parserInst, parser, dest: untyped): untyped =
  case parser.kind
  of nnkCall:
    # parser(params) -> parser(parserInst, params, dest)
    parser.insert(1, parserInst)
    parser.add dest
    result = parser
  of nnkIdent:
    # parser -> parser(parserInst, dest)
    result = newCall(parser, parserInst, dest)
  else:
    error("unsupported parser")

# will inject new 'destination' symbol and
# shadow available symbol with same name
template `:=`*(dest, parser: untyped) =
  var `dest` {.inject.} = q.emptyNode
  callParser(q, parser, `dest`)
  if q.error != errNone:
    return

# assign to available destination without shadowing
template `::=`*(dest, parser: untyped) =
  callParser(q, parser, dest)
  if q.error != errNone:
    return

template expect*(token: TokKind) =
  if currToken() == token:
    nextToken()
  else:
    q.parserError(errExpectToken, token)
    return

template expect*(name: Keyword) =
  if isKeyword(name):
    nextToken()
  else:
    q.parserError(errExpectName, name)
    return

# branch will not contains parser, usually ast node creation
# or other initialization code
template expect*(token: TokKind, branch: untyped) =
  if currToken() == token:
    branch
    nextToken()
  else:
    q.parserError(errExpectToken, token)
    return

# branch will not contains parser, usually ast node creation
# or other initialization code
template expect*(name: Keyword, branch: untyped) =
  if isKeyword(name):
    branch
    nextToken()
  else:
    q.parserError(errExpectName, name)
    return

# branch can contains parser(s)
template expectOptional*(token: TokKind, branch: untyped) =
  if currToken() == token:
    nextToken()
    branch

# branch can contains parser(s)
template expectOptional*(name: Keyword, branch: untyped) =
  if isKeyword(name):
    nextToken()
    branch

# branch can contains parser(s)
template expectOptional*(token: TokKind, branch, branchElse: untyped) =
  if currToken() == token:
    nextToken()
    branch
  else:
    branchElse

template expectOptional*(token: TokKind) =
  if currToken() == token:
    nextToken()

template expectOptional*(name: Keyword) =
  if isKeyword(name):
    nextToken()

template loopGuard(loopCounter: int, maxLoop: int, desc: string) =
  inc loopCounter
  if loopCounter > maxLoop:
    q.parserError(errLoopLimit, maxLoop, desc)
    return

# body can contains parser(s)
template repeatUntil*(lg: LoopGuard, kind: TokKind, body: untyped) =
  var loopCounter = 0
  while true:
    body
    loopGuard(loopCounter, lg.maxLoop, lg.desc)
    if currToken() == kind:
      nextToken()
      break

# body can contains parser(s)
template repeatOptional*(lg: LoopGuard, openKind, closeKind: TokKind, body: untyped) =
  expectOptional openKind:
    var loopCounter = 0
    while true:
      body
      loopGuard(loopCounter, lg.maxLoop, lg.desc)
      if currToken() == closeKind:
        nextToken()
        break

# body can contains parser(s)
template repeat*(lg: LoopGuard, tok: TokKind, body: untyped) =
  expectOptional tok
  var loopCounter = 0
  while true:
    body
    loopGuard(loopCounter, lg.maxLoop, lg.desc)
    expectOptional tok:
      continue
    do:
      break

# warning!! cannot protect against cross recursion
# reset recurssion guard before call recursive proc
template rgReset*(x: RecursionGuard) =
  q.rgCount[x] = 0

template rgReset*(q: var Parser, x: RecursionGuard) =
  q.rgCount[x] = 0

# put this in the recursive proc
template rgCheck*(x: RecursionGuard, limit: int) =
  inc(q.rgCount[x])
  if q.rgCount[x] > limit:
    q.parserError(errRecursionLimit, limit, x)
    return

template rgPush(x: RecursionGuard): untyped =
  q.rgCount[x]

template rgPop(x: RecursionGuard, v: int): untyped =
  q.rgCount[x] = v

proc valueLiteral*(q: var Parser, isConst: bool, val: var Node)

# reserved word(prefixed with '__') used exclusively for instrospection
proc validName(q: var Parser, name: Name): bool =
  if pfAcceptReservedWords in q.flags:
    return true

  if name.s.len >= 2 and name.s[0] == '_' and
     name.s[1] == '_':
     q.parserError(errInvalidName, "name without '__' prefix in this context")
     return false

  return true

# accept any name intended for type reference
proc namedType*(q: var Parser, name: var Node) =
  expect tokName:
    name = newNode(nkNamedType)
    name.name = q.lex.name

# can be name of anything
proc name*(q: var Parser, name: var Node) =
  expect tokName:
    name = newNode(nkName)
    name.name = q.lex.name

# expect name without '__' prefix if pfAcceptReservedWords
# turned on
proc resName*(q: var Parser, name: var Node) =
  expect tokName:
    if not q.validName(q.lex.name):
      return
    name = newNode(nkName)
    name.name = q.lex.name

# input:: [T]
proc listVal(q: var Parser, isConst: bool, val: var Node) =
  expect tokLBracket
  val = newNode(nkList)
  if pfJsonCompatibility in q.flags and currToken == tokRBracket:
    nextToken()
    return
  repeatUntil(q.conf.maxListElems, tokRBracket):
    let savePoint = rgPush(rgValueLiteral)
    valLit := valueLiteral(isConst)
    val <- valLit
    rgPop(rgValueLiteral, savePoint)

proc inputFieldName(q: var Parser, fieldName: var Node) =
  if pfJsonCompatibility in q.flags and currToken == tokString:
    if pfJsonKeyToName in q.flags:
      # convert json string to nkName
      fieldName = newNode(nkName)
      fieldName.name = q.lex.names.insert(q.lex.token)
    else:
      fieldName = newNode(nkString)
      fieldName.stringVal = q.lex.token
    nextToken
  else:
    fieldName ::= name

# input:: field: T
proc objectField(q: var Parser, isConst: bool, field: var Node) =
  fieldName := inputFieldName
  expect tokColon
  let savePoint = rgPush(rgValueLiteral)
  fieldVal := valueLiteral(isConst)
  field = newTree(nkInputField, fieldName, fieldVal)
  rgPop(rgValueLiteral, savePoint)

# input:: {field: T ...}
proc objectVal(q: var Parser, isConst: bool, input: var Node) =
  expect tokLCurly
  input = newNode(nkInput)
  if currToken == tokRCurly:
    # input object value can have empty fields
    nextToken()
    return
  repeatUntil(q.conf.maxFields, tokRCurly):
    field := objectField(isConst)
    input <- field

# input:: $varname
proc variable*(q: var Parser, varName: var Node) =
  expect tokDollar
  expect tokName:
    if not q.validName(q.lex.name):
      return
    varName = newNode(nkVariable)
    varName.name = q.lex.name

# input values
proc valueLiteral*(q: var Parser, isConst: bool, val: var Node) =
  rgCheck(rgValueLiteral, q.conf.maxRecursionLimit)
  case currToken
  of tokLBracket:
    val ::= listVal(isConst)
    return
  of tokLCurly:
    val ::= objectVal(isConst)
    return
  of tokInt:
    val = newNode(nkInt)
    val.intVal = q.lex.token
    nextToken
    return
  of tokFloat:
    val = newNode(nkFloat)
    val.floatVal = q.lex.token
    nextToken
    return
  of tokString, tokBlockString:
    val = newNode(nkString)
    val.stringVal = q.lex.token
    nextToken
    return
  of tokDollar:
    if not isConst:
      val ::= variable
      return
    else:
      q.parserError(errUnexpectedToken, "literal instead of variable")
  of tokName:
    case currName
    of kwTrue:
      val = newNode(nkBoolean)
      val.boolVal = true
      nextToken
      return
    of kwFalse:
      val = newNode(nkBoolean)
      val.boolVal = false
      nextToken
      return
    of kwNull:
      val = newNode(nkNull)
      nextToken
      return
    else:
      val = newNode(nkEnum, q.lex.name)
      nextToken
      return
  else:
    q.parserError(errUnexpectedToken, "valid literal")

# (name: value ...)
proc arguments*(q: var Parser, isConst: bool, args: var Node) =
  if currToken == tokLParen:
    args = newNode(nkArguments)
  repeatOptional(q.conf.maxArguments, tokLParen, tokRParen):
    argName := name
    expect tokColon
    rgReset(rgValueLiteral)
    argVal := valueLiteral(isConst)
    args <- newTree(nkPair, argName, argVal)

# @dirname(arg: val ...)
proc directive(q: var Parser, isConst: bool, dir: var Node) =
  expect tokAt
  dirName := name
  args := arguments(isConst)
  dir = newTree(nkDirective, dirName, args)

proc directives*(q: var Parser, isConst: bool, dirs: var Node) =
  if currToken == tokAt:
    dirs = newNode(nkMembers)
  while currToken == tokAt:
    dir := directive(isConst)
    dirs <- dir

proc typeRef*(q: var Parser, resType: var Node) =
  rgCheck(rgTypeRef, q.conf.maxRecursionLimit)
  expectOptional tokLBracket:
    elem := typeRef
    resType = newTree(nkListType, elem)
    expect tokRBracket
  do:
    resType ::= namedType

  expectOptional tokBang:
    resType = newTree(nkNonNullType, resType)
