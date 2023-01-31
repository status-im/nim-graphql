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

  TestNames = enum
    tnHuman     = "Human"
    tnDroid     = "Droid"
    tnStarship  = "Starship"
    tnEntity    = "Entity"
    tnBird      = "Bird"
    tnTree      = "Tree"

  TestContext = ref object of RootRef
    names: array[TestNames, Name]

proc decodeResponse*(input: string): ServerResponse =
  try:
    result = Json.decode(input, ServerResponse)
  except JsonReaderError as e:
    debugEcho e.formatMsg("")

when (NimMajor, NimMinor, NimPatch) >= (1, 6, 0):
  {.push hint[XCannotRaiseY]: off.}
else:
  {.push hint[XDeclaredButNotUsed]: off.}
{.pragma: apiPragma, cdecl, gcsafe, raises: [Defect, CatchableError].}

proc queryNameImpl(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  ok(resp("superman"))

proc queryColorImpl(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  ok(resp(567))

proc queryTreeImpl(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var tc = TestContext(ud)
  let tree = respMap(tc.names[tnTree])
  tree["name"] = resp("hardwood")
  ok(tree)

proc queryEchoImpl(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  ok(params[0].val)

proc queryEchoArgImpl(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  ok(Node(params))

proc queryCheckFruit(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  let val = params[0].val
  if val.kind == nkEnum:
    ok(resp("GOOD"))
  else:
    ok(resp("BAD"))

proc queryCreatures(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var tc = TestContext(ud)
  let tree = respMap(tc.names[tnTree])
  tree["name"] = resp("redwood")
  let bird = respMap(tc.names[tnBird])
  bird["name"] = resp("parrot")
  var list = respList()
  list.add tree
  list.add bird
  ok(list)

proc querySearchImpl(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var tc = TestContext(ud)
  var list = respList()
  list.add respMap(tc.names[tnHuman])
  list.add respMap(tc.names[tnDroid])
  list.add respMap(tc.names[tnStarship])
  ok(list)

proc queryExampleImpl(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  let obj = params[0].val
  let number = obj[0][1]
  ok(number)

proc queryEchoString(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  let text = params[0].val
  if text.kind == nkString:
    ok(text)
  else:
    ok(respNull())

const queryProtos = {
  "name": queryNameImpl,
  "color": queryColorImpl,
  "tree": queryTreeImpl,
  "echo": queryEchoImpl,
  "echoArg": queryEchoArgImpl,
  "checkFruit": queryCheckFruit,
  "creatures": queryCreatures,
  "search": querySearchImpl,
  "example": queryExampleImpl,
  "echoString": queryEchoString
}

proc creatureNameImpl(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  ok(parent.map[0].val)

proc treeAgeImpl(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  ok(resp(100))

proc treeNumberImpl(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var list = respList()
  list.add resp(345)
  list.add respNull()
  list.add resp(789)
  ok(list)

const treeProtos = {
  "name": creatureNameImpl,
  "age": treeAgeImpl,
  "number": treeNumberImpl,
  "echoArg": queryEchoArgImpl
}

const creatureProtos = {
  "name": creatureNameImpl
}

proc birdColorImpl(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  ok(resp("RED"))

const birdProtos = {
  "name": creatureNameImpl,
  "color": birdColorImpl
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

proc nameImpl(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  let tc = TestContext(ud)
  if parent.typeName == tc.names[tnHuman]:
    ok(resp("Dr. Jones"))
  elif parent.typeName == tc.names[tnStarship]:
    ok(resp("Millenium Falcon"))
  else:
    ok(resp("3CPO"))

proc colorImpl(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  ok(resp("YELLOW"))

const droidProtos = {
  "name": nameImpl,
  "color": colorImpl
}

proc coerceEnum(ctx: GraphqlRef, typeNode, node: Node): NodeResult {.cdecl, gcsafe, noSideEffect.} =
  if node.kind == nkString:
    ok(Node(kind: nkEnum, name: ctx.createName(node.stringVal), pos: node.pos))
  else:
    err("cannot coerce '$1' to $2" % [$node.kind, $typeNode.sym.name])

proc initMockApi*(ctx: GraphqlRef) =
  var tc = TestContext()
  for c in TestNames:
    let name = ctx.createName($c)
    tc.names[c] = name

  ctx.addResolvers(tc, "Entity", [("name", nameImpl)])
  ctx.addResolvers(tc, "Human", [("name", nameImpl)])
  ctx.addResolvers(tc, "Droid", droidProtos)
  ctx.addResolvers(tc, "Starship", [("name", nameImpl)])

  ctx.addResolvers(tc, "Query", queryProtos)
  ctx.addResolvers(ctx, "Tree", treeProtos)
  ctx.addResolvers(ctx, "Creature", creatureProtos)
  ctx.addResolvers(ctx, "Bird", birdProtos)
  ctx.addResolvers(ctx, "Echo", echoProtos)
  ctx.customCoercion("Fruits", coerceEnum)

{.pop.}
