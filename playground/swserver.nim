# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  std/[os], chronos,
  ../graphql, ../graphql/httpserver,
  ./swapi

proc main() =
  var address = initTAddress("127.0.0.1:8547")
  let socketFlags = {ServerFlags.TcpNoDelay, ServerFlags.ReuseAddr}
  var ctx = GraphqlRef.new()
  ctx.initStarWarsApi()
  
  let res = ctx.parseSchemaFromFile("tests" / "schemas" / "star_wars_schema.ql")
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
