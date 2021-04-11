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
  ./context, ./validator, ./executor

export
  validator, context, ast_helper, executor,
  response, results, types, names, errors, ast

type
  ParseResult* = Result[void, ErrorDesc]

const
  builtinSchema = staticRead("builtin" / "schema.ql")

proc registerBuiltinScalars(ctx: ContextRef)
proc loadBuiltinSchema(ctx: ContextRef)
proc registerInstrospection(ctx: ContextRef)
proc introsNames(ctx: ContextRef)

proc newContext*(): ContextRef =
  let empty = Node(kind: nkEmpty, pos: Pos())
  var ctx = ContextRef(
    names: newNameCache(),
    emptyNode: empty
  )
  ctx.introsNames()
  ctx.registerBuiltinScalars()
  ctx.loadBuiltinSchema()
  ctx.registerInstrospection()
  result = ctx

proc customScalar*(ctx: ContextRef, nameStr: string, scalarProc: ScalarProc) =
  let name = ctx.names.insert(nameStr)
  ctx.scalarTable[name] = ScalarRef(
    parseLit: scalarProc
  )

proc customScalars*(ctx: ContextRef, procs: openArray[(string, ScalarProc)]) =
  for c in procs:
    ctx.customScalar(c[0], c[1])

proc addVar*(ctx: ContextRef, name: string, val: int) =
  let name = ctx.names.insert(name)
  let node = Node(kind: nkInt, intVal: $val, pos: Pos())
  ctx.varTable[name] = node

proc addVar*(ctx: ContextRef, name: string, val: string) =
  let name = ctx.names.insert(name)
  let node = Node(kind: nkString, stringVal: val, pos: Pos())
  ctx.varTable[name] = node

proc addVar*(ctx: ContextRef, name: string, val: float64) =
  let name = ctx.names.insert(name)
  let node = Node(kind: nkFloat, floatVal: $val, pos: Pos())
  ctx.varTable[name] = node

proc addVar*(ctx: ContextRef, name: string, val: bool) =
  let name = ctx.names.insert(name)
  let node = Node(kind: nkBoolean, boolVal: val, pos: Pos())
  ctx.varTable[name] = node

proc addVar*(ctx: ContextRef, name: string) =
  let name = ctx.names.insert(name)
  let node = Node(kind: nkNull, pos: Pos())
  ctx.varTable[name] = node

proc parseVariable(q: var Parser): Node =
  nextToken
  if currToken == tokEof:
    return
  q.valueLiteral(isConst = true, result)

proc parseVar*(ctx: ContextRef, name: string,
               value: string): ParseResult =
  var stream = unsafeMemoryInput(value)
  var parser = Parser.init(stream)
  let node = parser.parseVariable()
  if parser.error != errNone:
    return err(parser.errDesc())
  let name = ctx.names.insert(name)
  ctx.varTable[name] = node
  ok()

proc addResolvers*(ctx: ContextRef, ud: RootRef,
     typeName: Name, resolvers: openArray[(string, ResolverProc)]) =
  var res = ctx.resolver.getOrDefault(typeName)
  if res.isNil:
    res = ResolverSet(ud: ud)
    ctx.resolver[typeName] = res

  for v in resolvers:
    let field = ctx.names.insert(v[0])
    res.resolvers[field] = v[1]

proc addResolvers*(ctx: ContextRef, ud: RootRef,
     typeName: string, resolvers: openArray[(string, ResolverProc)]) =
  let name = ctx.names.insert(typeName)
  ctx.addResolvers(ud, name, resolvers)

proc createName*(ctx: ContextRef, name: string): Name =
  ctx.names.insert(name)

template validation(ctx: ContextRef, parser: Parser,
                    stream: InputStream, doc: untyped): untyped =
  parser.parseDocument(doc)
  close stream
  if parser.error != errNone:
    return err(parser.errDesc())
  ctx.validate(doc.root)
  if ctx.errKind != ErrNone:
    return err(ctx.err)
  ok()

proc parseSchema*(ctx: ContextRef, schema: string): ParseResult =
  var stream = unsafeMemoryInput(schema)
  var parser = Parser.init(stream, ctx.names)
  var doc: SchemaDocument
  ctx.validation(parser, stream, doc)

proc parseSchemaFromFile*(ctx: ContextRef, fileName: string): ParseResult =
  var stream = memFileInput(fileName)
  var parser = Parser.init(stream, ctx.names)
  var doc: SchemaDocument
  ctx.validation(parser, stream, doc)

proc parseQuery*(ctx: ContextRef, query: string): ParseResult =
  var stream = unsafeMemoryInput(query)
  var parser = Parser.init(stream, ctx.names)
  var doc: QueryDocument
  ctx.validation(parser, stream, doc)

proc parseQueryFromFile*(ctx: ContextRef, fileName: string): ParseResult =
  var stream = memFileInput(fileName)
  var parser = Parser.init(stream, ctx.names)
  var doc: QueryDocument
  ctx.validation(parser, stream, doc)

proc purgeQueries*(ctx: ContextRef, includeVariables: bool) =
  ctx.opTable.clear()
  ctx.execTable.clear()
  if includeVariables:
    ctx.varTable.clear()
  ctx.errKind = ErrNone

proc purgeSchema*(ctx: ContextRef, includeScalars, includeResolvers: bool) =
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

proc getNameCounter*(ctx: ContextRef): NameCounter =
  ctx.names.getCounter()

proc purgeNames*(ctx: ContextRef, savePoint: NameCounter) =
  ctx.names.purge(savePoint)

proc introsNames(ctx: ContextRef) =
  for n in IntrosTypes:
    ctx.intros[n] = ctx.names.insert($n)

proc registerBuiltinScalars(ctx: ContextRef) =
  ctx.customScalars(builtinScalars)

proc loadBuiltinSchema(ctx: ContextRef) =
  var stream = unsafeMemoryInput(builtinSchema)
  var parser = Parser.init(stream, ctx.names)

  # include this flags when validating
  # builtin schema
  parser.flags.incl pfAcceptReservedWords

  var doc: SchemaDocument
  parser.parseDocument(doc)

  if parser.error != errNone:
    debugEcho parser.errDesc
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

proc registerInstrospection(ctx: ContextRef) =
  ctx.addResolvers(ctx, "__Query", queryProtos)
  ctx.addResolvers(ctx, "__Schema", schemaProtos)
  ctx.addResolvers(ctx, "__Type", typeProtos)
  ctx.addResolvers(ctx, "__Field", fieldProtos)
  ctx.addResolvers(ctx, "__InputValue", inputValueProtos)
  ctx.addResolvers(ctx, "__EnumValue", enumValueProtos)
  ctx.addResolvers(ctx, "__Directive", directiveProtos)
