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

{.pragma: respPragma, gcsafe, raises: [Defect, CatchableError].}

type
  serializeProc = proc(x: RootRef, n: Node) {.respPragma.}

  RespStream* = ref RespStreamObj
  RespStreamObj* = object
    obj: RootRef
    serializeP: serializeProc

proc serializeImpl[T](x: RootRef, n: Node) =
  mixin serialize
  serialize(T(x), n)

proc respStream*[T: RootRef](x: T): RespStream =
  mixin serialize
  new result
  result.obj = x
  result.serializeP = serializeImpl[T]

proc serialize*(x: RespStream, n: Node) =
  x.serializeP(x.obj, n)

proc to*(x: RespStream, T: type): T =
  T(x.obj)

template respMap*(x, body: untyped) =
  beginMap(x)
  body
  endMap(x)

template respList*(x, body: untyped) =
  beginList(x)
  body
  endList(x)
