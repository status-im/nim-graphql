# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  faststreams/inputs,
  graphql/[server, client, parser, api],
  graphql/builtin/json_respstream as jrs

export server, client, parser

export
  # faststreams inputs
  inputs,

  # ast helper types
  api.ast_helper,

  # exported types
  api.`$`,
  api.ErrorDesc,
  api.ErrorLevel,
  api.Name,
  api.Result,
  api.ContextRef,
  api.RespResult,
  api.ContextError,

  # exported stew/results
  api.isErr,
  api.isOk,
  api.err,
  api.ok,

  # graphql api
  api.newContext,
  api.customScalar,
  api.addVar,
  api.parseVar,
  api.registerResolvers,
  api.createName,
  api.executeRequest,
  api.validate,

  # graphql response
  api.respMap,
  api.respList,
  api.respNull,
  api.resp,

  # builtin json response stream
  jrs.newJsonRespStream,
  jrs.getOutput
