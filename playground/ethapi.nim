# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  std/[strutils, os],
  stew/[results],
  ../graphql, ../graphql/server_common,
  ./utils

type
  EthTypes = enum
    ethAccount      = "Account"
    ethLog          = "Log"
    ethTransaction  = "Transaction"
    ethBlock        = "Block"
    ethCallResult   = "CallResult"
    ethSyncState    = "SyncState"
    ethPending      = "Pending"
    ethQuery        = "Query"

  EthServer = ref EthServerObj
  EthServerObj = object of RootObj
    names: array[EthTypes, Name]
    blocks: Node
    accounts: Node

{.pragma: apiPragma, cdecl, gcsafe, raises: [Defect, CatchableError].}
{.push hint[XDeclaredButNotUsed]: off.}

proc validateHex(x: Node, minLen = 0): NodeResult =
  if x.stringVal.len < 2:
    return err("hex is too short")
  if x.stringVal.len > 2 + minLen * 2 and minLen != 0:
    return err("expect hex with len '$1', got '$2'" % [$(2 * minLen + 2), $x.stringVal.len])
  if x.stringVal.len mod 2 != 0:
    return err("hex must have even number of nibbles")
  if x.stringVal[0] != '0' or x.stringVal[1] notin {'x', 'X'}:
    return err("hex should be prefixed by '0x'")
  for i in 2..<x.stringVal.len:
    if x.stringVal[i] notin HexDigits:
      return err("invalid chars in hex")
  ok(x)

proc scalarBytes32(ctx: GraphqlRef, typeNode, node: Node): NodeResult {.cdecl, gcsafe, nosideEffect.} =
  ## Bytes32 is a 32 byte binary string,
  ## represented as 0x-prefixed hexadecimal.
  if node.kind != nkString:
    return err("expect hex string, but got '$1'" % [$node.kind])
  validateHex(node, 32)

proc scalarAddress(ctx: GraphqlRef, typeNode, node: Node): NodeResult {.cdecl, gcsafe, nosideEffect.} =
  ## Address is a 20 byte Ethereum address,
  ## represented as 0x-prefixed hexadecimal.
  if node.kind != nkString:
    return err("expect hex string, but got '$1'" % [$node.kind])
  validateHex(node, 20)

proc scalarBytes(ctx: GraphqlRef, typeNode, node: Node): NodeResult {.cdecl, gcsafe, nosideEffect.} =
  ## Bytes is an arbitrary length binary string,
  ## represented as 0x-prefixed hexadecimal.
  ## An empty byte string is represented as '0x'.
  ## Byte strings must have an even number of hexadecimal nybbles.
  if node.kind != nkString:
    return err("expect hex string, but got '$1'" % [$node.kind])
  validateHex(node)

proc validateInt(node: Node): NodeResult =
  for c in node.stringVal:
    if c notin Digits:
      return err("invalid char in int: '$1'" % [$c])

  node.stringVal = "0x" & convertBase(node.stringVal, 10, 16)
  if node.stringVal.len > 66:
    return err("int overflow")

  ok(node)

proc scalarBigInt(ctx: GraphqlRef, typeNode, node: Node): NodeResult {.cdecl, gcsafe, nosideEffect.} =
  ## BigInt is a large integer. Input is accepted as
  ## either a JSON number or as a string.
  ## Strings may be either decimal or 0x-prefixed hexadecimal.
  ## Output values are all 0x-prefixed hexadecimal.
  if node.kind == nkInt:
    # convert it into hex nkString node
    validateInt(Node(kind: nkString, stringVal: node.intVal, pos: node.pos))
  elif node.kind == nkString:
    if {'x', 'X'} in node.stringVal:
      # probably a hex string
      if node.stringVal.len > 66:
        # 256 bits = 32 bytes = 64 hex nibbles
        # 64 hex nibbles + '0x' prefix = 66 bytes
        return err("Big Int should not exceed 66 bytes")
      validateHex(node)
    else:
      # convert it into hex nkString node
      validateInt(node)
  else:
    return err("expect hex/dec string or int, but got '$1'" % [$node.kind])

