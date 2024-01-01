# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  std/tables,
  stew/results, faststreams/inputs,
  common/[respstream, errors, ast, types],
  lexer, common_parser, graphql,
  builtin/json_respstream

type
  ParseResult* = Result[Node, seq[ErrorDesc]]
  RequestObject* = object
    query*: Node
    operationName*: Node
    variables*: Node

{.push gcsafe, raises: [IOError].}

proc errorResp*(r: JsonRespStream, msg: string) =
  respMap(r):
    r.field("errors")
    respList(r):
      respMap(r):
        r.field("message")
        r.write(msg)

proc serialize(r: JsonRespStream, err: ErrorDesc) =
  respMap(r):
    r.field("message")
    r.write(err.message)
    r.field("locations")
    respList(r):
      respMap(r):
        r.field("line")
        r.write(err.pos.line.int)
        r.field("column")
        r.write(err.pos.col.int)
    if not err.path.isNil and err.path.len > 0:
      r.field("path")
      r.serialize(err.path)

proc errorResp*(r: JsonRespStream, err: seq[ErrorDesc]) =
  respMap(r):
    r.field("errors")
    respList(r):
      for c in err:
        serialize(r, c)

proc errorResp*(r: JsonRespStream, err: seq[ErrorDesc], data: openArray[byte]) =
  respMap(r):
    r.field("errors")
    respList(r):
      for i, c in err:
        serialize(r, c)
    r.field("data")
    r.write(data)

proc okResp*(r: JsonRespStream, data: openArray[byte]) =
  respMap(r):
    r.field("data")
    r.write(data)

proc jsonErrorResp*(msg: string): string =
  let resp = JsonRespStream.new()
  errorResp(resp, msg)
  resp.getString()

proc jsonErrorResp*(err: seq[ErrorDesc]): string =
  let resp = JsonRespStream.new()
  errorResp(resp, err)
  resp.getString()

proc jsonErrorResp*(err: seq[ErrorDesc], data: openArray[byte]): string =
  let resp = JsonRespStream.new()
  errorResp(resp, err, data)
  resp.getString()

proc jsonOkResp*(data: openArray[byte]): string =
  let resp = JsonRespStream.new()
  okResp(resp, data)
  resp.getString()

proc addVariables*(ctx: GraphqlRef, vars: Node) {.gcsafe, raises: [].} =
  if vars.kind != nkInput:
    return
  for n in vars:
    if n.len != 2: continue
    ctx.varTable[n[0].name] = n[1]

proc parseLiteral(ctx: GraphqlRef, input: InputStream, flags: set[ParserFlag]): ParseResult =
  var parser = Parser.init(input, ctx.names)
  var values: Node

  # we want to parse a json object
  parser.flags.incl flags
  parser.lex.next()
  if parser.lex.tok == tokEof:
    return ok(ctx.emptyNode)
  parser.rgReset(rgValueLiteral) # recursion guard
  parser.valueLiteral(isConst = true, values)
  if parser.error != errNone:
    return err(@[parser.err])
  ok(values)

proc parseLiteral*(ctx: GraphqlRef, input: string, flags = {pfJsonCompatibility, pfJsonKeyToName}): ParseResult {.gcsafe.} =
  {.gcsafe.}:
    var stream = unsafeMemoryInput(input)
    ctx.parseLiteral(stream, flags)

proc parseLiteral*(ctx: GraphqlRef, input: openArray[byte], flags = {pfJsonCompatibility, pfJsonKeyToName}): ParseResult {.gcsafe.} =
  {.gcsafe.}:
    var stream = unsafeMemoryInput(input)
    ctx.parseLiteral(stream, flags)

proc parseLiteralFromFile*(ctx: GraphqlRef, fileName: string, flags = {pfJsonCompatibility, pfJsonKeyToName}): ParseResult {.gcsafe.} =
  {.gcsafe.}:
    var stream = memFileInput(fileName)
    ctx.parseLiteral(stream, flags)

proc decodeRequest*(ctx: GraphqlRef, ro: var RequestObject, k, v: string): ParseResult =
  let res = ctx.parseLiteral(v)
  if res.isErr:
    return res

  result = res
  case k
  of "query":         ro.query = res.get()
  of "operationName": ro.operationName = res.get()
  of "variables":     ro.variables = res.get()
  else: discard

proc toQueryNode*(data: string): Node {.gcsafe, raises: [].} =
  Node(kind: nkString, stringVal: data, pos: Pos())

proc init*(_: type RequestObject): RequestObject {.gcsafe, raises: [].} =
  let empty = Node(kind: nkEmpty, pos: Pos())
  result.query         = empty
  result.operationName = empty
  result.variables     = empty

proc requestNodeToObject*(node: Node, ro: var RequestObject) {.gcsafe, raises: [].} =
  for n in node:
    if n.len != 2: continue
    case $n[0]
    of "query": ro.query = n[1]
    of "operationName": ro.operationName = n[1]
    of "variables": ro.variables = n[1]

proc toString*(node: Node): string {.gcsafe, raises: [].} =
  if node.isNil:
    return ""
  case node.kind
  of nkEmpty:
    return ""
  of nkString:
    return node.stringVal
  else:
    $node

{.pop.}
