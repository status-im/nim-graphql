import
  std/[times, strutils, options, os],
  std/[math, sequtils, random],
  json_serialization,
  json_serialization/std/options as jsopt

type
  UUID = distinct string
  Tnull = distinct int

  State* {.pure.} = enum
    failed  = "failed"
    passed  = "passed"
    skipped = "skipped"
    pending = "pending"

  Speed = enum
    fast = "fast"
    slow = "slow"

  ErrObj = object
    message: Option[string]
    estack : Option[string]
    diff   : Option[string]

  TestRef* = ref Test
  Test = object
    title     : string
    fullTitle : string
    timedOut  : bool
    duration  : int64
    state     : State
    speed     : Speed
    pass      : bool
    fail      : bool
    pending   : bool
    context   : Tnull
    code      : string
    err       : ErrObj
    uuid      : UUID
    parentUUID: UUID
    isHook    : bool
    skipped   : bool

  Empty = object
  SuiteRef = ref Suite
  Suite = object
    uuid       : UUID
    title      : string
    fullFile   : string
    file       : string
    beforeHooks: seq[Empty]
    afterHooks : seq[Empty]
    tests      : seq[TestRef]
    suites     : seq[SuiteRef]
    passes     : seq[UUID]
    failures   : seq[UUID]
    pending    : seq[UUID]
    skipped    : seq[UUID]
    duration   : int64
    root       : bool
    rootEmpty  : bool
    timeout {.serializedFieldName("_timeout").} : int

  Statistic = object
    suites   : int
    tests    : int
    passes   : int
    pending  : int
    failures : int
    startTime {.serializedFieldName("start").} : DateTime
    endTime   {.serializedFieldName("end").}   : DateTime
    duration : int64
    testsRegistered: int
    passPercent    : int
    pendingPercent : int
    other          : int
    hasOther       : bool
    skipped        : int
    hasSkipped     : bool

  Mocha* = object
    stats  : Statistic
    results: seq[SuiteRef]

const pattern = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"

proc generateUUID(): UUID =
  # taken from https://github.com/yglukhov/nim-only-uuid
  var d = toInt(epochTime() * 100000)
  proc fn(c : char): string =
    var r = toInt(toFloat(d) + rand(1.0) * 16) %% 16
    d = toInt(floor(toFloat(d) / 16))
    toHex(if c == 'x': r else: r and 0x3 or 0x8, 1)
  toLowerAscii(join(pattern.mapIt(if it == 'x' or it == 'y': fn(it) else: $it))).UUID

proc `$`(u: UUID): string =
  u.string

proc newSuite*(title, fullFile: string): SuiteRef =
  let (_, name) = fullFile.splitPath()
  var suite = SuiteRef(
    uuid       : generateUUID(),
    title      : title,
    fullFile   : fullFile,
    file       : name,
    timeout    : 2000
  )
  suite

proc add*(s, suite: SuiteRef) =
  s.suites.add suite
  s.duration += suite.duration

proc add*(s: SuiteRef, t: TestRef) =
  t.parentUUID = s.uuid
  s.tests.add t
  s.duration += t.duration
  if t.pass:
    s.passes.add t.uuid
  if t.fail:
    s.failures.add t.uuid
  if t.skipped:
    s.skipped.add t.uuid

proc newTest*(title, fullTitle: string): TestRef =
  var t = TestRef(
    title     : title,
    fullTitle : fullTitle,
    uuid      : generateUUID(),
    duration  : getTime().toWinTime()
  )
  t

proc setCode*(t: TestRef, code: string) =
  t.code = code

template calcDuration() =
  t.duration = (getTime().toWinTime() - t.duration) div 1_000_000_000_000_000_00'i64

proc setPass*(t: TestRef) =
  calcDuration()
  t.state = State.passed
  t.pass = true

proc setSkip*(t: TestRef) =
  calcDuration()
  t.state = State.skipped
  t.skipped = true

proc setFail*(t: TestRef, msg: string, estack = "", diff = "") =
  calcDuration()
  t.state = State.failed
  t.fail = true
  t.err.message = some(msg)
  if estack.len > 0:
    t.err.estack = some(estack)
  if diff.len > 0:
    t.err.diff = some(diff)

proc setExpect*(t: TestRef, msg: string, expected, actual: string) =
  calcDuration()
  if expected != actual:
    t.state = State.failed
    t.fail = true
    t.err.message = some(msg)
    t.err.diff = some("- $1\n+ $2\n" % [actual, expected])
  else:
    t.state = State.passed
    t.pass = true

proc setExpect*(t: TestRef, msg: string, expected, actual: int) =
  calcDuration()
  if expected != actual:
    t.state = State.failed
    t.fail = true
    t.err.message = some(msg)
    t.err.diff = some("- $1\n+ $2\n" % [$actual, $expected])
  else:
    t.state = State.passed
    t.pass = true

proc setExpectErr*(t: TestRef, msg: string, expected, actual: string) =
  calcDuration()
  if expected != actual:
    t.state = State.failed
    t.fail = true
    t.err.message = some(msg)
    t.err.diff = some("- $1\n+ $2\n" % [actual, expected])
  else:
    t.state = State.passed
    t.pass = true
    t.err.estack = some(actual)

proc init*(_: type Mocha): Mocha =
  result.stats.startTime = now().utc

proc add*(m: var Mocha, suite: SuiteRef) =
  m.results.add suite

proc numTests(s: SuiteRef): int =
  for x in s.suites:
    result += x.numTests()
  result += s.tests.len

proc totalDuration(s: SuiteRef): int64 =
  for x in s.suites:
    result += x.totalDuration()
  result += s.duration

proc numPass(s: SuiteRef): int =
  for x in s.suites:
    result += x.numPass()
  for n in s.tests:
    if n.pass:
      inc result

proc numFail(s: SuiteRef): int =
  for x in s.suites:
    result += x.numFail()
  for n in s.tests:
    if n.fail:
      inc result

proc numSkip(s: SuiteRef): int =
  for x in s.suites:
    result += x.numSkip()
  for n in s.tests:
    if n.skipped:
      inc result

proc writeValue(writer: var JsonWriter, value: TNull) =
  writer.writeValue JsonString("null")

proc writeValue(writer: var JsonWriter, value: UUID) =
  writer.writeValue $value

proc writeValue(writer: var JsonWriter, value: Empty) =
  writer.writeValue ""

proc writeValue(writer: var JsonWriter, value: DateTime) =
  writer.writeValue $value

proc writeValue(writer: var JsonWriter, value: State) =
  writer.writeValue $value

proc writeValue(writer: var JsonWriter, value: Speed) =
  writer.writeValue $value

proc finalize*(m: var Mocha, fileName: string) =
  m.stats.endTime = now().utc
  m.stats.suites = m.results.len
  for x in m.results:
    m.stats.tests    += x.numTests()
    m.stats.duration += x.totalDuration()
    m.stats.passes   += x.numPass()
    m.stats.failures += x.numFail()
    m.stats.skipped  += x.numSkip()

  m.stats.testsRegistered = m.stats.tests
  m.stats.hasSkipped = m.stats.skipped > 0
  m.stats.passPercent = int((float(m.stats.passes) / float(m.stats.tests)) * 100.0)

  var s = SuiteRef(
    uuid: generateUUID(),
    root: true,
    rootEmpty: true,
    timeout: 2000
  )
  s.suites = system.move(m.results)
  m.results = @[s]

  let (folder, _) = fileName.splitPath()
  if folder.len > 0:
    createDir(folder)
  Json.saveFile(fileName, m)
