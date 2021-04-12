# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  std/[os, tables, sets],
  faststreams/inputs,
  stew/[results],
  ./common/[ast, types, names, ast_helper, response, errors],
  ./builtin/[builtin, introspection],
  ./lexer, ./common_parser, ./schema_parser, ./query_parser,
  ./graphql, ./validator, ./executor

export
  validator, graphql, ast_helper, executor,
  response, results, types, names, errors, ast

type
  ParseResult* = Result[void, ErrorDesc]

const
  builtinSchema = staticRead("builtin" / "schema.ql")

proc registerBuiltinScalars(ctx: GraphqlRef)
proc loadBuiltinSchema(ctx: GraphqlRef)
proc registerInstrospection(ctx: GraphqlRef)
proc introsNames(ctx: GraphqlRef)

proc init*(ctx: GraphqlRef) =
  ctx.names = newNameCache()
  ctx.emptyNode = Node(kind: nkEmpty, pos: Pos())
  ctx.introsNames()
  ctx.registerBuiltinScalars()
  ctx.loadBuiltinSchema()
  ctx.registerInstrospection()

proc new*(_: type GraphqlRef): GraphqlRef =
  var ctx = new(Graphql)
  ctx.init()
  ctx

proc customScalar*(ctx: GraphqlRef, nameStr: string, scalarProc: ScalarProc) =
  let name = ctx.names.insert(nameStr)
  ctx.scalarTable[name] = ScalarRef(
    parseLit: scalarProc
  )

proc customScalars*(ctx: GraphqlRef, procs: openArray[(string, ScalarProc)]) =
  for c in procs:
    ctx.customScalar(c[0], c[1])

proc addVar*(ctx: GraphqlRef, name: string, val: int) =
  let name = ctx.names.insert(name)
  let node = Node(kind: nkInt, intVal: $val, pos: Pos())
  ctx.varTable[name] = node

proc addVar*(ctx: GraphqlRef, name: string, val: string) =
  let name = ctx.names.insert(name)
  let node = Node(kind: nkString, stringVal: val, pos: Pos())
  ctx.varTable[name] = node

proc addVar*(ctx: GraphqlRef, name: string, val: float64) =
  let name = ctx.names.insert(name)
  let node = Node(kind: nkFloat, floatVal: $val, pos: Pos())
  ctx.varTable[name] = node

proc addVar*(ctx: GraphqlRef, name: string, val: bool) =
  let name = ctx.names.insert(name)
  let node = Node(kind: nkBoolean, boolVal: val, pos: Pos())
  ctx.varTable[name] = node

proc addVar*(ctx: GraphqlRef, name: string) =
  let name = ctx.names.insert(name)
  let node = Node(kind: nkNull, pos: Pos())
  ctx.varTable[name] = node

proc parseVariable(q: var Parser): Node =
  nextToken
  if currToken == tokEof:
    return
  q.valueLiteral(isConst = true, result)

template parseVariableImpl(name: string, value: untyped): untyped =
  var stream = unsafeMemoryInput(value)
  var parser = Parser.init(stream)
  let node = parser.parseVariable()
  if parser.error != errNone:
    return err(parser.err)
  let varname = ctx.names.insert(name)
  ctx.varTable[varname] = node
  ok()

proc parseVar*(ctx: GraphqlRef, name: string,
               value: string): ParseResult =
  parseVariableImpl(name, value)

proc parseVar*(ctx: GraphqlRef, name: string,
               value: openArray[byte]): ParseResult =
  parseVariableImpl(name, value)

proc addResolvers*(ctx: GraphqlRef, ud: RootRef,
     typeName: Name, resolvers: openArray[(string, ResolverProc)]) =
  var res = ctx.resolver.getOrDefault(typeName)
  if res.isNil:
    res = ResolverRef(ud: ud)
    ctx.resolver[typeName] = res

  for v in resolvers:
    let field = ctx.names.insert(v[0])
    res.resolvers[field] = v[1]

proc addResolvers*(ctx: GraphqlRef, ud: RootRef,
     typeName: string, resolvers: openArray[(string, ResolverProc)]) =
  let name = ctx.names.insert(typeName)
  ctx.addResolvers(ud, name, resolvers)

proc createName*(ctx: GraphqlRef, name: string): Name =
  ctx.names.insert(name)

template validation(ctx: GraphqlRef, parser: Parser,
                    stream: InputStream, doc: untyped): untyped =
  parser.parseDocument(doc)
  close stream
  if parser.error != errNone:
    return err(parser.err)
  ctx.validate(doc.root)
  if ctx.errKind != ErrNone:
    return err(ctx.err)
  ok()

