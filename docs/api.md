## nim-graphql API

Please see [tutorial](tutorial.md) or other parts of this documentation to understand how to use this API.

### API index

If you find anything not listed or not exported in this list, please submit an issue.

#### nim-stew/results API
  - `isErr`. Caller will know if the callee is failed.
  - `isOk`. Caller will check if the callee is success.
  - `err`. Signal error condition to caller.
  - `ok`. Wrap the result object and return it to caller.
  - `error`. If `isError` is true, use `error` to retrieve the error message or error object.
  - `get`. If `isOk` is true, use `get` to retrieve the wrapped object.

#### Graphql API
  - `newContext(): ContextRef`. Create a new validation/execution context.
  - `customScalar(ctx: ContextRef, nameStr: string, scalarProc: ScalarProc)`. Add more custom scalar proc to the system.
  - `customScalars(ctx: ContextRef, procs: [(string, ScalarProc)])`. Add a list of custom scalars to the system.
  - `addVar`. Add new variable to the system.
    - `addVar(ctx: ContextRef, name: string, val: int)`
    - `addVar(ctx: ContextRef, name: string, val: string)`
    - `addVar(ctx: ContextRef, name: string, val: float64)`
    - `addVar(ctx: ContextRef, name: string, val: bool)`
    - `addVar(ctx: ContextRef, name: string)`. Add a `null` variable.

  - `parseVar(ctx: ContextRef, name: string, value: string): ParseResult`. Add new variable to the system by parsing a text string.
  - `addResolvers(ctx: ContextRef, ud: RootRef, typeName: Name, resolvers: openArray[(string, ResolverProc)])`. Add a list of resolvers to the system.
    - `addResolvers(ctx: ContextRef, ud: RootRef, typeName: string, resolvers: openArray[(string, ResolverProc)])`
  - `createName(ctx: ContextRef, name: string): Name`. `respMap` will need a name from the system using this proc.
  - `executeRequest`. This is your main entrance to the execution engine.
  - `validate`. Usually you don't need to call this directly.
  - `parseSchema(ctx: ContextRef, schema: string): ParseResult`. Parse a scheme from text string.
  - `parseSchemaFromFile(ctx: ContextRef, fileName: string): ParseResult`.
  - `parseQuery(ctx: ContextRef, query: string): ParseResult `. Parse queries from text string.
  - `parseQueryFromFile(ctx: ContextRef, fileName: string): ParseResult`.
  - `purgeQueries(ctx: ContextRef, includeVariables: bool)`. A server will often call this to remove unused queries.
  - `purgeSchema(ctx: ContextRef, includeScalars, includeResolvers: bool)`. Probably not need to call this often.
  - `getNameCounter(ctx: ContextRef): NameCounter`. Use this proc to create a savepoint for `purgeNames`.
  - `purgeNames(ctx: ContextRef, savePoint: NameCounter)`. You need to call this after you call `purgeQueries` or `purgeSchema`.
  - `treeRepr(n: Node): string`. Pretty print `Node`.

#### Graphql response API
  - `respMap(name: Name): Node`. Create a names map.
  - `respList(): Node`. Create a list object.
  - `respNull(): Node`. Create a null literal.
  - `resp(): Node`. Create an empty node.
  - `resp`. Response object constructors.
    - `resp(x: string): Node`
    - `resp(x: int): Node`
    - `resp(x: bool): Node`
    - `resp(x: float64): Node`

#### Builtin JSON response stream API
  - `newJsonRespStream(doubleEscape = false): RespStream`. Create a new JSON response stream object.
    When `doubleEscape` is true, the `getOutput` will return a text string that can be embedded in a json string.
  - `getOutput(): string`. Get a string output from response stream.

#### Datatypes
  - `ErrorDesc`.
  - `ErrorLevel`.
  - `Name`.
  - `Result`.
  - `ContextRef`.
  - `ScalarResult`.
  - `RespResult`.
  - `ParseResult`.
  - `ContextError`.
  - `NameCounter`.
  - `Node`.
