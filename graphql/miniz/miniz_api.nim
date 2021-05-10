# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import strutils
from os import quoteShell, DirSep, AltSep

const
  minizPath = currentSourcePath.rsplit({DirSep, AltSep}, 1)[0]

{.passC: "-I" & quoteShell(minizPath).}
{.passC: "-D_LARGEFILE64_SOURCE=1".}
{.compile: minizPath & "/" & "miniz.c".}

type
  MzError* {.size: sizeof(cint).} = enum
    MZ_PARAM_ERROR   = -10000
    MZ_VERSION_ERROR = -6
    MZ_BUF_ERROR     = -5
    MZ_MEM_ERROR     = -4
    MZ_DATA_ERROR    = -3
    MZ_STREAM_ERROR  = -2
    MZ_ERRNO         = -1
    MZ_OK            = 0
    MZ_STREAM_END    = 1
    MZ_NEED_DICT     = 2

  MzLevel* {.size: sizeof(cint).} = enum
    MZ_DEFAULT_COMPRESSION  = -1
    MZ_NO_COMPRESSION       = 0
    MZ_BEST_SPEED           = 1
    MZ_DEFAULT_LEVEL        = 6
    MZ_BEST_COMPRESSION     = 9
    MZ_UBER_COMPRESSION     = 10

  MzMethod* {.size: sizeof(cint).} = enum
    MZ_DEFLATED = 8

  MzWindowBits* {.size: sizeof(cint).} = enum
    MZ_RAW_DEFLATE         = -15
    MZ_DEFAULT_WINDOW_BITS = 15

  MzStrategy* {.size: sizeof(cint).} = enum
    MZ_DEFAULT_STRATEGY = 0
    MZ_FILTERED         = 1
    MZ_HUFFMAN_ONLY     = 2
    MZ_RLE              = 3
    MZ_FIXED            = 4

  MzFlush* {.size: sizeof(cint).} = enum
    MZ_NO_FLUSH      = 0
    MZ_PARTIAL_FLUSH = 1
    MZ_SYNC_FLUSH    = 2
    MZ_FULL_FLUSH    = 3
    MZ_FINISH        = 4
    MZ_BLOCK         = 5

  MzStream {.importc: "mz_stream", header: "miniz.h".} = object
    next_in*   : ptr cuchar  # pointer to next byte to read
    avail_in*  : cuint    # number of bytes available at next_in
    total_in   : culong   # total number of bytes consumed so far

    next_out*  : ptr cuchar # pointer to next byte to write
    avail_out* : cuint    # number of bytes that can be written to next_out
    total_out  : culong   # total number of bytes produced so far

proc deflateInit2*(mz: var MzStream, level: MzLevel, meth: MzMethod,
                  windowBits: MzWindowBits, memLevel: cint,
                  strategy: MzStrategy): MzError {.cdecl, importc: "mz_deflateInit2", header: "miniz.h".}

proc deflate*(mz: var MzStream, flush: MzFlush): MzError {.cdecl, importc: "mz_deflate", header: "miniz.h".}

proc deflateBound*(mz: var MzStream, sourceLen: culong): culong {.cdecl, importc: "mz_deflateBound", header: "miniz.h".}

proc deflateEnd*(mz: var MzStream): MzError {.cdecl, importc: "mz_deflateEnd", header: "miniz.h".}

const
  MZ_CRC32_INIT* = 0.culong

proc mz_crc32*(crc: culong, buf: ptr cuchar, buf_len: csize_t): culong {.cdecl, importc: "mz_crc32", header: "miniz.h".}

func mz_crc32*[T: byte|char](input: openArray[T]): culong =
  mz_crc32(MZ_CRC32_INIT,
    cast[ptr cuchar](input[0].unsafeAddr),
    input.len.csize_t
  ).culong

proc gzip*(source: string): string =
  # all these cast[ptr cuchar] is need because
  # clang++ will complaints about incompatible
  # pointer types
  var mz = MzStream(
    next_in: cast[ptr cuchar](source[0].unsafeAddr),
    avail_in: source.len.cuint
  )

  assert(mz.deflateInit2(
    MZ_DEFAULT_LEVEL,
    MZ_DEFLATED,
    MZ_RAW_DEFLATE,
    1,
    MZ_DEFAULT_STRATEGY) == MZ_OK
  )

  let maxSize = mz.deflateBound(source.len.culong).int
  result = newString(maxSize + 18)

  result[0] = 0x1F.char
  result[1] = 0x8B.char
  result[2] = 8.char
  result[3] = 0.char
  result[4] = 0.char
  result[5] = 0.char
  result[6] = 0.char
  result[7] = 0.char
  result[8] = 0.char
  result[9] = 0xFF.char

  mz.next_out = cast[ptr cuchar](result[10].addr)
  mz.avail_out = (result.len - 10).cuint
  assert(mz.deflate(MZ_FINISH) == MZ_STREAM_END)

  let
    size  = mz.total_out.int
    crc   = mz_crc32(source)
    ssize = source.len

  result[size + 10] = char(         crc and 0xFF)
  result[size + 11] = char((crc shr 8)  and 0xFF)
  result[size + 12] = char((crc shr 16) and 0xFF)
  result[size + 13] = char((crc shr 24) and 0xFF)
  result[size + 14] = char(         ssize and 0xFF)
  result[size + 15] = char((ssize shr 8)  and 0xFF)
  result[size + 16] = char((ssize shr 16) and 0xFF)
  result[size + 17] = char((ssize shr 24) and 0xFF)

  result.setLen(mz.total_out.int + 18)
  assert(mz.deflateEnd() == MZ_OK)
