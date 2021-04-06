# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  ./ast

type
  InputObject* = distinct Node
  InputFields* = distinct Node
  InputField* = distinct Node
  Arguments* = distinct Node
  Argument* = distinct Node
  Directive* = distinct Node
  Interface* = distinct Node
  Object* = distinct Node
  ObjectFields* = distinct Node
  ObjectField* =  distinct Node
  Enum* = distinct Node
  EnumVals* = distinct Node
  EnumVal* = distinct Node
  Union* = distinct Node
  Scalar* = distinct Node
  Schema* = distinct Node
  Variables* = distinct Node
  Variable* = distinct Node
  Query* = distinct Node
  Mutation* = distinct Node
  Subscription* = distinct Node
  Fragment* = distinct Node
  InlineFragment* = distinct Node
  Field* =  distinct Node
  Args* = distinct Node
  Arg* = distinct Node
  FragmentSpread* = distinct Node
  Dir* = distinct Node
  Dirs* = distinct Node

  Types* = Directive | InputObject | Enum | Union | Interface | Object | Scalar

func desc*(n: Types): Node = Node(n)[0]
func name*(n: Types): Node = Node(n)[1]
func dirs*(n: InputObject): Dirs = Dirs(Node(n)[2])
func fields*(n: InputObject): InputFields =
  InputFields(Node(n)[3])

iterator items*(n: InputFields): InputField =
  for x in Node(n):
    yield InputField(x)

iterator items*(n: Arguments): Argument =
  for x in Node(n):
    yield Argument(x)

func typ*(n: Argument | InputField): Node = Node(n)[2]
func defVal*(n: Argument | InputField): Node = Node(n)[3]
func repeatable*(n: Directive): Node = Node(n)[3]
func locs*(n: Directive): Node = Node(n)[4]
func implements*(n: Interface | Object): Node = Node(n)[2]
func dirs*(n: Interface | Object): Dirs = Dirs(Node(n)[3])
func fields*(n: Interface | Object): ObjectFields =
  ObjectFields(Node(n)[4])

iterator items*(n: ObjectFields): ObjectField =
  for x in Node(n):
    yield ObjectField(x)

func desc*(n: ObjectField | EnumVal | Argument | InputField): Node = Node(n)[0]
func name*(n: ObjectField | EnumVal | Argument | InputField): Node = Node(n)[1]
func args*(n: ObjectField | Directive): Arguments = Arguments(Node(n)[2])
func typ*(n: ObjectField): Node = Node(n)[3]
func dirs*(n: ObjectField | Argument | InputField): Dirs = Dirs(Node(n)[4])
func values*(n: Enum): EnumVals = EnumVals(Node(n)[3])

iterator items*(n: EnumVals): EnumVal =
  for x in Node(n):
    yield EnumVal(x)

func members*(n: Union | Schema): Node = Node(n)[3]
func dirs*(n: Scalar | Schema | Union | EnumVal | Enum): Dirs = Dirs(Node(n)[2])

iterator items*(n: Variables): Variable =
  for x in Node(n):
    yield Variable(x)

func name*(n: Query | Mutation | Subscription | Fragment | Variable | FragmentSpread): Node = Node(n)[0]
func vars*(n: Query | Mutation | Subscription | Fragment): Variables = Variables(Node(n)[1])
func dirs*(n: Query | Mutation | Subscription): Dirs = Dirs(Node(n)[2])
func sels*(n: Query | Mutation | Subscription): Node = Node(n)[3]

func typeCond*(n: Fragment): Node = Node(n)[2]
func dirs*(n: Fragment): Dirs = Dirs(Node(n)[3])
func sels*(n: Fragment): Node = Node(n)[4]

func typ*(n: Variable): Node = Node(n)[1]
func defVal*(n: Variable): Node = Node(n)[2]
func dirs*(n: Variable): Dirs = Dirs(Node(n)[3])

func typeCond*(n: InlineFragment): Node = Node(n)[0]
func dirs*(n: InlineFragment | FragmentSpread): Dirs = Dirs(Node(n)[1])
func sels*(n: InlineFragment): Node = Node(n)[2]

func alias*(n: Field): Node = Node(n)[0]
func name*(n: Field): Node = Node(n)[1]
func args*(n: Field): Args = Args(Node(n)[2])
func dirs*(n: Field): Dirs = Dirs(Node(n)[3])
func sels*(n: Field): Node = Node(n)[4]

iterator items*(n: Args): Arg =
  for x in Node(n):
    yield Arg(x)

func name*(n: Arg): Node = Node(n)[0]
func val*(n: Arg): Node = Node(n)[1]
func `[]`*(n: Args, i: int): Arg = Arg(Node(n)[i])

iterator items*(n: Dirs): Dir =
  for x in Node(n):
    yield Dir(x)

func name*(n: Dir): Node = Node(n)[0]
func args*(n: Dir): Args = Args(Node(n)[1])

proc findArg*(name: Node, args: Args): Arg =
  for arg in args:
    if arg.name.name == name.name:
      return arg
  return Arg(nil)

proc findArg*(name: Node, args: Arguments): Node =
  for arg in args:
    if arg.name.name == name.name:
      return arg.typ
  return nil
