## Tutorial

This tutorial is for developers who want to know how to use nim-graphql and how to write
graphql service using nim-graphql. This tutorial doesn't talk about how the server or the client should be written.
That topic is covered in [server](server.md) section.

This tutorial covers about:
  - loading schema
  - implementing resolvers
  - parsing variables
  - executing queries

### Important notes

In nim-graphql, both queries and schemas share the same pool of `Name`s,
after loading and executing a query, we usually discard the recent query and
keep schemas intact.

Every time we load/execute a new query, there is possibility it create new `Name`s
that is not needed by the system. To remove this unused `Name`, we will call `purgeNames(counter)`.
`purgeNames` will remove all `Name`s with id greater than the counter parameter.

This is a simplified example using Nim-like syntax to describe how to use `purgeNames`

```Nim
  var server = setupServer()
  let ctx = GraphqlRef.new()
  ctx.parseSchemaFromFile("myschema.ql")
  let counter = ctx.getNameCounter()

  loop:
    let query = server.recvQuery()

    # one or more queries can be executed
    ctx.parseQuery(query)
    let resp = JsonRespStream.new()
    ctx.executeRequest(resp, "operationName")
    server.sendResponse(resp)

    ctx.purgeQueries() # remove recent queries
    ctx.purgeNames(counter) # remove all names associated with recent queries
```

The server can decide how much queries executed before calling `purgeNames`.

### Star Wars tutorial
