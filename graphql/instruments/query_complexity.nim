# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  ../../graphql

{.pragma: ccRaises, raises: [].}

type
  ComplexityCalculator* = proc(qc: QueryComplexity, field: FieldRef): int {.cdecl,
                  gcsafe, ccRaises.}
  QueryComplexity* = ref object of InstrumentRef
    maxComplexity: int
    calculator: ComplexityCalculator

proc traverse(qc: QueryComplexity, fieldSet: FieldSet): int =
  for field in fieldSet:
    inc(result, qc.calculator(qc, field))
    inc(result, qc.traverse(field.fieldSet))

proc queryComplexity(ud: InstrumentRef, flag: InstrumentFlag,
                     params, node: Node): InstrumentResult {.cdecl,
                     gcsafe, ccRaises.} =

  let qc = QueryComplexity(ud)
  let exec = ExecRef(node.sym.exec)
  let total = qc.traverse(exec.fieldSet)
  if total > qc.maxComplexity:
    return err("query complexity exceed max(" & $qc.maxComplexity & "), got " & $total)
  ok()

proc init*(qc: QueryComplexity, calc: ComplexityCalculator, maxComplexity: int) =
  qc.flags.incl iExecBegin
  qc.calculator = calc
  qc.maxComplexity = maxComplexity
  qc.iProc = queryComplexity

proc new*(_: type QueryComplexity, calc: ComplexityCalculator,
          maxComplexity: int): QueryComplexity =
  var qc = QueryComplexity()
  qc.init(calc, maxComplexity)
  qc
