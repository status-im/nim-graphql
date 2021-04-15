# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  std/[tables, strutils],
  stew/[results],
  ../common/[ast, ast_helper, response, names],
  ../graphql

{.pragma: apiPragma, cdecl, gcsafe, raises: [Defect, CatchableError].}
{.push hint[XDeclaredButNotUsed]: off.}

proc findType(ctx: GraphqlRef, nameStr: string): Symbol =
  let name = ctx.names.insert(nameStr)
  findType(name)

proc skipDeprecated(ctx: GraphqlRef, dirs: Dirs, includeDeprecated: bool): bool =
  let deprecated = ctx.names.keywords[kwDeprecated]
  for dir in dirs:
    if dir.name.sym.name == deprecated:
      return not includeDeprecated

proc directiveValue(dirs: Dirs, dirName, dirArg: Keyword): RespResult =
  for dir in dirs:
    if toKeyword(dir.name.sym.name) != dirName:
      continue
    let args = dir.args
    for arg in args:
      if toKeyword(arg.name.name) == dirArg:
        return ok(arg.val)
  ok(respNull())

proc deprecated(dirs: Dirs): RespResult =
  for dir in dirs:
    if toKeyword(dir.name.sym.name) == kwDeprecated:
      return ok(resp(true))
  ok(resp(false))

proc toDesc(node: Node): Node =
  if node.kind == nkEmpty:
    respNull()
  else:
    node

