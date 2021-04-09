# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  std/[tables, strutils, macros],
  stew/[results],
  ./common/[ast, ast_helper, errors, names, types]

type
  ContextError* = enum
    ErrNone
    ErrInternal
    ErrDuplicateName
    ErrOnlyOne
    ErrTypeUndefined
    ErrTypeMismatch
    ErrCyclicReference
    ErrDirectiveMisLoc
    ErrNoImpl
    ErrValueError
    ErrNoArg
    ErrArgTypeMismatch
    ErrIncompatType
    ErrNotUsed
    ErrNotPartOf
    ErrNoRoot
    ErrFieldArgUndefined
    ErrFieldNotinArg
    ErrNotNullable
    ErrRequireSelection
    ErrDirArgUndefined
    ErrMergeConflict
    ErrOperationNotFound
    ErrScalarError

  IntrosTypes* = enum
    inQuery      = "__Query"
    inSchema     = "__Schema"
    inType       = "__Type"
    inField      = "__Field"
    inInputValue = "__InputValue"
    inEnumValue  = "__EnumValue"
    inDirective  = "__Directive"
    inTypeKind   = "__TypeKind"
    inDirLoc     = "__DirectiveLocation"
    inInt        = "Int"
    inFloat      = "Float"
    inString     = "String"
    inBoolean    = "Boolean"
    inID         = "ID"
    inSkip       = "skip"
    inInclude    = "include"
    inDeprecated = "deprecated"

  FieldForName* = ref FieldForNameObj
  FieldForNameObj* = object
    respName*  : Node
    field*     : Field
    typ*       : Node
    parentType*: Node
    merged*    : bool
    fieldSet*  : FieldSet

  FieldSet* = seq[FieldForName]

  ExecRef* = ref ExecObj
  ExecObj* = object
    opType*   : Node
    opSym*    : Node
    fieldSet* : FieldSet

  RespResult* = Result[Node, string]

  ResolverProc* = proc(ud: RootRef, params: Args,
    parent: Node): RespResult {.cdecl, gcsafe, raises: [Defect, CatchableError].}

  ResolverSet* = ref ResolverSetObj
  ResolverSetObj* = object
    ud*       : RootRef
    resolvers*: Table[Name, ResolverProc]

  ContextRef* = ref Context

  Context* = object of RootObj
    errKind*      : ContextError
    err*          : ErrorDesc
    opTable*      : Table[Name, Symbol]
    typeTable*    : Table[Name, Symbol]
    scalarTable*  : Table[Name, ScalarRef]
    varTable*     : Table[Name, Node]
    execTable*    : Table[Name, ExecRef]
    resolver*     : Table[Name, ResolverSet]
    names*        : NameCache
    intros*       : array[IntrosTypes, Name]
    emptyNode*    : Node
    rootQuery*    : Node
    rootMutation* : Node
    rootSubs*     : Node
    rootIntros*   : Node

template findType*(name: Name): Symbol =
  ctx.typeTable.getOrDefault(name)

template findOp*(name: Name): Symbol =
  ctx.opTable.getOrDefault(name)

template findScalar*(name: Name): ScalarRef =
  ctx.scalarTable.getOrDefault(name)

macro callValidator*(ctx, validator: untyped): untyped =
  case validator.kind
  of nnkCall:
    validator.insert(1, ctx)
    result = validator
  of nnkIdent:
    result = newCall(validator, ctx)
  else:
    result = validator

template visit*(validator: untyped) =
  callValidator(ctx, validator)
  if ctx.errKind != ErrNone:
    return

template `:=`*(dest: untyped, validator: untyped) =
  let dest {.inject.} = callValidator(ctx, validator)
  if ctx.errKind != ErrNone:
    return

template `::=`*(dest: untyped, validator: untyped) =
  dest = callValidator(ctx, validator)
  if ctx.errKind != ErrNone:
    return

template invalid*(cond: untyped, body: untyped) =
  if cond:
    body
    return