proc scalarLong(ctx: GraphqlRef, typeNode, node: Node): NodeResult {.cdecl, gcsafe, nosideEffect.} =
  ## Long is a 64 bit unsigned integer.
  ## TODO: validate max-int 64 bit
  if node.kind == nkInt:
    # convert it into nkString node
    ok(node)
  else:
    err("expect int, but got '$1'" % [$node.kind])

proc findKey(node: Node, key: string): RespResult =
  for n in node:
    if n[0].stringVal == key:
      return ok(n[1])

  err("cannot find key: " & key)

proc toBlock(n: Node, name: Name): Node =
  let map = respMap(name)
  map["blocks"] = n[3][1]
  map["txs"] = n[4][1]
  map["ommers"] = n[2][1]
  map

proc toAccount(node: Node, address: Node, name: Name): Node =
  let map = respMap(name)
  map["address"] = address
  for n in node:
    map[n[0].stringVal] = n[1]
  map

proc findMap(node: Node, key: string): RespResult =
  for n in node.map:
    if n.key == key:
      return ok(n.val)

  err("cannot find key: " & key)

proc findMap(node: Node, key, subkey: string): RespResult =
  for n in node.map:
    if n.key == key:
      return findKey(n.val, subkey)

  err("cannot find key: " & key)

proc findLong(node: Node, key: string): RespResult =
  let res = findKey(node, key)
  if res.isErr:
    return res
  let node = res.get()
  let intVal = parseHexInt(node.stringVal)
  ok(Node(kind: nkInt, intVal: $intVal, pos: node.pos))

proc findMapLong(node: Node, key: string): RespResult =
  let res = findMap(node, key)
  if res.isErr:
    return res
  let node = res.get()
  let intVal = parseHexInt(node.stringVal)
  ok(Node(kind: nkInt, intVal: $intVal, pos: node.pos))

