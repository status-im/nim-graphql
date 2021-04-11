# Table of contents

- [Overview](#overview)
  - [Graphql core](#graphql-core)
  - [Security features](#security-features)

- [Tutorials](tutorial.md)
  - [Important notes](tutorial.md#important-notes)
  - [Star wars tutorial](tutorial.md#star-wars-tutorial)

- [Resolver explained](resolver.md)
  - [How resolver works](resolver.md#how-resolver-works)
  - [Userdata](resolver.md#userdata)
  - [Resolver parameters](resolver.md#resolver-parameters)
  - [Response object](resolver.md#response-object)

- [Scalars](scalars.md)
  - [Builtin scalars](scalars.md#builtin-scalars)
  - [Custom scalars](scalars.md#custom-scalars)

- [Directives](directives.md)
  - [Builtin directives](directives.md#)
  - [Custom directives](directives.md#)

- [Introspection](introspection.md)
  - [Introspection API](introspection.md#introspection-api)
  - [Non-standard features](introspection.md#non-standard-features)

- [nim-graphql API](api.md)
  - [API index](api.md#api-index)
  - [Datatypes](api.md#datatypes)

- [Server](server.md)
  - [Server API index](server.md#server-api-index)
  - [Serving over HTTP](server.md#serving-over-http)

- [Client](client.md)
  - [Client API index](client.md#client-api-index)
  - [Request over HTTP](client.md#request-over-http)

## Overview

nim-graphql designed with simplicity in mind without compromising performance and
robustsness. Every part of nim-graphql can be tested and debugged relatively easy.
nim-graphql comes with comprehensive test suite touching every features as much as possible.
This gives us confidence when deploying a graphql service in performance critical and secure
application.

### Graphql core

The core of nim-graphql is built upon these components:

  - a performant `Name` or identifiers table.
  - an [almost] exception free lexer designed with security in mind.
  - Three kind of parsers to to help you build responsive graphql service:
    - `Schema parser`. This parser parse graphql type system document a.k.a schema.
    - `Query parser`. This parser only parse graphql query language and validating user input.
    - `Full parser`. This is a combination of `Schema parser` and `Query parser`.
  - A validator aiming at implementing all features described in the official specification.
  - An execution engine that can accept external datasources easily and exposing the interface
    using only plain Nim without hiding behind magical macros.
  - A complete but simple type system introspection described in the specification covering not only
    user defined types but also capable to query built in types using the same syntax, same output.

### Security features

Because nim-graphql lexer and parser are dealing with potentially malicious/malformed input that
can bring down the service, both lexer and parser are configurable to mitigate this problem.

  - Lexer config options:
    - `maxIdentChars`. Identifiers length must be within `maxIdentChars` or trigger an error. (default = 128)
    - `maxDigits`. nim-graphql support arbitrary number of digits for integer and float, but is limited by `maxDigits`. (default = 128)
    - `maxStringChars`. Single line string and multi line string length should not become too long. (default = 2048)

  - Parser config options:
    - `maxRecursionLimit`. Field selection recursion must be within this limit. (default = 25)
    - `maxListElems`. Arrays and lists maximum elements is limited by this option. (default = 128)
    - `maxFields`. Type fields, input object fields, and operation fields number should be within this limit. (default = 128)
    - `maxArguments`. Fields and directives usually don't require too much arguments. (default = 32)
    - `maxSchemaElems`. Graphql specification tells us it can only contains max 3 elems. (default = 3)
    - `maxEnumVals`. We have efficient identifers comparison, but should not too much enums. (default = 64)
    - `maxDefinitions`. Queries, mutations, subscriptions, and fragments total number should be reasonable. (default = 512)
    - `maxChoices`. Unions and directive's locations are limited by this number. (default = 64)