proc fatal*(ctx: ContextRef, err: ContextError, msg: varargs[string, `$`]) =
  ctx.errKind = err
  ctx.err.level = elFatal
  case err
  of ErrOperationNotFound:
    ctx.err.message = "Operation not found: '$1'" % [msg[0]]
  of ErrTypeUndefined:
    ctx.err.message = "Resolver not found: '$1'" % [msg[0]]
  of ErrNoImpl:
    ctx.err.message = "Implementation not found: '$1' of '$2'" % [msg[0], msg[1]]
  of ErrValueError:
    ctx.err.message = "Field '$1' cannot be resolved: \"$2\"" % [msg[0], msg[1]]
  of ErrNotNullable:
    ctx.err.message = "Field '$1' should not return null" % [msg[0]]
  of ErrIncompatType:
    ctx.err.message = "Field '$1' expect '$2' but got '$3'" % [msg[0], msg[1], msg[2]]
  else:
    discard

proc nonEmptyPos(node: Node): Pos =
  if node.kind in NoSonsNodes:
    return node.pos

  for n in node:
    if n.kind != nkEmpty:
      return n.pos

func getArticle(x: string): string =
  const vowels = {'a','A','i','I','e','E','o','O'}
  case x[0]
  of vowels: return "an"
  of 'u', 'U':
    return if x[1] in {'n', 'N'}: "a" else: "an"
  else: return "a"

proc error*(ctx: ContextRef, err: ContextError, node: Node, msg: varargs[string, `$`]) =
  ctx.errKind = err
  ctx.err.pos = node.nonEmptyPos
  ctx.err.level = elError

  case err
  of ErrDuplicateName:
    ctx.err.message = "duplicate name '$1'" % [$node]
  of ErrOnlyOne:
    ctx.err.message = "only one '$1' allowed" % [msg[0]]
  of ErrTypeUndefined:
    ctx.err.message = "type not defined '$1'" % [$node]
  of ErrTypeMismatch:
    let typ = msg[0]
    let an = getArticle(typ)
    ctx.err.message = "'$1' is $2 '$3', expect '$4'" % [$node, an, typ, msg[1]]
  of ErrCyclicReference:
    ctx.err.message = "cyclic reference detected for '$1'"  % [$node]
  of ErrDirectiveMisLoc:
    ctx.err.message = "directive '$1' doesn't specify '$2' location"  % [$node, msg[0]]
  of ErrNoImpl:
    ctx.err.message = "no '$2' '$1' implementation found" % [$node, msg[0]]
  of ErrValueError:
    ctx.err.message = "the value of '$1' can't be '$2'" % [$node, msg[0]]
  of ErrNoArg:
    ctx.err.message = "field '$1' need argument '$2'" % [$node, msg[0]]
  of ErrArgTypeMismatch:
    ctx.err.message = "arg '$1' of field '$2' type mismatch with '$3'" % [$node, msg[0], msg[1]]
  of ErrIncompatType:
    ctx.err.message = "'$1' has incompatible type with '$2'" % [$node, msg[0]]
  of ErrNotUsed:
    ctx.err.message = "'$1' is not used" % [$node]
  of ErrNotPartOf:
    ctx.err.message = "'$1' is not part of '$2'" % [$node, msg[0]]
  of ErrNoRoot:
    ctx.err.message = "no root operation '$1' available" % [msg[0]]
  of ErrFieldArgUndefined:
    ctx.err.message = "arg '$1' not defined in field '$2' of '$3'" % [$node, msg[0], msg[1]]
  of ErrFieldNotinArg:
    ctx.err.message = "field '$1' of arg '$2' should not empty" % [msg[0], $node]
  of ErrNotNullable:
    ctx.err.message = "$1 '$2' should not nullable" % [msg[0], $node]
  of ErrRequireSelection:
    ctx.err.message = "field '$1' return type is '$2' requires selection set" % [$node, msg[0]]
  of ErrDirArgUndefined:
    ctx.err.message = "arg '$1' not defined in directive '$2'" % [$node, msg[0]]
  of ErrMergeConflict:
    ctx.err.message = "field '$1' have merge conflict: $2" % [$node, msg[0]]
  of ErrScalarError:
    ctx.err.message = "scalar '$1': $2" % [$node, msg[0]]
  else:
    discard

proc getScalar*(ctx: ContextRef, locType: Node): ScalarRef =
  if locType.sym.scalar.isNil:
    let scalar = findScalar(locType.sym.name)
    invalid scalar.isNil:
      ctx.error(ErrNoImpl, locType, "scalar")
    locType.sym.scalar = scalar
    scalar
  else:
    locType.sym.scalar
