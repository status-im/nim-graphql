# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import hashes

type
  Name* {.acyclic.} = ref object
    id* : int
    s*  : string
    h   : Hash
    next: Name

  Keyword* = enum
    kwInvalid     = ":invalid"
    kwDirective   = "directive"
    kwEnum        = "enum"
    kwExtend      = "extend"
    kwFalse       = "false"
    kwImplements  = "implements"
    kwInput       = "input"
    kwInterface   = "interface"
    kwNull        = "null"
    kwOn          = "on"
    kwRepeatable  = "repeatable"
    kwScalar      = "scalar"
    kwSchema      = "schema"
    kwTrue        = "true"
    kwType        = "type"
    kwUnion       = "union"

    # Definitions
    # Don't change this order
    kwQuery          = "query"
    kwMutation       = "mutation"
    kwSubscription   = "subscription"
    kwFragment       = "fragment"

    kwRootQuery        = "Query"
    kwRootMutation     = "Mutation"
    kwRootSubscription = "Subscription"

    # builtin directives
    kwSkip        = "skip"
    kwInclude     = "include"
    kwDeprecated  = "deprecated"
    kwIf          = "if"
    kwReason      = "reason"
    kwSpecifiedBy = "specifiedBy"
    kwUrl         = "url"

    # Type system instrospection
    introsSchema       = "__schema"
    introsType         = "__type"
    introsTypeName     = "__typename"
    introsRoot         = "__Query"

    # ExecutableDirectiveLocation
    LocQUERY                = "QUERY"
    LocMUTATION             = "MUTATION"
    LocSUBSCRIPTION         = "SUBSCRIPTION"
    LocFIELD                = "FIELD"
    LocFRAGMENT_DEFINITION  = "FRAGMENT_DEFINITION"
    LocFRAGMENT_SPREAD      = "FRAGMENT_SPREAD"
    LocINLINE_FRAGMENT      = "INLINE_FRAGMENT"
    LocVARIABLE_DEFINITION  = "VARIABLE_DEFINITION"

    # TypeSystemDirectiveLocation
    LocSCHEMA                  = "SCHEMA"
    LocSCALAR                  = "SCALAR"
    LocOBJECT                  = "OBJECT"
    LocFIELD_DEFINITION        = "FIELD_DEFINITION"
    LocARGUMENT_DEFINITION     = "ARGUMENT_DEFINITION"
    LocINTERFACE               = "INTERFACE"
    LocUNION                   = "UNION"
    LocENUM                    = "ENUM"
    LocENUM_VALUE              = "ENUM_VALUE"
    LocINPUT_OBJECT            = "INPUT_OBJECT"
    LocINPUT_FIELD_DEFINITION  = "INPUT_FIELD_DEFINITION"

  NameCounter* = distinct int

  NameCache* = ref object
    buckets   : array[4096, Name]
    counter   : int
    anonName* : Name
    emptyName*: Name
    keywords* : array[Keyword, Name]

const MaxKeyword = Keyword.high.int

{.push gcsafe, raises: [] .}

proc insert*(nc: NameCache, name: string): Name

proc newNameCache*(): NameCache =
  var nc = new(NameCache)
  # special names
  nc.anonName     = nc.insert ":anonymous"
  nc.anonName.id  = -1
  nc.emptyName    = nc.insert ""
  nc.emptyName.id = -2

  # exclude NameInvalid
  let firstName = succ(Keyword.low)
  for kw in firstName..Keyword.high:
    let word = nc.insert($kw)
    word.id = int(kw)
    nc.keywords[kw] = word

  nc.counter = MaxKeyword
  return nc

proc getName(nc: NameCache, name: string, h: Hash): Name =
  let idx = h and high(nc.buckets)
  var curName = nc.buckets[idx]
  var last = Name(nil)
  while curName != nil:
    if curName.s == name:
      if last != nil:
        # make access to last looked up identifier faster:
        last.next = curName.next
        curName.next = nc.buckets[idx]
        nc.buckets[idx] = curName
      return curName
    last = curName
    curName = curName.next

  inc(nc.counter)
  curName = new(Name)
  curName.s = name
  curName.h = h
  curName.next = nc.buckets[idx]
  nc.buckets[idx] = curName
  curName.id = nc.counter
  return curName

proc insert*(nc: NameCache, name: string): Name =
  nc.getName(name, hash(name))

proc remove*(nc: NameCache, name: Name) =
  doAssert(name.id > MaxKeyword)

  let idx = name.h and high(nc.buckets)
  var curName = nc.buckets[idx]
  if curName == name:
    nc.buckets[idx] = curName.next
    return

  while curName != nil:
    if curName.next == name:
      curName.next = name.next
      return
    curName = curName.next

  doAssert(false, "unreachable code or 'Name' not from this cache")

proc resetCounter*(nc: NameCache, limit = NameCounter(MaxKeyword)) =
  nc.counter = limit.int
  for x in nc.buckets:
    if x.isNil: continue
    var curName = x
    while curName != nil:
      if curName.id > limit.int:
        inc nc.counter
        curName.id = nc.counter
        break
      curName = curName.next

proc getCounter*(nc: NameCache): NameCounter =
  NameCounter(nc.counter)

iterator items(nc: NameCache): Name =
  for x in nc.buckets:
    if x.isNil: continue
    var curName = x
    while curName != nil:
      yield curName
      curName = curName.next

proc purge*(nc: NameCache, savePoint: NameCounter) =
  assert(savePoint.int <= nc.counter)
  let size = nc.counter - MaxKeyword
  var names = newSeqOfCap[Name](size)
  for n in nc:
    if n.id > savePoint.int:
      names.add n
  for n in names:
    nc.remove(n)
  nc.resetCounter(savePoint)

# for tables/sets
func hash*(n: Name): Hash = n.h

func `==`*(a, b: Name): bool =
  if a.isNil.not and b.isNil.not:
    return a.id == b.id

func `==`*(a: Keyword, b: Name): bool =
  if b.isNil.not:
    return a.int == b.id

func `==`*(a: Name, b: Keyword): bool =
  if a.isNil.not:
    return a.id == b.int

func toKeyword*(x: Name): Keyword =
  if x.isNil or x.id > MaxKeyword or x.id < 0:
    return kwInvalid
  Keyword(x.id)

proc `$`*(x: Name): string =
  if x.isNil: ":nil" else: x.s

{.pop.}
