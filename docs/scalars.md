## Scalars

```Nim
type
  NodeResult* = Result[Node, string]
  CoerceProc* = proc(ctx: Graphql, typeNode, node: Node): NodeResult
```

Unlike other graphql implementations, nim-graphql using a simpler approach to implement scalars.
You can refer to above types definition when writing your own custom scalars.

### Builtin scalars
  - `Int`. Accepts `nkInt` but validate with 32bit limit. Always return `nkInt`.
  - `Float`. Accepts `nkInt` or `nkFloat`, but always return it as `nkFloat`.
  - `String`. Accepts and return `nkString`.
  - `Boolean`. Accepts and return `nkBoolean`.
  - `ID`. Accepts `nkInt` and `nkString` but always return `nkString`. No limit check when accepting `nkInt`.

### Custom scalars
  Custom scalars main purpose is validating the user param input and validating scalar response object returned by resolver.
  Custom scalars can accepts and returns whatever response object needeed by the service, but the serialization is done by execution engine.
  For this reason, always keep in mind that final [response object](resolver.md#response-object) should contains only limited set of `Node` types.

```Nim
proc scalarMyScalar(ctx: GraphqlRef, typeNode, node: Node): NodeResult {.cdecl, gcsafe, nosideEffect.} =
  if node.kind == nkString:
    ok(node)
  else:
    err("expect string, but got '$1'" % [$node.kind])

proc scalarLong(ctx: GraphqlRef, typeNode, node: Node): NodeResult {.cdecl, gcsafe, nosideEffect.} =
  ## Long is a 64 bit unsigned integer.
  ## TODO: validate max-int 64 bit
  if node.kind == nkInt:
    # convert it into nkString node
    ok(Node(kind: nkString, stringVal: node.intVal, pos: node.pos))
  else:
    err("expect int, but got '$1'" % [$node.kind])

proc initMyApi(ctx: GraphqlRef) =
  ctx.customScalar("myScalar", scalarMyScalar)
  ctx.customScalar("Long", scalarLong)
```

### Variable coercion
  Variable coercion will use scalar proc to validate/convert the value.
  But sometimes the variables serialization format doesn't provide compatible type with
  scalar type. Common example is when a http graphql server receive variables in json format,
  there is no way to distinguish between string and enum.

  Then we need a type conversion from json string to enum node using custom coercion.

```graphql
enum Fruits {
  Banana
  Apple
  Orange
}
enum Vehicles {
  Car
  Motorcycle
  Bus
  Truck
}
scalar UUID
```

```Nim
proc coerceEnum(ctx: GraphqlRef, typeNode, node: Node): NodeResult {.cdecl, gcsafe, nosideEffect.} =
  if node.kind == nkString:
    ok(Node(kind: nkEnum, name: ctx.createName(node.stringVal), pos: node.pos))
  else:
    err("cannot coerce '$1' to $2" % [$node.kind, $typeNode])

proc coerceUUID(ctx: GraphqlRef, typeNode, node: Node): NodeResult {.cdecl, gcsafe, nosideEffect.} =
  if node.kind == nkString:
    ok(node)
  elif node.kind == nkInt:
    ok(Node(kind: nkString, stringVal: node.intVal, pos: node.pos))
  else:
    err("cannot coerce '$1' to $2" % [$node.kind, $typeNode])

proc initMyApi(ctx: GraphqlRef) =
  ctx.customCoercion("Fruits", coerceEnum)
  ctx.customCoercion("Vehicles", coerceEnum)
  ctx.customCoercion("UUID", coerceUUID)
```

  Custom coercion will be executed first, then the custom scalar or builtin scalar proc will be executed.
  When a custom scalar proc is not provided it will trigger error, but custom coercion is optional.
  If custom coercion proc is not provided for custom scalar or enum, it will be skipped and go to the scalar
  validation.

  Because after coercion there is still scalar/enum validation, usually coercion proc only do conversion and
  doesn't need to do complex validation.