proc querySchema(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = GraphqlRef(ud)
  let name = ctx.names.insert("schema")
  let sym = findType(name)
  let resp = if sym.isNil:
               resp()
             else:
               resp(sym)
  ok(resp)

proc queryType(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = GraphqlRef(ud)
  let name = params[0].val
  let sym = ctx.findType(name.stringVal)
  if sym.isNil:
    err("'$1' not defined" % [name.stringVal])
  elif sym.kind == skDirective:
    err("'$1' is a directive, not a type" % [name.stringVal])
  else:
    ok(resp(sym))

proc queryTypename(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  if parent.kind != nkMap:
    return err("__typename expect a 'Map' but got '$1'" % [$parent.kind])

  ok(resp($parent.typeName))

const queryProtos* = {
  "__schema"   : querySchema,
  "__type"     : queryType,
  "__typename" : queryTypename
}

proc schemaDescription(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = GraphqlRef(ud)
  if parent.kind == nkSym:
    ok(toDesc(parent.sym.ast[0]))
  else:
    ok(respNull())

proc schemaTypes(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = GraphqlRef(ud)
  let arg = params[0].val
  let includeBuiltin = if arg.kind == nkBoolean: arg.boolVal else: false
  var list = respList()
  for v in values(ctx.typeTable):
    # schema is not a queryable entity from introspection pov
    if v.kind in {skDirective, skSchema}:
      continue
    if ((sfBuiltin in v.flags) != includeBuiltin):
      continue
    list.add resp(v)
  ok(list)

proc schemaQueryType(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = GraphqlRef(ud)
  ok(ctx.rootQuery)

proc schemaMutationType(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = GraphqlRef(ud)
  if ctx.rootMutation.kind == nkEmpty:
    ok(respNull())
  else:
    ok(ctx.rootMutation)

proc schemaSubscriptionType(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = GraphqlRef(ud)
  if ctx.rootSubs.kind == nkEmpty:
    ok(respNull())
  else:
    ok(ctx.rootSubs)

proc schemaDirectives(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = GraphqlRef(ud)
  let arg = params[0].val
  let includeBuiltin = if arg.kind == nkBoolean: arg.boolVal else: false
  var list = respList()
  for v in values(ctx.typeTable):
    if v.kind != skDirective:
      continue
    if ((sfBuiltin in v.flags) != includeBuiltin):
      continue
    list.add resp(v)
  ok(list)

const schemaProtos* = {
  "description"     : schemaDescription,
  "types"           : schemaTypes,
  "queryType"       : schemaQueryType,
  "mutationType"    : schemaMutationType,
  "subscriptionType": schemaSubscriptionType,
  "directives"      : schemaDirectives
}

proc typeKind(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  case parent.kind
  of nkNonNullType:
    result = ok(resp("NON_NULL"))
  of nkListType:
    result = ok(resp("LIST"))
  of nkSym:
    case parent.sym.kind
    of skScalar:      result = ok(resp("SCALAR"))
    of skObject:      result = ok(resp("OBJECT"))
    of skInterface:   result = ok(resp("INTERFACE"))
    of skUnion:       result = ok(resp("UNION"))
    of skEnum:        result = ok(resp("ENUM"))
    of skInputObject: result = ok(resp("INPUT_OBJECT"))
    else:
      debugEcho "KIND: ", parent.sym.kind
      unreachable()
  else:
    unreachable()

proc typeName(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  if parent.kind == nkSym:
    ok(resp($parent))
  else:
    ok(respNull())

proc typeDescription(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  if parent.kind == nkSym:
    ok(toDesc(parent.sym.ast[0]))
  else:
    ok(respNull())

proc typeFields(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = GraphqlRef(ud)
  let arg = params[0].val
  let includeDeprecated = if arg.kind == nkBoolean: arg.boolVal else: false
  if parent.kind == nkSym and parent.sym.kind in {skObject, skInterface}:
    var list = respList()
    let fields = Object(parent.sym.ast).fields
    for n in fields:
      if ctx.skipDeprecated(n.dirs, includeDeprecated):
        continue
      list.add Node(n)
    ok(list)
  else:
    ok(respNull())

proc typeInterfaces(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  if parent.kind == nkSym and parent.sym.kind in {skObject, skInterface}:
    var list = respList()
    let impls = Object(parent.sym.ast).implements
    for n in impls:
      list.add n
    ok(list)
  else:
    ok(respNull())

proc typePossibleTypes(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = GraphqlRef(ud)
  if parent.kind == nkSym and parent.sym.kind in {skUnion, skInterface}:
    var list = respList()
    if parent.sym.kind == skUnion:
      let members = Union(parent.sym.ast).members
      for n in members:
        list.add n
    else:
      for n in parent.sym.types:
        list.add n
    ok(list)
  else:
    ok(respNull())

proc typeEnumValues(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = GraphqlRef(ud)
  let arg = params[0].val
  let includeDeprecated = if arg.kind == nkBoolean: arg.boolVal else: false
  if parent.kind == nkSym and parent.sym.kind == skEnum:
    var list = respList()
    let values = Enum(parent.sym.ast).values
    for n in values:
      if ctx.skipDeprecated(n.dirs, includeDeprecated):
        continue
      list.add Node(n)
    ok(list)
  else:
    ok(respNull())

proc typeInputFields(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  if parent.kind == nkSym and parent.sym.kind in {skInputObject}:
    var list = respList()
    let fields = InputObject(parent.sym.ast).fields
    for n in fields:
      list.add Node(n)
    ok(list)
  else:
    ok(respNull())

proc typeOfType(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  if parent.kind in {nkListType, nkNonNullType}:
    ok(parent[0])
  else:
    ok(respNull())

proc typeSpecifiedByURL(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  if parent.kind == nkSym and parent.sym.kind == skScalar:
    directiveValue(Scalar(parent.sym.ast).dirs, kwSpecifiedByURL, kwUrl)
  else:
    ok(respNull())

const typeProtos* = {
  "kind"          : typeKind,
  "name"          : typeName,
  "description"   : typeDescription,
  "fields"        : typeFields,
  "interfaces"    : typeInterfaces,
  "possibleTypes" : typePossibleTypes,
  "enumValues"    : typeEnumValues,
  "inputFields"   : typeInputFields,
  "ofType"        : typeOfType,
  "specifiedByURL": typeSpecifiedByURL
}

proc fieldName(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  let name = ObjectField(parent).name
  ok(resp($name))

proc fieldDescription(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  ok(ObjectField(parent).desc.toDesc)

proc fieldArgs(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var list = respList()
  let args = ObjectField(parent).args
  for arg in args:
    list.add Node(arg)
  ok(list)

proc fieldType(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  ok(ObjectField(parent).typ)

proc fieldDeprecated(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  deprecated(ObjectField(parent).dirs)

proc fieldDeprecatedReason(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  directiveValue(ObjectField(parent).dirs, kwDeprecated, kwReason)

const fieldProtos* = {
  "name"             : introspection.fieldName,
  "description"      : fieldDescription,
  "args"             : fieldArgs,
  "type"             : fieldType,
  "isDeprecated"     : fieldDeprecated,
  "deprecationReason": fieldDeprecatedReason
}

proc invalName(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  let arg = Argument(parent)
  ok(resp($arg.name))

proc invalDescription(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  ok(Argument(parent).desc.toDesc)

proc invalType(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  ok(Argument(parent).typ)

proc invalDefVal(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  let val = Argument(parent).defVal
  case val.kind
  of nkNull: ok(val)
  of nkEmpty: ok(respNull())
  else: ok(resp($val))

const inputValueProtos* = {
  "name"        : invalName,
  "description" : invalDescription,
  "type"        : invalType,
  "defaultValue": invalDefVal
}

proc enumValName(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  ok(resp($EnumVal(parent).name))

proc enumValDescription(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  ok(EnumVal(parent).desc.toDesc)

proc enumValDeprecated(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  deprecated(EnumVal(parent).dirs)

proc enumValDeprecatedReason(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  directiveValue(EnumVal(parent).dirs, kwDeprecated, kwReason)

const enumValueProtos* = {
  "name"             : enumValName,
  "description"      : enumValDescription,
  "isDeprecated"     : enumValDeprecated,
  "deprecationReason": enumValDeprecatedReason
}

proc dirName(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  let dir = Directive(parent.sym.ast)
  ok(resp($dir.name))

proc dirDescription(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  let dir = Directive(parent.sym.ast)
  ok(dir.desc.toDesc)

proc dirLocations(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var list = respList()
  let locs = Directive(parent.sym.ast).locs
  for n in locs:
    list.add resp($n)
  ok(list)

proc dirArgs(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  let args = Directive(parent.sym.ast).args
  var list = respList()
  for arg in args:
    list.add Node(arg)
  ok(list)

proc dirRepeatable(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  ok(resp(sfRepeatable in parent.sym.flags))

const directiveProtos* = {
  "name"        : dirName,
  "description" : dirDescription,
  "locations"   : dirLocations,
  "args"        : dirArgs,
  "isRepeatable": dirRepeatable
}

{.pop.}