proc accountAddress(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  findMap(parent, "address")

proc accountBalance(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  findMap(parent, "balance")

proc accountTxCount(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  findMapLong(parent, "nonce")

proc accountCode(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  findMap(parent, "code")

proc accountStorage(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  let slot = params[0].val
  let res = findMap(parent, "storage")
  if res.isErr:
    return res
  let storage = res.get()
  for n in storage:
    if n[0].stringVal == slot.stringVal:
      return ok(n[1])
  err("cannot find storage with slot: " & slot.stringVal)

const accountProcs = {
  "address": accountAddress,
  "balance": accountBalance,
  "transactionCount": accountTxCount,
  "code": accountCode,
  "storage": accountStorage
}

proc logIndex(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc logAccount(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc logTopics(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc logData(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc logTransaction(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

const logProcs = {
  "index": logIndex,
  "account": logAccount,
  "topics": logTopics,
  "data": logData,
  "transaction": logTransaction
}

proc txHash(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  ok(resp("0x0102030405060708090a0b0c0d0e0f0102030405060708090a0b0c0d0e0f0000"))

proc txNonce(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  findMap(parent, "tx", "nonce")

proc txIndex(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  findMap(parent, "index")

proc txFrom(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  err("not implemented")

proc txTo(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  err("not implemented")

proc txValue(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  ok(resp(1000))

proc txGasPrice(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  ok(resp(21000))

proc txGas(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  ok(resp(21000))

proc txInputData(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  ok(resp("0xDEADBEEF"))

proc txBlock(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  err("not implemented")

proc txStatus(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  ok(resp(1))

proc txGasUsed(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  ok(resp(21000))

proc txCumulativeGasUsed(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  ok(resp(21000))

proc txCreatedContract(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  err("not implemented")

proc txLogs(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  err("not implemented")

const txProcs = {
  "hash": txHash,
  "nonce": txNonce,
  "index": txIndex,
  "from": txFrom,
  "to": txTo,
  "value": txValue,
  "gasPrice": txGasPrice,
  "gas": txGas,
  "inputData": txInputData,
  "block": txBlock,
  "status": txStatus,
  "gasUsed": txGasUsed,
  "cumulativeGasUsed": txCumulativeGasUsed,
  "createdContract": txCreatedContract,
  "logs": txLogs
}

proc blockNumber(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  let blk = parent.map[0].val
  findLong(blk, "number")

proc blockHash(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  let blk = parent.map[0].val
  findKey(blk, "hash")

proc blockParent(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  let blk = parent.map[0].val
  let res = findKey(blk, "parentHash")
  if res.isErr:
    return res
  let parentHash = res.get()
  for n in ctx.blocks:
    let res = findKey(n[3][1], "hash")
    if res.isErr:
      return res
    if res.get().stringVal == parentHash.stringVal:
      return ok(n.toBlock(ctx.names[ethBlock]))
  err("cannot find parent with hash: " & parentHash.stringVal)

proc blockNonce(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  let blk = parent.map[0].val
  findKey(blk, "nonce")

proc blockTransactionsRoot(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  let blk = parent.map[0].val
  findKey(blk, "transactionsTrie")

proc blockTransactionCount(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  let txs = parent.map[1].val
  ok(resp(txs.len))

proc blockStateRoot(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  let blk = parent.map[0].val
  findKey(blk, "stateRoot")

proc blockReceiptsRoot(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  let blk = parent.map[0].val
  findKey(blk, "receiptTrie")

proc blockMiner(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  let blk = parent.map[0].val
  let res = findKey(blk, "coinbase")
  if res.isErr:
    return res
  let miner = res.get()
  for n in ctx.accounts:
    if n[0].stringVal == miner.stringVal:
      return ok(toAccount(n[1], n[0], ctx.names[ethAccount]))
  err("eccount not found: " & miner.stringVal)

proc blockExtraData(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  let blk = parent.map[0].val
  findKey(blk, "extraData")

proc blockGasLimit(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  let blk = parent.map[0].val
  findLong(blk, "gasLimit")

proc blockGasUsed(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  let blk = parent.map[0].val
  findLong(blk, "gasUsed")

proc blockTimestamp(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  let blk = parent.map[0].val
  findKey(blk, "timestamp")

proc blockLogsBloom(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  let blk = parent.map[0].val
  findKey(blk, "bloom")

proc blockMixHash(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  let blk = parent.map[0].val
  findKey(blk, "mixHash")

proc blockDifficulty(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  let blk = parent.map[0].val
  findKey(blk, "difficulty")

proc blockTotalDifficulty(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  let blk = parent.map[0].val
  findKey(blk, "difficulty")

proc blockOmmerCount(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  let ommers = parent.map[2].val
  ok(resp(ommers.len))

proc blockOmmers(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  err("not implemented")

proc blockOmmerAt(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  err("not implemented")

proc blockOmmerHash(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  let blk = parent.map[0].val
  findKey(blk, "uncleHash")

proc blockTransactions(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  let txs = parent.map[1].val
  var list = respList()
  var i = 0
  for n in txs:
    var map = respMap(ctx.names[ethTransaction])
    map["index"] = resp(i)
    map["tx"] = n
    list.add map
    inc i

  ok(list)

proc blockTransactionAt(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  err("not implemented")

proc blockLogs(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  err("not implemented")

proc blockAccount(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  err("not implemented")

proc blockCall(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  err("not implemented")

proc blockEstimateGas(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  ok(resp(21000))

const blockProcs = {
  "number": blockNumber,
  "hash": blockHash,
  "parent": blockParent,
  "nonce": blockNonce,
  "transactionsRoot": blockTransactionsRoot,
  "transactionCount": blockTransactionCount,
  "stateRoot": blockStateRoot,
  "receiptsRoot": blockReceiptsRoot,
  "miner": blockMiner,
  "extraData": blockExtraData,
  "gasLimit": blockGasLimit,
  "gasUsed": blockGasUsed,
  "timestamp": blockTimestamp,
  "logsBloom": blockLogsBloom,
  "mixHash": blockMixHash,
  "difficulty": blockDifficulty,
  "totalDifficulty": blockTotalDifficulty,
  "ommerCount": blockOmmerCount,
  "ommers": blockOmmers,
  "ommerAt": blockOmmerAt,
  "ommerHash": blockOmmerHash,
  "transactions": blockTransactions,
  "transactionAt": blockTransactionAt,
  "blockLogs": blockLogs,
  "account": blockAccount,
  "call": blockCall,
  "estimateGas": blockEstimateGas
}

proc callResultData(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc callResultGasUsed(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc callResultStatus(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

const callResultProcs = {
  "data": callResultData,
  "gasUsed": callResultGasUsed,
  "status": callResultStatus
}

proc syncStateStartingBlock(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  ok(resp(0))

proc syncStateCurrentBlock(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  ok(resp(3))

proc syncStateHighestBlock(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  ok(resp(3))

proc syncStatePulledStates(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  ok(respNull())

proc syncStateKnownStates(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  ok(respNull())

const syncStateProcs = {
  "startingBlock": syncStateStartingBlock,
  "currentBlock":  syncStateCurrentBlock,
  "highestBlock":  syncStateHighestBlock,
  "pulledStates":  syncStatePulledStates,
  "knownStates":   syncStateKnownStates
}

proc pendingTransactionCount(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  ok(resp(1))

proc pendingTransactions(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  err("not implemented")

proc pendingAccount(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  let n = ctx.accounts[0]
  ok(toAccount(n[1], n[0], ctx.names[ethAccount]))

proc pendingCall(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  err("not implemented")

proc pendingEstimateGas(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  ok(resp(21000))

const pendingProcs = {
  "transactionCount": pendingTransactionCount,
  "transactions": pendingTransactions,
  "account": pendingAccount,
  "call": pendingCall,
  "estimateGas": pendingEstimateGas
}

proc queryBlock(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  let number = params[0].val
  let hash = params[1].val
  if number.kind == nkInt:
    for n in ctx.blocks:
      if n[1][1].stringVal == number.intVal:
        return ok(n.toBlock(ctx.names[ethBlock]))
    err("block not found: " & number.stringVal)
  elif hash.kind == nkString:
    for n in ctx.blocks:
      if n[1][1].stringVal == number.intVal:
        return ok(n.toBlock(ctx.names[ethBlock]))
    err("block not found: " & number.stringVal)
  else:
    ok(ctx.blocks[ctx.blocks.len - 1].toBlock(ctx.names[ethBlock]))

proc queryBlocks(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  var list = respList()
  let blk = toBlock(ctx.blocks[0], ctx.names[ethBlock])
  list.add blk
  ok(list)

proc queryPending(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  ok(respMap(ctx.names[ethPending]))

proc queryTransaction(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  err("not implemented")

proc queryLogs(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  err("not implemented")

proc queryGasPrice(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  ok(resp(21000))

proc queryProtocolVersion(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  ok(resp(63))

proc querySyncing(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)
  ok(respMap(ctx.names[ethSyncState]))

const queryProcs = {
  "block": queryBlock,
  "blocks": queryBlocks,
  "pending": queryPending,
  "transaction": queryTransaction,
  "logs": queryLogs,
  "gasPrice": queryGasPrice,
  "protocolVersion": queryProtocolVersion,
  "syncing": querySyncing
}

{.pop.}

proc extractData(ud: EthServer, node: Node) =
  let data = node[0][1]
  for n in data:
    if $n[0] == "blocks":
      ud.blocks = n[1]
    elif $n[0] == "postState":
      ud.accounts = n[1]

proc initEthApi*(ctx: GraphqlRef) =
  ctx.customScalar("Bytes32", scalarBytes32)
  ctx.customScalar("Address", scalarAddress)
  ctx.customScalar("Bytes", scalarBytes)
  ctx.customScalar("BigInt", scalarBigInt)
  ctx.customScalar("Long", scalarLong)

  var ud = EthServer()
  for n in EthTypes:
    let name = ctx.createName($n)
    ud.names[n] = name

  let res = ctx.parseLiteralFromFile("playground" / "data" / "ConstantinopleFixTransition.json", {pfJsonCompatibility})
  if res.isErr:
    debugEcho res.error
    quit(QuitFailure)

  extractData(ud, res.get())

  ctx.addResolvers(ud, ud.names[ethAccount    ], accountProcs)
  ctx.addResolvers(ud, ud.names[ethLog        ], logProcs)
  ctx.addResolvers(ud, ud.names[ethTransaction], txProcs)
  ctx.addResolvers(ud, ud.names[ethBlock      ], blockProcs)
  ctx.addResolvers(ud, ud.names[ethCallResult ], callResultProcs)
  ctx.addResolvers(ud, ud.names[ethSyncState  ], syncStateProcs)
  ctx.addResolvers(ud, ud.names[ethPending    ], pendingProcs)
  ctx.addResolvers(ud, ud.names[ethQuery      ], queryProcs)