template parseSchemaImpl(schema, conf: untyped): untyped =
  var stream = unsafeMemoryInput(schema)
  var parser = Parser.init(stream, ctx.names, conf)
  var doc: SchemaDocument
  ctx.validation(parser, stream, doc)

proc parseSchema*(ctx: GraphqlRef, schema: string, conf = defaultParserConf()): ParseResult =
  parseSchemaImpl(schema, conf)

proc parseSchema*(ctx: GraphqlRef, schema: openArray[byte], conf = defaultParserConf()): ParseResult =
  parseSchemaImpl(schema, conf)

proc parseSchemaFromFile*(ctx: GraphqlRef, fileName: string, conf = defaultParserConf()): ParseResult =
  var stream = memFileInput(fileName)
  var parser = Parser.init(stream, ctx.names, conf)
  var doc: SchemaDocument
  ctx.validation(parser, stream, doc)

template parseQueryImpl(schema, conf: untyped): untyped =
  var stream = unsafeMemoryInput(query)
  var parser = Parser.init(stream, ctx.names, conf)
  var doc: QueryDocument
  ctx.validation(parser, stream, doc)

proc parseQuery*(ctx: GraphqlRef, query: string, conf = defaultParserConf()): ParseResult =
  parseQueryImpl(query, conf)

proc parseQuery*(ctx: GraphqlRef, query: openArray[byte], conf = defaultParserConf()): ParseResult =
  parseQueryImpl(query, conf)

proc parseQueryFromFile*(ctx: GraphqlRef, fileName: string): ParseResult =
  var stream = memFileInput(fileName)
  var parser = Parser.init(stream, ctx.names)
  var doc: QueryDocument
  ctx.validation(parser, stream, doc)

proc purgeQueries*(ctx: GraphqlRef, includeVariables: bool) =
  ctx.opTable.clear()
  ctx.execTable.clear()
  if includeVariables:
    ctx.varTable.clear()
  ctx.errKind = ErrNone

proc purgeSchema*(ctx: GraphqlRef, includeScalars, includeResolvers: bool) =
  let size = max(max(ctx.typeTable.len, ctx.scalarTable.len), ctx.resolver.len)
  var names = newSeqOfCap[Name](size)
  var intros = initHashSet[Name]()
  for n in ctx.intros:
    intros.incl n

  for n in keys(ctx.typeTable):
    if n notin intros:
      names.add n

  for n in keys(ctx.scalarTable):
    if n notin intros:
      names.add n

  for n in keys(ctx.resolver):
    if n notin intros:
      names.add n

  ctx.rootQuery = nil
  ctx.rootMutation = nil
  ctx.rootSubs = nil

  for n in names:
    ctx.typeTable.del(n)

  if includeScalars:
    for n in names:
      ctx.scalarTable.del(n)

  if includeResolvers:
    for n in names:
      ctx.resolver.del(n)

  ctx.errKind = ErrNone

proc getNameCounter*(ctx: GraphqlRef): NameCounter =
  ctx.names.getCounter()

proc purgeNames*(ctx: GraphqlRef, savePoint: NameCounter) =
  ctx.names.purge(savePoint)

proc introsNames(ctx: GraphqlRef) =
  for n in IntrosTypes:
    ctx.intros[n] = ctx.names.insert($n)

proc registerBuiltinScalars(ctx: GraphqlRef) =
  ctx.customScalars(builtinScalars)

proc loadBuiltinSchema(ctx: GraphqlRef) =
  var stream = unsafeMemoryInput(builtinSchema)
  var parser = Parser.init(stream, ctx.names)

  # include this flags when validating
  # builtin schema
  parser.flags.incl pfAcceptReservedWords

  var doc: SchemaDocument
  parser.parseDocument(doc)

  if parser.error != errNone:
    debugEcho parser.err
    doAssert(parser.error == errNone)

  ctx.validate(doc.root)
  if ctx.errKind != ErrNone:
    debugEcho ctx.err
    doAssert(ctx.errKind == ErrNone)

  # instrospection root
  let name = ctx.intros[inQuery]
  for n in doc.root:
    if n.sym.name == name:
      ctx.rootIntros = n
    n.sym.flags.incl sfBuiltin

proc registerInstrospection(ctx: GraphqlRef) =
  ctx.addResolvers(ctx, "__Query", queryProtos)
  ctx.addResolvers(ctx, "__Schema", schemaProtos)
  ctx.addResolvers(ctx, "__Type", typeProtos)
  ctx.addResolvers(ctx, "__Field", fieldProtos)
  ctx.addResolvers(ctx, "__InputValue", inputValueProtos)
  ctx.addResolvers(ctx, "__EnumValue", enumValueProtos)
  ctx.addResolvers(ctx, "__Directive", directiveProtos)
