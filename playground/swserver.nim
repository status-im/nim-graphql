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
  ./swapi, ./ethapi, ./config, ../tests/keys/keys

proc loadSchema(ctx: GraphqlRef, schema: config.Schema): GraphqlResult =
  notice "loading graphql api", name = schema

  var conf = defaultParserConf()
  conf.flags.incl pfCommentDescription

  if schema == ethereum:
    ctx.initEthApi()
    ctx.parseSchemaFromFile("tests" / "schemas" / "ethereum_1.0.ql", conf = conf)
  else:
    ctx.initStarWarsApi()
    ctx.parseSchemaFromFile("tests" / "schemas" / "star_wars_schema.ql", conf = conf)

proc main() =
  var message: string
  ## Processing command line arguments
  let r = processArguments()

  if r.isErr:
    debugEcho r.error
    quit(QuitFailure)

  let conf = r.get

  let socketFlags = {ServerFlags.TcpNoDelay, ServerFlags.ReuseAddr}
  var ctx = GraphqlRef.new()

  let res = ctx.loadSchema(conf.schema)
  if res.isErr:
    debugEcho res.error
    return

  let sres = if conf.secure:
               GraphqlHttpServerRef.new(ctx,
                 address = conf.bindAddress,
                 tlsPrivateKey = TLSPrivateKey.init(SecureKey),
                 tlsCertificate = TLSCertificate.init(SecureCrt),
                 socketFlags = socketFlags)
             else:
               GraphqlHttpServerRef.new(ctx,
                 address = conf.bindAddress,
                 socketFlags = socketFlags)

  if sres.isErr():
    debugEcho sres.error
    return

  let server = sres.get()
  server.start()

  runForever()

main()
