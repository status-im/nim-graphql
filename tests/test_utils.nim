# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  std/[json, strutils],
  json_serialization,
  ../graphql

type
  ServerResponse* = object
    errors*: JsonNode
    data*: JsonNode

proc decodeResponse*(input: string): ServerResponse =
  try:
    result = Json.decode(input, ServerResponse)
  except JsonReaderError as e:
    debugEcho e.formatMsg("")

proc removeWhitespaces*(x: string): string =
  # TODO: do not remove white spaces in string/multiline string
  const whites = {' ', '\t', '\r', '\n'}
  for c in x:
    if c notin whites:
      result.add c

{.push hint[XDeclaredButNotUsed]: off.}
{.pragma: apiPragma, cdecl, gcsafe, raises: [Defect, CatchableError].}

proc queryNameImpl(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  ok(resp("superman"))

proc queryColorImpl(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  ok(resp(567))

proc queryHumanImpl(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  let ctx = GraphqlRef(ud)
  let name = ctx.createName("Human")
  ok(respMap(name))

proc queryEchoImpl(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  let ctx = GraphqlRef(ud)
  ok(params[0].val)

proc queryCheckFruit(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  let val = params[0].val
  if val.kind == nkEnum:
    ok(resp("GOOD"))
  else:
    ok(resp("BAD"))

const queryProtos = {
  "name": queryNameImpl,
  "color": queryColorImpl,
  "human": queryHumanImpl,
  "echo": queryEchoImpl,
  "checkFruit": queryCheckFruit
}

proc humanNameImpl(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  ok(resp("spiderman"))

proc humanAgeImpl(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  ok(resp(100))

proc humanNumberImpl(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var list = respList()
  list.add resp(345)
  list.add respNull()
  list.add resp(789)
  ok(list)

const humanProtos = {
  "name": humanNameImpl,
  "age": humanAgeImpl,
  "number": humanNumberImpl
}

proc echoProc(parent: Node, i: int): RespResult =
  if parent[i][1].kind == nkEmpty:
    ok(respNull())
  else:
    ok(parent[i][1])

proc echoOneImpl(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  echoProc(parent, 0)

proc echoTwoImpl(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  echoProc(parent, 1)

proc echoThreeImpl(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  echoProc(parent, 2)

proc echoFourImpl(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  echoProc(parent, 3)

proc echoFiveImpl(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  echoProc(parent, 4)

const echoProtos = {
  "one": echoOneImpl,
  "two": echoTwoImpl,
  "three": echoThreeImpl,
  "four": echoFourImpl,
  "five": echoFiveImpl,
}

proc coerceEnum(ctx: GraphqlRef, typeNode, node: Node): NodeResult {.cdecl, gcsafe, nosideEffect.} =
  if node.kind == nkString:
    ok(Node(kind: nkEnum, name: ctx.createName(node.stringVal), pos: node.pos))
  else:
    err("cannot coerce '$1' to $2" % [$node.kind, $typeNode.sym.name])

proc initMockApi*(ctx: GraphqlRef) =
  ctx.addResolvers(ctx, "Query", queryProtos)
  ctx.addResolvers(ctx, "Human", humanProtos)
  ctx.addResolvers(ctx, "Echo", echoProtos)
  ctx.customCoercion("Fruits", coerceEnum)

{.pop.}
