# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  std/[options, strutils],
  ../graphql

type
  Episode = enum
    NEWHOPE
    EMPIRE
    JEDI

  Kind = enum
    kHuman = "Human"
    kDroid = "Droid"
    kShip  = "Starship"

  Review = object
    episode: Episode
    stars: int
    commentary: string

  Starwars = ref object of RootRef
    names: array[Kind, Name]
    characters: seq[Character]
    ships: seq[Starship]
    reviews: seq[Review]

  Character = ref object of RootRef
    kind: Kind
    id: string
    name: string
    friends: seq[string]
    appearsIn: seq[Episode]

  Human = ref object of Character
    homePlanet: string
    height: float64
    mass: Option[float64]
    starships: seq[string]

  Droid = ref object of Character
    primaryFunction: string

  Starship = ref object
    id: string
    name: string
    length: float64
    coord: array[2, float64]

let characters = [
  Human(
    kind: kHuman,
    id: "1000",
    name: "Luke Skywalker",
    friends: @[ "1002", "1003", "2000", "2001" ],
    appearsIn: @[ NEWHOPE, EMPIRE, JEDI ],
    homePlanet: "Tatooine",
    height: 1.72,
    mass: some(77.0),
    starships: @[ "3001", "3003" ]
  ),
  Human(
    kind: kHuman,
    id: "1001",
    name: "Darth Vader",
    friends: @[ "1004" ],
    appearsIn: @[ NEWHOPE, EMPIRE, JEDI ],
    homePlanet: "Tatooine",
    height: 2.02,
    mass: some(136.0),
    starships: @[ "3002" ]
  ),
  Human(
    kind: kHuman,
    id: "1002",
    name: "Han Solo",
    friends: @[ "1000", "1003", "2001" ],
    appearsIn: @[ NEWHOPE, EMPIRE, JEDI ],
    height: 1.8,
    mass: some(80.0),
    starships: @[ "3000", "3003" ]
  ),
  Human(
    kind: kHuman,
    id: "1003",
    name: "Leia Organa",
    friends: @[ "1000", "1002", "2000", "2001" ],
    appearsIn: @[ NEWHOPE, EMPIRE, JEDI ],
    homePlanet: "Alderaan",
    height: 1.5,
    mass: some(49.0),
    starships: @[]
  ),
  Human(
    kind: kHuman,
    id: "1004",
    name: "Wilhuff Tarkin",
    friends: @[ "1001" ],
    appearsIn: @[ NEWHOPE ],
    height: 1.8,
    mass: none(float64),
    starships: @[]
  ),
  Droid(
    kind: kDroid,
    id: "2000",
    name: "C-3PO",
    friends: @[ "1000", "1002", "1003", "2001" ],
    appearsIn: @[ NEWHOPE, EMPIRE, JEDI ],
    primaryFunction: "Protocol"
  ),
  Droid(
    kind: kDroid,
    id: "2001",
    name: "R2-D2",
    friends: @[ "1000", "1002", "1003" ],
    appearsIn: @[ NEWHOPE, EMPIRE, JEDI ],
    primaryFunction: "Astromech"
  )
]

let starships = [
  Starship(
    id: "3000",
    name: "Millenium Falcon",
    length: 34.37
  ),
  Starship(
    id: "3001",
    name: "X-Wing",
    length: 12.5
  ),
  Starship(
    id: "3002",
    name: "TIE Advanced x1",
    length: 9.2
  ),
  Starship(
    id: "3003",
    name: "Imperial shuttle",
    length: 20
  )
]

proc charToResp(ctx: Starwars, c: Character): Node =
  var resp = respMap(ctx.names[c.kind])
  resp["id"]   = resp(c.id)
  resp["name"] = resp(c.name)
  var list = respList()
  for n in c.friends:
    list.add resp(n)
  resp["friends"] = list
  list = respList()
  for n in c.appearsIn:
    list.add resp($n)
  resp["appearsIn"] = list
  resp

proc findChar(ctx: Starwars, id: string): RespResult =
  for n in ctx.characters:
    if n.id == id:
      return ok(ctx.charToResp(n))
  err("can't find hero with id: " & id)

proc droidToResp(ctx: Starwars, c: Character): Node =
  var resp = ctx.charToResp(c)
  let droid = Droid(c)
  resp["primaryFunction"] = resp(droid.primaryFunction)
  resp

