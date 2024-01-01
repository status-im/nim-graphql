# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  std/[tables, sets],
  faststreams/inputs,
  stew/[results],
  ./common/[ast, types, names, ast_helper, response, errors],
  ./builtin/[builtin, introspection],
  ./lexer, ./common_parser, ./schema_parser, ./query_parser,
  ./graphql, ./validator, ./executor

export
  validator, graphql, ast_helper, executor,
  response, results, types, names, errors, ast

const
  builtinSchema = staticRead("builtin/schema.ql")

{.push gcsafe, raises: [].}

proc registerBuiltinScalars(ctx: GraphqlRef)
proc loadBuiltinSchema(ctx: GraphqlRef)
proc registerInstrospection(ctx: GraphqlRef)

proc init*(ctx: GraphqlRef) =
  ctx.names = newNameCache()
  ctx.emptyNode = Node(kind: nkEmpty, pos: Pos())
  ctx.registerBuiltinScalars()
  ctx.loadBuiltinSchema()
  ctx.registerInstrospection()

proc new*(_: type GraphqlRef): GraphqlRef =
  var ctx = new(Graphql)
  ctx.init()
  ctx

proc customScalar*(ctx: GraphqlRef, nameStr: string, scalarProc: CoercionProc) =
  let name = ctx.names.insert(nameStr)
  ctx.scalarTable[name] = scalarProc

proc customScalar*(ctx: GraphqlRef,
                    procs: openArray[tuple[name: string, scalarProc: CoercionProc]]) =
  for c in procs:
    ctx.customScalar(c.name, c.scalarProc)

proc customCoercion*(ctx: GraphqlRef, nameStr: string, coerceProc: CoercionProc) =
  let name = ctx.names.insert(nameStr)
  ctx.coerceTable[name] = coerceProc

proc customCoercion*(ctx: GraphqlRef,
                    procs: openArray[tuple[name: string, coerceProc: CoercionProc]]) =
  for c in procs:
    ctx.customCoercion(c.name, c.coerceProc)

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

proc parseVariable(q: var Parser): Node {.gcsafe, raises: [IOError].} =
  nextToken
  if currToken == tokEof:
    return
  rgReset(rgValueLiteral) # recursion guard
  q.valueLiteral(isConst = true, result)

proc parseVariable(ctx: GraphqlRef, name: string, input: InputStream): GraphqlResult =
  try:
    var parser = Parser.init(input, ctx.names)
    let node = parser.parseVariable()
    if parser.error != errNone:
      return err(@[parser.err])
    let varname = ctx.names.insert(name)
    ctx.varTable[varname] = node
    ok()
  except IOError as exc:
    err(@[errorError(exc.msg)])

proc parseVar*(ctx: GraphqlRef, name: string,
               value: string): GraphqlResult {.gcsafe.} =
  {.gcsafe.}:
    var stream = unsafeMemoryInput(value)
    ctx.parseVariable(name, stream)

proc parseVar*(ctx: GraphqlRef, name: string,
               value: openArray[byte]): GraphqlResult {.gcsafe.} =
  {.gcsafe.}:
    var stream = unsafeMemoryInput(value)
    ctx.parseVariable(name, stream)

proc parseVars(ctx: GraphqlRef, input: InputStream): GraphqlResult {.gcsafe, raises: [].} =
  try:
    var parser = Parser.init(input, ctx.names)
    parser.lex.next()
    if parser.lex.tok == tokEof:
      return ok()

    var values: Node
    parser.rgReset(rgValueLiteral) # recursion guard
    parser.valueLiteral(isConst = true, values)
    if parser.error != errNone:
      return err(@[parser.err])

    for n in values:
      ctx.varTable[n[0].name] = n[1]
    ok()
  except IOError as exc:
    err(@[errorError(exc.msg)])

proc parseVars*(ctx: GraphqlRef, input: string): GraphqlResult {.gcsafe, raises: [].} =
  {.gcsafe.}:
    var stream = unsafeMemoryInput(input)
    ctx.parseVars(stream)

