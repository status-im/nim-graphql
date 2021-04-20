# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

from algorithm import reverse

const
  MIN_BASE = 2
  MAX_BASE = 36

type
  Conv = object
    intToChar: array[MAX_BASE, char]
    charToInt: array[256, int]

proc init(_: type Conv): Conv =
  for i in 0..<10:
    result.intToChar[i] = char('0'.int + i)
    result.charToInt[result.intToChar[i].int] = i

  for i in 0..<26:
    result.intToChar[i+10] = char('a'.int + i)
    result.charToInt['a'.int + i] = i + 10
    result.charToInt['A'.int + i] = i + 10

const conv = Conv.init()

# Adds two numbers using long addition.
proc add(a, b: string, base = 10): string =
  if base > MAX_BASE or base < MIN_BASE: return ""

  # Reserve storage for the result.
  result = newStringOfCap(1 + max(a.len, b.len))

  # Column positions and carry flag.
  var
    apos = a.len
    bpos = b.len
    carry = 0

  # Do long arithmetic.
  while carry > 0 or apos > 0 or bpos > 0:
    if apos > 0:
      dec apos
      carry += conv.charToInt[a[apos].int]
    if bpos > 0:
      dec bpos
      carry += conv.charToInt[b[bpos].int]

    result.add(conv.intToChar[carry mod base])
    carry = carry div base

  # The result string is backwards.  Reverse and return it.
  result.reverse()

# Converts a single value to some base, intended for single-digit conversions.
proc asBase(number, base: int): string =
  var number = number
  if  number <= 0: return "0"
  while number > 0:
    result.add conv.intToChar[number mod base]
    number = number div base
  result.reverse()

# Converts a number from one base to another.
proc convertBase*(number: string, oldBase, newBase: int): string =
  for digit in number:
    let value = conv.charToInt[digit.int]
    if result.len == 0:
      result = asBase(value, newBase)
    else:
      var temp = result
      for i in 1..<oldBase:
        temp = add(result, temp, newBase)
      result = add(temp, asBase(value, newBase), newBase)
