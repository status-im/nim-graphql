## Resolver explained

```Nim
{.pragma: apiPragma, cdecl, gcsafe, raises: [Defect, CatchableError].}
proc resolverProc(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  discard
```

This is an example of nim-graphql resolver proc. One field in a type is associated with one resolver proc.
A resolver will read from external datasource and transform it into [`response object`](#response-object).

- `ud`. This object is shared across all resolvers that execute for a particular operation.
  Use this to share per-operation state, such as authentication information and access to data sources.
- `params`. This object contains all GraphQL arguments provided for this field.
- `parent`. This is the return value of the resolver for this field's parent.
  The resolver for a parent field always executes before the resolvers for that field's children.

### How resolver works

Unions, interfaces, scalars, lists, and non-nulls returned by a resolver are checked against the schema.
And this returned object is passed to inner resolver as `parent` parameter.
Only `Object` type not validated by the execution engine because it will be validated by the inner resolvers.

- Unions and interfaces can be one of `{nkString, nkName, nkNamedType, nkMap}`.
  `respMap` is the common choice to construct an object.
- When constructing a list, the inner type should match the inner resolver return type.
  `respList` will help you construct a list object.
- Scalars usually can accept more than one compatible types. The validation is in the scalar implementation.
- Although the final response of an `Object` is a map, but when constructing an object within a resolver,
  you don't need to create an actual map. The execution engine will do this.
  You can just return an id or a name of the object. Then the inner resolvers will use this id or name to resolve the object fields.
  But because introspection `__typename` and the possibility of using them with union and interface,
  better to construct object as one of `{nkString, nkName, nkNamedType, nkMap}`.


### Userdata

User data is an object where you provide external data source to a set of resolvers.

```graphql
type Person {
  name: String!
  address: String
  age: Int
}

type Cat {
  color: Colors # an enum
  age: Int
}
```

In this example, there is `Person` and `Cat` types. Both can use the same data source or different data source.

```Nim
proc personName(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  discard

proc personAddress(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  discard

proc personAge(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  discard

const personProcs = {
  "name": personName,
  "address": personAddress,
  "age": personAge,
}

proc catColor(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  discard

proc catAge(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  discard

const catProcs = {
  "color": catColor,
  "age": catAge
}

# both person can cat using the same data source
# but you can use different data source.
var ud = creataUserData()
ctx.addResolvers(ud, "Person", personProcs)
ctx.addResolvers(ud, "Cat", catProcs)
```

### Resolver parameters

Resolver parameters is a list of name and value pairs. But it is not a map.
The order of this name-value pairs always the same with arguments definition in the schema.
The number of argument always same with arguments number in the schema although the are omitted optional parameter.

`Null` and `empty` are not equals. `Null` means the value is null literal, while `empty` means no value.

```graphql
type Query {
  cat(color: Color, age: Int, sex: Sex): Cat
}

query {
  # you give different order, and missing optional param
  cat(age: 3, sex: Male) # the resolver will receive [color:empty, age:3, sex:Male]
}

query {
  # you give null param
  cat(color: null, age: 3) # the resolver will receive [color:null, age:3, sex:empty]
}
```

If there is a doubt about what kind of parameters are passed by the execution engine to the resolvers,
you can always use `treeRepr` function to pretty print the `params` nodes.

```Nim
debugEcho Node(params).treeRepr
```

If one or more of your parameter is an input object, it will undergo similar transformation like parameters list.
Any missing field will be filled and the order will become exactly like the input object definition in the schema.

### Response object

Response object share the same `Node` object used by internal AST,
but only a subset of Node types are allowed to appear in final response object.

Allowed subset of Node types are: `nkNull`, `nkBoolean`, `nkInt`, `nkFloat`, `nkString`, `nkList`, and `nkMap`.
Other types of Node will trigger error. For this reason, we already provided a set of helpers to construct
response object below instead of using AST node constructor.

```Nim
proc respMap*(name: Name): Node
proc respList*(): Node
proc respNull*(): Node
proc resp*(): Node   # will produce empty node
proc resp*(x: string): Node
proc resp*(x: int): Node
proc resp*(x: bool): Node
proc resp*(x: float64): Node
```

A resolver return data type is defined as:

```Nim
type
  RespResult* = Result[Node, string]
```

Therefore you cannot return response object directly but must wrap it using `ok` or `err`.

```Nim
# ok condition
var list = respList()
return ok(list)

# error condition
return err("cannot find cat with age: '$1'" % [catAge])
```
