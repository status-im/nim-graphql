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
  - `newContext(): GraphqlRef`. Create a new validation/execution context.
  - `customScalar(ctx: GraphqlRef, nameStr: string, scalarProc: CoerceProc)`. Add more custom scalar proc to the system.
  - `customScalar(ctx: GraphqlRef, procs: [(string, CoerceProc)])`. Add a list of custom scalar procs to the system.
  - `customCoercion(ctx: GraphqlRef, nameStr: string, scalarProc: CoerceProc)`. Add more custom coercion proc to the system.
  - `customCoercion(ctx: GraphqlRef, procs: [(string, CoerceProc)])`. Add a list of custom coercion procs to the system.
  - `addVar`. Add new variable to the system.
    - `addVar(ctx: GraphqlRef, name: string, val: int)`
    - `addVar(ctx: GraphqlRef, name: string, val: string)`
    - `addVar(ctx: GraphqlRef, name: string, val: float64)`
    - `addVar(ctx: GraphqlRef, name: string, val: bool)`
    - `addVar(ctx: GraphqlRef, name: string)`. Add a `null` variable.

  - `parseVar(ctx: GraphqlRef, name: string, value: string | openArray[byte]): ParseResult`. Add new variable to the system by parsing a text string.
  - `parseVars(ctx: GraphqlRef, value: string | openArray[byte]): ParseResult`.
     Add new variables to the system by parsing map. Top level keys will become variables name.
  - `addResolvers(ctx: GraphqlRef, ud: RootRef, typeName: Name, resolvers: openArray[(string, ResolverProc)])`. Add a list of resolvers to the system.
    - `addResolvers(ctx: GraphqlRef, ud: RootRef, typeName: string, resolvers: openArray[(string, ResolverProc)])`
  - `createName(ctx: GraphqlRef, name: string): Name`. `respMap` will need a name from the system using this proc.
  - `executeRequest(ctx: GraphqlRef, resp: RespStream, opName = ""): ParseResult`. This is your main entrance to the execution engine.
  - `validate(ctx: GraphqlRef, root: Node)`. Usually you don't need to call this directly.
  - `parseSchema(ctx: GraphqlRef, schema: string | openArray[byte]): ParseResult`. Parse a scheme from text string.
  - `parseSchemaFromFile(ctx: GraphqlRef, fileName: string): ParseResult`.
  - `parseSchemas[T: string | seq[byte]](ctx: GraphqlRef, files: openArray[string], schemas: openArray[T], conf = defaultParserConf()): GraphqlResult`.
    Parses multiple files and multiple string/seq[byte] schema definitions at once.
  - `parseQuery(ctx: GraphqlRef, query: string | openArray[byte]): ParseResult `. Parse queries from text string.
  - `parseQueryFromFile(ctx: GraphqlRef, fileName: string): ParseResult`.
  - `purgeQueries(ctx: GraphqlRef, includeVariables: bool)`. A server will often call this to remove unused queries.
  - `purgeSchema(ctx: GraphqlRef, includeScalars, includeResolvers: bool)`. Probably not need to call this often.
  - `getNameCounter(ctx: GraphqlRef): NameCounter`. Use this proc to create a savepoint for `purgeNames`.
  - `purgeNames(ctx: GraphqlRef, savePoint: NameCounter)`. You need to call this after you call `purgeQueries` or `purgeSchema`.
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
  - `new(_: type JsonRespStream, doubleEscape = false): RespStream`. Create a new JSON response stream object.
    When `doubleEscape` is true, the `getOutput` will return a text string that can be embedded in a json string.
  - `getString(): string`. Get a string output from response stream.
  - `getBytes(): seq[byte]`. Get a bytes output from response stream.
  - `JsonRespStream`. The JSON stream type

#### Datatypes
  - `ErrorDesc`.
  - `ErrorLevel`.
  - `Name`.
  - `Result`.
  - `GraphqlRef`.
  - `NodeResult`.
  - `RespResult`.
  - `GraphqlResult`.
  - `GraphqlError`.
  - `NameCounter`.
  - `Node`.
