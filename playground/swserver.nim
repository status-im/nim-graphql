# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  std/[os, strutils], chronos, chronicles,
  ../graphql, ../graphql/httpserver,
  ./swapi, ./ethapi

type
  Schema = enum
    starwars
    ethereum

proc loadSchema(ctx: GraphqlRef, schema: Schema): GraphqlResult =
  notice "loading graphql api", name = schema

  var conf = defaultParserConf()
  conf.flags.incl pfCommentDescription

  if schema == ethereum:
    ctx.initEthApi()
    ctx.parseSchemaFromFile("tests" / "schemas" / "ethereum_1.0.ql", conf = conf)
  else:
    ctx.initStarWarsApi()
    ctx.parseSchemaFromFile("tests" / "schemas" / "star_wars_schema.ql", conf = conf)

const
  address = initTAddress("127.0.0.1:8547")

proc main() =
  let socketFlags = {ServerFlags.TcpNoDelay, ServerFlags.ReuseAddr}
  var ctx = GraphqlRef.new()

  let schema = if paramCount() == 0: starwars
               else: parseEnum[Schema](paramStr(1))

  let res = ctx.loadSchema(schema)
  if res.isErr:
    debugEcho res.error
    return

  let sres = GraphqlHttpServerRef.new(ctx, address, socketFlags = socketFlags)
  if sres.isErr():
    debugEcho sres.error
    return

  let server = sres.get()
  server.start()

  runForever()

main()
