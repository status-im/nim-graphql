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
  graphql/[parser, api],
  graphql/builtin/json_respstream as jrs

export
  # faststreams inputs
  inputs,

  # query_parser, schema_parser
  # and full_parser
  parser,

  # ast helper types
  api.ast_helper,

  # exported types
  api.`$`,
  api.ErrorDesc,
  api.ErrorLevel,
  api.Name,
  api.Result,
  api.GraphqlRef,
  api.ScalarResult,
  api.RespResult,
  api.ParseResult,
  api.GraphqlError,
  api.NameCounter,

  # exported stew/results
  api.isErr,
  api.isOk,
  api.err,
  api.ok,
  api.error,
  api.get,

  # graphql api
  api.init,
  api.new,
  api.customScalar,
  api.customScalars,
  api.addVar,
  api.parseVar,
  api.addResolvers,
  api.createName,
  api.executeRequest,
  api.validate,
  api.parseSchema,
  api.parseSchemaFromFile,
  api.parseQuery,
  api.parseQueryFromFile,
  api.purgeQueries,
  api.purgeSchema,
  api.getNameCounter,
  api.purgeNames,
  api.treeRepr,

  # graphql response
  api.respMap,
  api.respList,
  api.respNull,
  api.resp,

  # builtin json response stream
  jrs.new,
  jrs.getString,
  jrs.getBytes,
  jrs.JsonRespStream,
  jrs