proc findDroid(ctx: Starwars, id: string): RespResult =
  for n in ctx.characters:
    if n.id == id and n.kind == kDroid:
      return ok(ctx.droidToResp(n))
  err("can't find droid with id: " & id)

proc shipToResp(ctx: Starwars, s: Starship): Node =
  var resp = respMap(ctx.names[kShip])
  resp["id"] = resp(s.id)
  resp["name"] = resp(s.name)
  resp["length"] = resp(s.length)
  resp

proc findShip(ctx: Starwars, id: string): RespResult =
  for n in ctx.ships:
    if n.id == id:
      return ok(ctx.shipToResp(n))
  err("can't find ship with id: " & id)

proc humanToResp(ctx: Starwars, c: Character): Node =
  var resp = ctx.charToResp(c)
  let h = Human(c)
  resp["homePlanet"] = resp(h.homePlanet)
  resp["height"] = resp(h.height)
  resp["mass"] = if h.mass.isSome: resp(h.mass.get)
                 else: respNull()
  var list = respList()
  for n in h.starships:
    list.add resp(n)
  resp["starship"] = list
  resp

proc findHuman(ctx: Starwars, id: string): RespResult =
  for n in ctx.characters:
    if n.id == id and n.kind == kHuman:
      return ok(ctx.humanToResp(n))
  err("can't find human with id: " & id)

proc fillFriends(ctx: Starwars, parent: Node): RespResult =
  let ids = parent.map[2].val
  var list = respList()
  for n in ids:
    var res = ctx.findChar(n.stringVal)
    if res.isOk:
      list.add res.get()
    else:
      list.add respNull()
  ok(list)

proc toResp(ctx: Starwars, c: Character): Node =
  if c.kind == kHuman:
    humanToResp(ctx, c)
  else:
    droidToResp(ctx, c)

proc search(c: Character, text: string): bool =
  if text in c.id: return true
  if text in c.name: return true
  for n in c.friends:
    if text in n: return true

  if c.kind == kHuman:
    let h = Human(c)
    if text in h.homePlanet: return true
    for n in h.starships:
      if text in n: return true
  else:
    let d = Droid(c)
    if text in d.primaryFunction: return true

proc search(c: Starship, text: string): bool =
  if text in c.id: return true
  if text in c.name: return true

proc search(ctx: Starwars, text: string): Node =
  var list = respList()
  for n in ctx.characters:
    if search(n, text):
      list.add toResp(ctx, n)

  for n in ctx.ships:
    if search(n, text):
      list.add shipToResp(ctx, n)

  list

{.pragma: apiPragma, cdecl, gcsafe, raises: [Defect, CatchableError].}
{.push hint[XDeclaredButNotUsed]: off.}

