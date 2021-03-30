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
  ../common/respstream

export respstream

type
  State = enum
    StateTop
    StateBeginList
    StateList
    StateBeginMap
    StateMap
    StateBeginInlineMap
    StateInlineMap

  TomlRespStream* = ref object of RootRef
    stream: OutputStream
    stack: seq[State]
    fieldName: string

template top(x: seq[State]): State =
  x[^1]

template top(x: seq[State], s: State) =
  x[^1] = s

template append(s: untyped) =
  x.stream.write s

proc beginList*(x: TomlRespStream) =
  case x.stack.top
  of StateTop:
    append x.fieldName
    append " = ["
  of StateBeginInlineMap:
    append x.fieldName
    append " = ["
    x.stack.top(StateInlineMap)
  of StateInlineMap:
    append ", "
    append x.fieldName
    append " = ["
  of StateBeginMap:
    append "  "
    append x.fieldName
    append " = ["
    x.stack.top(StateMap)
  of StateMap:
    append "  "
    append x.fieldName
    append " = ["
  of StateList:
    append ", ["
  of StateBeginList:
    append '['
    x.stack.top(StateList)
  x.stack.add StateBeginList

proc endList*(x: TomlRespStream) =
  discard x.stack.pop
  append ']'
  if x.stack.len <= 2:
    append '\n'

proc beginMap*(x: TomlRespStream) =
  let top = x.stack.top
  case top
  of StateTop:
    append '['
    append x.fieldName
    append "]\n"
  of StateBeginMap:
    append "  "
    append x.fieldName
    append " = {"
    x.stack.top(StateMap)
  of StateMap:
    append "  "
    append x.fieldName
    append " = {"
  of StateList:
    append ", {"
  of StateInlineMap:
    append ", "
    append x.fieldName
    append " = {"
  of StateBeginList:
    append '{'
    x.stack.top(StateList)
  of StateBeginInlineMap:
    append '{'
    x.stack.top(StateInlineMap)

  if top == StateTop:
    x.stack.add StateBeginMap
  else:
    x.stack.add StateBeginInlineMap

proc endMap*(x: TomlRespStream) =
  let top = x.stack.pop
  if top == StateInlineMap:
    append '}'
    if x.stack.len == 2:
      append '\n'
  else:
    append '\n'

proc writeSeparator(x: TomlRespStream) =
  let top = x.stack.top
  case top
  of StateBeginList:
    x.stack.top(StateList)
  of StateList:
    append ','
    append ' '
  of StateInlineMap:
    append ','
    append ' '
    append x.fieldName
    append " = "
  of StateMap:
    append "  "
    append x.fieldName
    append " = "
  of StateTop:
    append x.fieldName
    append " = "
  of StateBeginMap:
    x.stack.top(StateMap)
    append "  "
    append x.fieldName
    append " = "
  of StateBeginInlineMap:
    x.stack.top(StateInlineMap)
    append x.fieldName
    append " = "
  x.fieldName.setLen(0)

proc writeEOL(x: TomlRespStream) =
  if x.stack.top in {StateMap, StateTop}:
    append '\n'

proc writeString*(x: TomlRespStream, v: string) =
  writeSeparator(x)
  append '\"'

  template addPrefixSlash(c) =
    append '\\'
    append c

  for c in v:
    case c
    of '\L': addPrefixSlash 'n'
    of '\b': addPrefixSlash 'b'
    of '\f': addPrefixSlash 'f'
    of '\t': addPrefixSlash 't'
    of '\r': addPrefixSlash 'r'
    of '"' : addPrefixSlash '\"'
    of '\0'..'\7':
      append "\\u000"
      append char(ord('0') + ord(c))
    of '\14'..'\31':
      append "\\u00"
      x.stream.writeHex([c])
    of '\\': addPrefixSlash '\\'
    else: append c

  append '\"'
  writeEOL(x)

proc writeBool*(x: TomlRespStream, v: bool) =
  writeSeparator(x)
  if v:
    append "true"
  else:
    append "false"
  writeEOL(x)

proc writeInt*(x: TomlRespStream, v: int) =
  writeSeparator(x)
  x.stream.writeText int64(v)
  writeEOL(x)

proc writeFloat*(x: TomlRespStream, v: float64) =
  writeSeparator(x)
  # TODO: implement write float
  append $v
  writeEOL(x)

proc writeNull*(x: TomlRespStream) =
  # really, just do nothing
  discard

proc fieldName*(x: TomlRespStream, v: string) =
  x.fieldName = v

proc getOutput*(x: TomlRespStream): string =
  x.stream.getOutput(string)

proc newTomlRespStream*(): RespStream =
  let v = TomlRespStream(
    stream: memoryOutput(),
    stack: @[StateTop]
  )
  respStream(v)
