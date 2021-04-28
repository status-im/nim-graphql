nim-graphql
=================

<img alt="GraphQL Logo" align="right" src="resources/GraphQL%20Logo.svg" width="15%" />

[![License: Apache](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
![Github action](https://github.com/status-im/nim-graphql/workflows/nim-graphql%20CI/badge.svg)

## Introduction

Enjoy writing graphql service in plain Nim!.
You decide when to use more syntactic sugars offered by Nim templates.
And you can choose whether you want to use macros or not, we don't impose them to you.

Designed from ground up to be easily tested part by part,
you can quickly implement your service while writing a comprehensive test suite for it.

You can choose which transport mechanism to deliver your service.
Over http or secure-http, websocket or secure-websocket, ipc or rpc, rawsocket,
and OS stdin/stdout. Not all of these mechanisms provided by nim-graphql,
but the freedom is there.

## Documentation

If you are interested in contributing to nim-graphql development, the official
specification is [here](https://spec.graphql.org/June2018/).

If you want to know how to use nim-graphql or how nim-graphql works,
the documentation is available [here](docs/toc.md).

## Playground

You can play with our playground graphql http server using graphql
client such as [Altair GraphQL client](https://altair.sirmuel.design)
or using builtin [graphiql](https://github.com/graphql/graphiql) user interface.

- Using Starwars schema/api.
```bash
$ nimble starwars

or

$ nim c -r playground/swserver starwars
```

- Using Ethereum schema/api.
```bash
$ nimble ethereum

or

$ nim c -r playground/swserver ethereum
```

The server is accessible at this address `http://127.0.0.1:8547/graphql`
and the web user interface at `http://127.0.0.1:8547/graphql/ui`.

## Installation

You can use Nim's official package manager Nimble to install nim-graphql:

```
$ nimble install https://github.com/status-im/nim-graphql.git
```

or

```
$ nimble install graphql
```

## Contributing

When submitting pull requests, please add test cases for any new features
or fixes and make sure `nimble test` is still able to execute the entire
test suite successfully.

## License

Licensed and distributed under either of

* MIT license: [LICENSE-MIT](LICENSE-MIT) or http://opensource.org/licenses/MIT

or

* Apache License, Version 2.0, ([LICENSE-APACHEv2](LICENSE-APACHEv2) or http://www.apache.org/licenses/LICENSE-2.0)

at your option. These files may not be copied, modified, or distributed except according to those terms.