proc queryHero(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  ## Allows us to fetch the undisputed hero of the Star Wars trilogy, R2-D2.
  var ctx = Starwars(ud)
  let episode = params[0].val
  if episode.kind in {nkEmpty, nkNull}:
    return ctx.findChar("2001")

  if $episode.name == "EMPIRE":
    # Luke is the hero of Episode V.
    return ctx.findChar("1000")

  # Artoo is the hero otherwise.
  return ctx.findChar("2001")

proc queryReviews(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  err("not implemented")

proc querySearch(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = Starwars(ud)
  let text = params[0].val
  if text.kind == nkString:
    let list = ctx.search(text.stringVal)
    ok(list)
  else:
    ok(respNull())

proc queryCharacter(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = Starwars(ud)
  let id = params[0].val
  return ctx.findChar(id.stringVal)

proc queryDroid(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = Starwars(ud)
  let id = params[0].val
  return ctx.findDroid(id.stringVal)

proc queryHumans(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = Starwars(ud)
  var list = respList()
  for n in ctx.characters:
    if n.kind == kHuman:
      list.add ctx.humanToResp(n)
  ok(list)

proc queryHuman(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = Starwars(ud)
  let id = params[0].val
  return ctx.findHuman(id.stringVal)

proc queryStarship(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = Starwars(ud)
  let id = params[0].val
  ctx.findShip(id.stringVal)

const queryProcs = {
  "hero": queryHero,
  "reviews": queryReviews,
  "search": querySearch,
  "character": queryCharacter,
  "droid": queryDroid,
  "humans": queryHumans,
  "human": queryHuman,
  "starship": queryStarship
}

proc charId(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  ok(parent.map[0].val)

proc charName(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  ok(parent.map[1].val)

proc charFriends(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = Starwars(ud)
  ctx.fillFriends(parent)

proc charFriendsConnection(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  err("not implemented")

proc charAppearsIn(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  ok(parent.map[3].val)

const charProcs = {
  "id": charId,
  "name": charName,
  "friends": charFriends,
  "friendsConnection": charFriendsConnection,
  "appearsIn": charAppearsIn
}

proc humanHomePlanet(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  ok(parent.map[4].val)

proc humanHeight(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  let height = parent.map[5].val
  let unit = params[0].val
  if $unit == "FOOT":
    ok(resp(3.28084 * parseFloat(height.floatVal)))
  else:
    ok(height)

proc humanMass(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  ok(parent.map[6].val)

proc humanStarships(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = Starwars(ud)
  var ships = parent.map[7].val
  var list = respList()
  for n in ships:
    var res = ctx.findShip(n.stringVal)
    if res.isOk:
      list.add res.get()
    else:
      list.add respNull()
  ok(list)

const human = {
  "id": charId,
  "name": charName,
  "friends": charFriends,
  "friendsConnection": charFriendsConnection,
  "appearsIn": charAppearsIn,
  "homePlanet": humanHomePlanet,
  "height": humanHeight,
  "mass": humanMass,
  "starships": humanStarships
}

proc droidPrimaryFunction(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  ok(parent.map[4].val)

const droidProcs = {
  "id": charId,
  "name": charName,
  "friends": charFriends,
  "friendsConnection": charFriendsConnection,
  "appearsIn": charAppearsIn,
  "primaryFunction": droidPrimaryFunction
}

proc fcTotalCount(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  discard

proc fcEdges(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  discard

proc fcFriends(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  discard

proc fcPageInfo(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  discard

const friendsConnectionProcs = {
  "totalCount": fcTotalCount,
  "edges": fcEdges,
  "friends": fcFriends,
  "pageInfo": fcPageInfo
}

proc feCursor(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  discard

proc feNode(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  discard

const friendsEdgeProcs = {
  "cursor": feCursor,
  "node": feNode
}

proc piStartCursor(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  discard

proc piEndCursor(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  discard

proc piHasNextPage(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  discard

const pageInfoProcs = {
  "startCursor": piStartCursor,
  "endCursor": piEndCursor,
  "hasNextPage": piHasNextPage
}

proc reviewEpisode(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  discard

proc reviewStars(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  discard

proc reviewCommentary(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  discard

const reviewProcs = {
  "episode": reviewEpisode,
  "stars": reviewStars,
  "commentary": reviewCommentary
}

proc starshipId(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  ok(parent.map[0].val)

proc starshipName(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  ok(parent.map[1].val)

proc starshipLength(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  ok(parent.map[2].val)

proc starshipCoordinates(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var list = respList()
  var c = respList()
  var d = respList()
  c.add resp(1)
  c.add resp(2)
  d.add resp(3)
  d.add resp(4)
  list.add c
  list.add d
  ok(list)

const starshipProcs = {
  "id": starshipId,
  "name": starshipName,
  "length": starshipLength,
  "coordinates": starshipCoordinates
}

proc coerceEnum(ctx: GraphqlRef, typeNode, node: Node): NodeResult {.cdecl, gcsafe, noSideEffect.} =
  case node.kind
  of nkString:
    ok(Node(kind: nkEnum, name: ctx.createName(node.stringVal), pos: node.pos))
  of nkEnum:
    ok(node)
  else:
    err("cannot coerce '$1' to $2" % [$node.kind, $typeNode])

{.pop.}

proc initStarWarsApi*(ctx: GraphqlRef) =
  var ud = Starwars(characters: @characters, ships: @starships)
  for n in Kind:
    ud.names[n] = ctx.createName($n)

  ctx.addResolvers(ud, "Droid", droidProcs)
  ctx.addResolvers(ud, "FriendsEdge", friendsEdgeProcs)
  ctx.addResolvers(ud, "FriendsConnection", friendsConnectionProcs)
  ctx.addResolvers(ud, "PageInfo", pageInfoProcs)
  ctx.addResolvers(ud, "Review", reviewProcs)
  ctx.addResolvers(ud, "Human", human)
  ctx.addResolvers(ud, "Query", queryProcs)
  ctx.addResolvers(ud, "Character", charProcs)
  ctx.addResolvers(ud, "Starship", starshipProcs)
  ctx.customCoercion("Episode", coerceEnum)
  ctx.customCoercion("LengthUnit", coerceEnum)
