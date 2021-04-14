# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  common/[respstream, errors, response, ast],
  builtin/json_respstream

proc errorResp*(r: RespStream, msg: string) =
  respMap(r):
    r.fieldName("errors")
    respList(r):
      respMap(r):
        r.fieldName("message")
        r.write(msg)

proc serialize(r: RespStream, err: ErrorDesc, path: Node) =
  respMap(r):
    r.fieldName("message")
    r.write(err.message)
    r.fieldName("locations")
    respList(r):
      respMap(r):
        r.fieldName("line")
        r.write(err.pos.line.int)
        r.fieldName("column")
        r.write(err.pos.col.int)
    if not path.isNil:
      r.fieldName("path")
      response.serialize(path, r)

proc errorResp*(r: RespStream, err: seq[ErrorDesc]) =
  respMap(r):
    r.fieldName("errors")
    respList(r):
      for c in err:
        serialize(r, c, nil)

proc errorResp*(r: RespStream, err: seq[ErrorDesc], data: openArray[byte], path: Node) =
  respMap(r):
    r.fieldName("errors")
    respList(r):
      for i, c in err:
        serialize(r, c, if i < err.len-1: nil else: path)
    r.fieldName("data")
    r.write(data)

proc okResp*(r: RespStream, data: openArray[byte]) =
  respMap(r):
    r.fieldName("data")
    r.write(data)

proc jsonErrorResp*(msg: string): string =
  let resp = JsonRespStream.new()
  errorResp(resp, msg)
  resp.getString()

proc jsonErrorResp*(err: seq[ErrorDesc]): string =
  let resp = JsonRespStream.new()
  errorResp(resp, err)
  resp.getString()

proc jsonErrorResp*(err: seq[ErrorDesc], data: openArray[byte], path: Node): string =
  let resp = JsonRespStream.new()
  errorResp(resp, err, data, path)
  resp.getString()

proc jsonOkResp*(data: openArray[byte]): string =
  let resp = JsonRespStream.new()
  okResp(resp, data)
  resp.getString()
