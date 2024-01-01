# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  faststreams/[outputs, textio],
  ../common/[respstream, ast],
  ../private/utf

export respstream

type
  State = enum
    StateTop
    StateBeginList
    StateList
    StateBeginMap
    StateMap

  JsonRespStream* = ref object of RootRef
    stream: OutputStream
    stack: seq[State]
    doubleEscape: bool
    escapeUnicode: bool

{.push gcsafe, raises: [IOError] .}

template top(x: seq[State]): State =
  x[^1]

template top(x: seq[State], s: State) =
  x[^1] = s

template append(s: untyped) =
  x.stream.write s

proc writeSeparator(x: JsonRespStream) =
  let top = x.stack.top
  case top
  of StateList:
    append ','
  of StateBeginList:
    x.stack.top(StateList)
  else: discard

proc beginList*(x: JsonRespStream) =
  writeSeparator(x)
  append '['
  x.stack.add StateBeginList

proc endList*(x: JsonRespStream) =
  discard x.stack.pop
  append ']'

proc beginMap*(x: JsonRespStream) =
  writeSeparator(x)
  append '{'
  x.stack.add StateBeginMap

proc endMap*(x: JsonRespStream) =
  discard x.stack.pop
  append '}'

proc write*(x: JsonRespStream, v: string) =
  writeSeparator(x)
  if x.doubleEscape:
    append "\\\""
  else:
    append '\"'

  template addPrefixSlash(c) =
    if x.doubleEscape:
      append '\\'
    append '\\'
    append c

  template writeChar(c: char) =
    case c
    of '\L': addPrefixSlash 'n'
    of '\b': addPrefixSlash 'b'
    of '\f': addPrefixSlash 'f'
    of '\t': addPrefixSlash 't'
    of '\r': addPrefixSlash 'r'
    of '"' : addPrefixSlash '\"'
    of '\0'..'\7':
      if x.doubleEscape:
        append '\\'
      append "\\u000"
      append char(ord('0') + ord(c))
    of '\14'..'\31':
      if x.doubleEscape:
        append '\\'
      append "\\u00"
      x.stream.writeHex([c])
    of '\\': addPrefixSlash '\\'
    else: append c

  if x.escapeUnicode:
    for c in Utf8.codePoints(v):
      if c >= 0x80:
        let p = Utf16.toPair(c)
        if p.state == Utf16One:
          append "\\u"
          x.stream.writeHex([char(p.cp shr 8), char(p.cp and 0xFF)])
        elif p.state == Utf16Two:
          append "\\u"
          x.stream.writeHex([char(p.hi shr 8), char(p.hi and 0xFF)])
          append "\\u"
          x.stream.writeHex([char(p.lo shr 8), char(p.lo and 0xFF)])
      else:
        let cc = c.char
        writeChar(cc)
  else:
    for c in v:
      writeChar(c)

  if x.doubleEscape:
    append "\\\""
  else:
    append '\"'

proc writeRaw*(x: JsonRespStream, v: string) =
  writeSeparator(x)
  x.stream.write(v)

proc write*(x: JsonRespStream, v: bool) =
  writeSeparator(x)
  if v:
    append "true"
  else:
    append "false"

proc write*(x: JsonRespStream, v: int) =
  writeSeparator(x)
  x.stream.writeText int64(v)

proc write*(x: JsonRespStream, v: float64) =
  writeSeparator(x)
  # TODO: implement write float
  append $v

proc writeNull*(x: JsonRespStream) =
  writeSeparator(x)
  append "null"

proc field*(x: JsonRespStream, v: string){.gcsafe, raises: [IOError].} =
  let top = x.stack.top
  if x.doubleEscape:
    case top
    of StateMap:
      append ",\\\""
      append v
      append "\\\":"
    of StateBeginMap:
      append "\\\""
      append v
      append "\\\":"
      x.stack.top(StateMap)
    else:
      doAssert(false)
    return

  case top
  of StateMap:
    append ','
    append '\"'
    append v
    append '\"'
    append ':'
  of StateBeginMap:
    append '\"'
    append v
    append '\"'
    append ':'
    x.stack.top(StateMap)
  else:
    doAssert(false)

proc serialize*(resp: JsonRespStream, n: Node) =
  case n.kind
  of nkNull:
    resp.writeNull
  of nkBoolean:
    resp.write(n.boolVal)
  of nkInt:
    # no preprocessing
    resp.writeRaw(n.intVal)
  of nkFloat:
    # no preprocessing
    resp.writeRaw(n.floatVal)
  of nkString:
    resp.write(n.stringVal)
  of nkList:
    resp.beginList()
    for x in n:
      serialize(resp, x)
    resp.endList()
  of nkMap:
    resp.beginMap()
    for k, v in n.mapPair:
      resp.field(k)
      serialize(resp, v)
    resp.endMap()
  else:
    doAssert(false, $n.kind & " should not appear in resp stream")

proc write*(x: JsonRespStream, v: openArray[byte]) =
  x.stream.write(v)

proc getString*(x: JsonRespStream): string {.gcsafe, raises:[].} =
  x.stream.getOutput(string)

proc getBytes*(x: JsonRespStream): seq[byte] {.gcsafe, raises:[].} =
  x.stream.getOutput(seq[byte])

proc len*(x: JsonRespStream): int {.gcsafe, raises:[].} =
  x.stream.pos()

proc init*(v: JsonRespStream,
           doubleEscape: bool = false,
           escapeUnicode: bool = false) {.gcsafe, raises:[].} =
  v.stream = memoryOutput()
  v.stack = @[StateTop]
  v.doubleEscape = doubleEscape
  v.escapeUnicode = escapeUnicode

proc new*(_: type JsonRespStream,
          doubleEscape: bool = false,
          escapeUnicode: bool = false): JsonRespStream {.gcsafe, raises: [].} =
  let v = JsonRespStream()
  v.init(doubleEscape, escapeUnicode)
  v

{.pop.}
