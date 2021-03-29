# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  testutils/fuzzing,
  faststreams,
  ../graphql/schema_parser,
  ../graphql/common/names

test:
  var doc: SchemaDocument
  var stream = unsafeMemoryInput(payload)
  var parser = Parser.init(stream)
  parser.flags.incl pfAcceptReservedWords
  parser.parseDocument(doc)
