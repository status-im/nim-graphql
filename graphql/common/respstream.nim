# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  faststreams/outputs

{.pragma: respPragma, gcsafe, raises: [Defect, CatchableError].}

type
  simpleProc   = proc (x: RootRef) {.respPragma.}
  stringProc   = proc (x: RootRef, v: string) {.respPragma.}
  boolProc     = proc (x: RootRef, v: bool) {.respPragma.}
  intProc      = proc (x: RootRef, v: int) {.respPragma.}
  floatProc    = proc (x: RootRef, v: float64) {.respPragma.}
  bytesProc    = proc (x: RootRef, v: openArray[byte]) {.respPragma.}
  outputSProc  = proc (x: RootRef): string {.respPragma.}
  outputBProc  = proc (x: RootRef): seq[byte] {.respPragma.}

  RespStream* = ref RespStreamObj
  RespStreamObj* = object
    obj: RootRef
    beginListP: simpleProc
    endListP: simpleProc
    beginMapP: simpleProc
    endMapP: simpleProc
    fieldNameP: stringProc
    writeStringP: stringProc
    writeBoolP: boolProc
    writeIntP: intProc
    writeNullP: simpleProc
    writeBytesP: bytesProc
    writeFloatP: floatProc
    getStringP: outputSProc
    getBytesP: outputBProc

proc beginListImpl[T](x: RootRef) =
  mixin beginList
  beginList(T(x))

proc endListImpl[T](x: RootRef) =
  mixin endList
  endList(T(x))

proc beginMapImpl[T](x: RootRef) =
  mixin beginMap
  beginMap(T(x))

proc endMapImpl[T](x: RootRef) =
  mixin endMap
  endMap(T(x))

proc writeStringImpl[T](x: RootRef, v: string) =
  mixin writeString
  writeString(T(x), v)

proc writeBoolImpl[T](x: RootRef, v: bool) =
  mixin writeBool
  writeBool(T(x), v)

proc writeIntImpl[T](x: RootRef, v: int) =
  mixin writeInt
  writeInt(T(x), v)

proc writeFloatImpl[T](x: RootRef, v: float64) =
  mixin writeFloat
  writeFloat(T(x), v)

proc writeNullImpl[T](x: RootRef) =
  mixin writeNull
  writeNull(T(x))

proc writeBytesImpl[T](x: RootRef, raw: openArray[byte]) =
  mixin writeBytes
  writeBytes(T(x), raw)

proc fieldNameImpl[T](x: RootRef, v: string) =
  mixin fieldName
  fieldName(T(x), v)

proc getStringImpl[T](x: RootRef): string =
  mixin getString
  getString(T(x))

proc getBytesImpl[T](x: RootRef): seq[byte] =
  mixin getBytes
  getBytes(T(x))

proc respStream*[T: RootRef](x: T): RespStream =
  mixin beginList, endList, beginMap, endMap
  mixin writeString, writeBool
  mixin writeInt, writeNull, writeFloat

  new result
  result.obj = x
  result.beginListP     = beginListImpl[T]
  result.endListP       = endListImpl[T]
  result.beginMapP      = beginMapImpl[T]
  result.endMapP        = endMapImpl[T]
  result.fieldNameP     = fieldNameImpl[T]
  result.writeStringP   = writeStringImpl[T]
  result.writeBoolP     = writeBoolImpl[T]
  result.writeIntP      = writeIntImpl[T]
  result.writeNullP     = writeNullImpl[T]
  result.writeBytesP    = writeBytesImpl[T]
  result.writeFloatP    = writeFloatImpl[T]
  result.getStringP     = getStringImpl[T]
  result.getBytesP      = getBytesImpl[T]

proc beginList*(x: RespStream) =
  x.beginListP(x.obj)

proc endList*(x: RespStream) =
  x.endListP(x.obj)

proc beginMap*(x: RespStream) =
  x.beginMapP(x.obj)

proc endMap*(x: RespStream) =
  x.endMapP(x.obj)

proc fieldName*(x: RespStream, v: string) =
  x.fieldNameP(x.obj, v)

proc write*(x: RespStream, v: string) =
  x.writeStringP(x.obj, v)

proc write*(x: RespStream, v: bool) =
  x.writeBoolP(x.obj, v)

proc write*(x: RespStream, v: int) =
  x.writeIntP(x.obj, v)

proc write*(x: RespStream, v: float64) =
  x.writeFloatP(x.obj, v)

proc writeNull*(x: RespStream) =
  x.writeNullP(x.obj)

proc write*(x: RespStream, raw: openArray[byte]) =
  x.writeBytesP(x.obj, raw)
  
proc getString*(x: RespStream): string =
  x.getStringP(x.obj)

proc getBytes*(x: RespStream): seq[byte] =
  x.getBytesP(x.obj)

template respMap*(x: RespStream, body: untyped) =
  beginMap(x)
  body
  endMap(x)

template respList*(x: RespStream, body: untyped) =
  beginList(x)
  body
  endList(x)
