# nim-graphql
# Copyright (c) 2021-2025 Status Research & Development GmbH
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
  api.NodeResult,
  api.RespResult,
  api.GraphqlResult,
  api.GraphqlError,
  api.NameCounter,
  api.InstrumentFlag,
  api.InstrumentResult,
  api.InstrumentObj,
  api.InstrumentRef,
  api.InstrumentProc,
  api.ExecRef,
  api.FieldSet,
  api.FieldRef,

  # exported results
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
  api.customCoercion,
  api.addVar,
  api.parseVar,
  api.parseVars,
  api.addResolvers,
  api.createName,
  api.executeRequest,
  api.validate,
  api.parseSchema,
  api.parseSchemaFromFile,
  api.parseSchemas,
  api.parseQuery,
  api.parseQueryFromFile,
  api.purgeQueries,
  api.purgeSchema,
  api.getNameCounter,
  api.purgeNames,
  api.treeRepr,
  api.addInstrument,

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