proc parseVars*(ctx: GraphqlRef, input: openArray[byte]): GraphqlResult {.gcsafe, raises: [].} =
  {.gcsafe.}:
    var stream = unsafeMemoryInput(input)
    ctx.parseVars(stream)

proc addResolvers*(ctx: GraphqlRef, ud: RootRef, typeName: Name,
                   resolvers: openArray[tuple[name: string, resolver: ResolverProc]]) =
  var res = ctx.resolver.getOrDefault(typeName)
  if res.isNil:
    res = ResolverRef(ud: ud)
    ctx.resolver[typeName] = res

  for v in resolvers:
    let field = ctx.names.insert(v.name)
    res.resolvers[field] = v.resolver

proc addResolvers*(ctx: GraphqlRef, ud: RootRef, typeName: string,
                   resolvers: openArray[tuple[name: string, resolver: ResolverProc]]) =
  let name = ctx.names.insert(typeName)
  ctx.addResolvers(ud, name, resolvers)

proc createName*(ctx: GraphqlRef, name: string): Name =
  ctx.names.insert(name)

proc markAsStored(ctx: GraphqlRef, root: Node) =
  for n in root:
    if n.kind != nkSym:
      continue

    n.sym.flags.incl sfBuiltin

    # piggy back the rootIntros here :)
    if toKeyword(n.sym.name) == introsRoot:
      ctx.rootIntros = n

template validation(ctx: GraphqlRef, parser: Parser,
                    stream: InputStream, doc, store: untyped): untyped =
  try:
    parser.parseDocument(doc)
    close stream
    if parser.error != errNone:
      return err(@[parser.err])
    ctx.validate(doc.root)
    if store:
      ctx.markAsStored(doc.root)
    if ctx.errKind != ErrNone:
      return err(ctx.errors)
    ok()
  except IOError as exc:
    err(@[errorError(exc.msg)])

template parseSchemaImpl(schema, store, conf: untyped): untyped =
  var stream = unsafeMemoryInput(schema)
  var parser = Parser.init(stream, ctx.names, conf)
  var doc: SchemaDocument
  ctx.validation(parser, stream, doc, store)

proc parseSchema*(ctx: GraphqlRef, schema: string, store = false,
                  conf = defaultParserConf()): GraphqlResult {.gcsafe, raises: [].} =
  {.gcsafe.}:
    parseSchemaImpl(schema, store, conf)

proc parseSchema*(ctx: GraphqlRef, schema: openArray[byte], store = false,
                  conf = defaultParserConf()): GraphqlResult {.gcsafe, raises: [].} =
  {.gcsafe.}:
    parseSchemaImpl(schema, store, conf)

proc parseSchemaFromFile*(ctx: GraphqlRef, fileName: string, store = false,
                          conf = defaultParserConf()): GraphqlResult {.gcsafe, raises: [].} =
  {.gcsafe.}:
    try:
      var stream = memFileInput(fileName)
      var parser = Parser.init(stream, ctx.names, conf)
      var doc: SchemaDocument
      ctx.validation(parser, stream, doc, store)
    except CatchableError as e:
      err(@[fatalError("parseSchemaFromFile: " & e.msg)])

proc parseSchema(ctx: GraphqlRef, stream: InputStream,
                 root: var Node, conf: ParserConf): GraphqlResult {.gcsafe, raises: [].} =
  try:
    var parser = Parser.init(stream, ctx.names, conf)
    var doc: SchemaDocument
    parser.parseDocument(doc)
    close stream
    if parser.error != errNone:
      return err(@[parser.err])
    if root.isNil: root = doc.root
    else: root.sons.add doc.root.sons
    ok()
  except IOError as exc:
    err(@[errorError(exc.msg)])

