# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  std/[os, tables],
  faststreams/inputs,
  stew/[results],
  ./common/[ast, types, names, ast_helper, response],
  ./builtin/[builtin, introspection],
  ./schema_parser, ./context, ./validator,
  ./executor

export
  validator, context, ast_helper, executor,
  response, results, types, names

const
  builtinSchema = staticRead("builtin" / "schema.ql")

proc registerBuiltinScalars(ctx: ContextRef)
proc loadBuiltinSchema(ctx: ContextRef)
proc registerInstrospection(ctx: ContextRef)

proc newContext*(): ContextRef =
  let empty = Node(kind: nkEmpty, pos: Pos())
  var ctx = ContextRef(
    names: newNameCache(),
    emptyNode: empty
  )
  ctx.registerBuiltinScalars()
  ctx.loadBuiltinSchema()
  ctx.registerInstrospection()
  result = ctx

proc customScalar*(ctx: ContextRef, nameStr: string, scalarProc: ScalarProc) =
  let name = ctx.names.insert(nameStr)
  ctx.scalarTable[name] = ScalarRef(
    parseLit: scalarProc
  )

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

proc registerBuiltinScalars(ctx: ContextRef) =
  for c in builtinScalars:
    ctx.customScalar(c[0], c[1])

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
  let name = ctx.names.insert("__Query")
  for n in doc.root:
    if n.sym.name == name:
      ctx.rootIntros = n
    n.sym.flags.incl sfBuiltin

proc registerResolvers*(ctx: ContextRef, ud: RootRef, typeName: Name, resolvers: openArray[(string, ResolverProc)]) =
  var res = ctx.resolver.getOrDefault(typeName)
  if res.isNil:
    res = ResolverSet(ud: ud)
    ctx.resolver[typeName] = res

  for v in resolvers:
    let field = ctx.names.insert(v[0])
    res.resolvers[field] = v[1]

proc registerResolvers*(ctx: ContextRef, ud: RootRef, typeName: string, resolvers: openArray[(string, ResolverProc)]) =
  let name = ctx.names.insert(typeName)
  ctx.registerResolvers(ud, name, resolvers)

proc registerInstrospection(ctx: ContextRef) =
  ctx.registerResolvers(ctx, "__Query", queryProtos)
  ctx.registerResolvers(ctx, "__Schema", schemaProtos)
  ctx.registerResolvers(ctx, "__Type", typeProtos)
  ctx.registerResolvers(ctx, "__Field", fieldProtos)
  ctx.registerResolvers(ctx, "__InputValue", inputValueProtos)
  ctx.registerResolvers(ctx, "__EnumValue", enumValueProtos)
  ctx.registerResolvers(ctx, "__Directive", directiveProtos)

proc createName*(ctx: ContextRef, name: string): Name =
  ctx.names.insert(name)
