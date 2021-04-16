## Scalars

```Nim
type
  NodeResult* = Result[Node, string]
  CoerceProc* = proc(ctx: Graphql, node: Node): NodeResult
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