proc parseSchemas*[T: string | seq[byte]](ctx: GraphqlRef,
                  files: openArray[string],
                  schemas: openArray[T], store = false,
                  conf = defaultParserConf()): GraphqlResult {.gcsafe, raises: [].} =
  {.gcsafe.}:
    var root: Node
    try:
      for fileName in files:
        let stream = memFileInput(fileName)
        let res = ctx.parseSchema(stream, root, conf)
        if res.isErr:
          return res
    except CatchableError as e:
      return err(@[fatalError("parseSchemas: " & e.msg)])

    for schema in schemas:
      let stream = unsafeMemoryInput(schema)
      let res = ctx.parseSchema(stream, root, conf)
      if res.isErr:
        return res

    ctx.validate(root)
    if store:
      ctx.markAsStored(root)
    if ctx.errKind != ErrNone:
      return err(ctx.errors)
    ok()

template parseQueryImpl(schema, store, conf: untyped): untyped =
  var stream = unsafeMemoryInput(query)
  var parser = Parser.init(stream, ctx.names, conf)
  var doc: QueryDocument
  ctx.validation(parser, stream, doc, store)

proc parseQuery*(ctx: GraphqlRef, query: string, store = false,
                 conf = defaultParserConf()): GraphqlResult {.gcsafe, raises: [].} =
  {.gcsafe.}:
    parseQueryImpl(query, store, conf)

proc parseQuery*(ctx: GraphqlRef, query: openArray[byte], store = false,
                 conf = defaultParserConf()): GraphqlResult {.gcsafe, raises: [].} =
  {.gcsafe.}:
    parseQueryImpl(query, store, conf)

proc parseQueryFromFile*(ctx: GraphqlRef, fileName: string, store = false,
                         conf = defaultParserConf()): GraphqlResult {.gcsafe, raises: [].} =
  {.gcsafe.}:
    try:
      var stream = memFileInput(fileName)
      var parser = Parser.init(stream, ctx.names, conf)
      var doc: QueryDocument
      ctx.validation(parser, stream, doc, store)
    except CatchableError as e:
      err(@[fatalError("parseQueryFromFile: " & e.msg)])

proc purgeQueries*(ctx: GraphqlRef, includeVariables = true, includeStored = false) =
  if includeStored:
    ctx.opTable.clear()
  else:
    var names = newSeqOfCap[Name](ctx.opTable.len)
    for n, v in ctx.opTable:
      if sfBuiltin notin v.sym.flags:
        names.add n
    for n in names:
      ctx.opTable.del(n)

  if includeVariables:
    ctx.varTable.clear()

proc purgeSchema*(ctx: GraphqlRef, includeScalars = true,
                  includeResolvers = true, includeCoercion = true) =
  var names = newSeqOfCap[Name](ctx.typeTable.len)
  for n, v in ctx.typeTable:
    if sfBuiltin notin v.sym.flags:
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

  if includeCoercion:
    for n in names:
      ctx.coerceTable.del(n)

proc getNameCounter*(ctx: GraphqlRef): NameCounter =
  ctx.names.getCounter()

proc purgeNames*(ctx: GraphqlRef, savePoint: NameCounter) =
  ctx.names.purge(savePoint)

proc addInstrument*(ctx: GraphqlRef, instr: InstrumentRef) =
  ctx.instruments.add instr

proc registerBuiltinScalars(ctx: GraphqlRef) =
  ctx.customScalar(builtinScalars)

proc loadBuiltinSchema(ctx: GraphqlRef) =
  var conf = defaultParserConf()

  # include this flags when validating
  # builtin schema
  conf.flags.incl pfAcceptReservedWords
  let res = ctx.parseSchema(builtinSchema, store = true, conf)
  if res.isErr:
    debugEcho res.error
  assert(res.isOk)

proc registerInstrospection(ctx: GraphqlRef) =
  ctx.addResolvers(ctx, "__Query", queryProtos)
  ctx.addResolvers(ctx, "__Schema", schemaProtos)
  ctx.addResolvers(ctx, "__Type", typeProtos)
  ctx.addResolvers(ctx, "__Field", fieldProtos)
  ctx.addResolvers(ctx, "__InputValue", inputValueProtos)
  ctx.addResolvers(ctx, "__EnumValue", enumValueProtos)
  ctx.addResolvers(ctx, "__Directive", directiveProtos)

{.pop.}
