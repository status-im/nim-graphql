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
  common/[respstream, errors, response, ast, names, types],
  lexer, common_parser, graphql,
  builtin/json_respstream

type
  ParseResult* = Result[Node, seq[ErrorDesc]]
  RequestObject* = object
    query*: Node
    operationName*: Node
    variables*: Node

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

proc addVariables*(ctx: GraphqlRef, vars: Node) =
  if vars.kind != nkInput:
    return
  for n in vars:
    if n.len != 2: continue
    # support both json/graphql object key
    if n[0].kind == nkString:
      let varname = ctx.names.insert(n[0].stringVal)
      ctx.varTable[varname] = n[1]
    else:
      ctx.varTable[n[0].name] = n[1]

proc parseLiteral(ctx: GraphqlRef, input: InputStream): ParseResult =
  var parser = Parser.init(input, ctx.names)
  var values: Node

  # we want to parse a json object
  parser.flags.incl pfJsonCompatibility
  parser.lex.next()
  if parser.lex.tok == tokEof:
    return ok(ctx.emptyNode)
  parser.rgReset(rgValueLiteral) # recursion guard
  parser.valueLiteral(isConst = true, values)
  if parser.error != errNone:
    return err(@[parser.err])
  ok(values)

proc parseLiteral*(ctx: GraphqlRef, input: string): ParseResult {.gcsafe.} =
  {.gcsafe.}:
    var stream = unsafeMemoryInput(input)
    ctx.parseLiteral(stream)

proc parseLiteral*(ctx: GraphqlRef, input: openArray[byte]): ParseResult {.gcsafe.} =
  {.gcsafe.}:
    var stream = unsafeMemoryInput(input)
    ctx.parseLiteral(stream)

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

proc toQueryNode*(data: string): Node =
  Node(kind: nkString, stringVal: data, pos: Pos())

proc init*(_: type RequestObject): RequestObject =
  let empty = Node(kind: nkEmpty, pos: Pos())
  result.query         = empty
  result.operationName = empty
  result.variables     = empty

proc requestNodeToObject*(node: Node, ro: var RequestObject) =
  for n in node:
    if n.len != 2: continue
    case $n[0]
    of "query": ro.query = n[1]
    of "operationName": ro.operationName = n[1]
    of "variables": ro.variables = n[1]

proc toString*(node: Node): string =
  if node.isNil:
    return ""
  if node.kind == nkEmpty:
    return ""
  $node
