# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  std/[strutils],
  stew/[results],
  ../graphql

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

{.pragma: apiPragma, cdecl, gcsafe, raises: [Defect, CatchableError].}
{.push hint[XDeclaredButNotUsed]: off.}

proc validateHex(x: Node, minLen = 0): NodeResult =
  if x.stringVal.len < 2:
    return err("hex is too short")
  if x.stringVal.len != 2 + minLen * 2 and minLen != 0:
    return err("expect hex with len '$1', got '$2'" % [$(2 * minLen + 2), $x.stringVal.len])
  if x.stringVal.len mod 2 != 0:
    return err("hex must have even number of nibbles")
  if x.stringVal[0] != '0' or x.stringVal[1] notin {'x', 'X'}:
    return err("hex should be prefixed by '0x'")
  for i in 2..<x.stringVal.len:
    if x.stringVal[i] notin HexDigits:
      return err("invalid chars in hex")
  ok(x)

proc scalarBytes32(ctx: GraphqlRef, node: Node): NodeResult {.cdecl, gcsafe, nosideEffect.} =
  ## Bytes32 is a 32 byte binary string,
  ## represented as 0x-prefixed hexadecimal.
  if node.kind != nkString:
    return err("expect hex string, but got '$1'" % [$node.kind])
  validateHex(node, 32)

proc scalarAddress(ctx: GraphqlRef, node: Node): NodeResult {.cdecl, gcsafe, nosideEffect.} =
  ## Address is a 20 byte Ethereum address,
  ## represented as 0x-prefixed hexadecimal.
  if node.kind != nkString:
    return err("expect hex string, but got '$1'" % [$node.kind])
  validateHex(node, 20)

proc scalarBytes(ctx: GraphqlRef, node: Node): NodeResult {.cdecl, gcsafe, nosideEffect.} =
  ## Bytes is an arbitrary length binary string,
  ## represented as 0x-prefixed hexadecimal.
  ## An empty byte string is represented as '0x'.
  ## Byte strings must have an even number of hexadecimal nybbles.
  if node.kind != nkString:
    return err("expect hex string, but got '$1'" % [$node.kind])
  validateHex(node)

proc scalarBigInt(ctx: GraphqlRef, node: Node): NodeResult {.cdecl, gcsafe, nosideEffect.} =
  ## BigInt is a large integer. Input is accepted as
  ## either a JSON number or as a string.
  ## Strings may be either decimal or 0x-prefixed hexadecimal.
  ## Output values are all 0x-prefixed hexadecimal.
  if node.kind != nkString:
    return err("expect hex string, but got '$1'" % [$node.kind])
  if node.stringVal.len > 66:
    # 256 bits = 32 bytes = 64 hex nibbles
    # 64 hex nibbles + '0x' prefix = 66 bytes
    return err("Big Int should not exceed 66 bytes")
  validateHex(node)

proc scalarLong(ctx: GraphqlRef, node: Node): NodeResult {.cdecl, gcsafe, nosideEffect.} =
  ## Long is a 64 bit unsigned integer.
  ## TODO: validate max-int 64 bit
  if node.kind == nkInt:
    # convert it into nkString node
    ok(Node(kind: nkString, stringVal: node.intVal, pos: node.pos))
  else:
    err("expect int, but got '$1'" % [$node.kind])

proc accountAddress(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc accountBalance(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc accountTxCount(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc accountCode(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc accountStorage(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

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

proc txNonce(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc txIndex(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc txFrom(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc txTo(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc txValue(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc txGasPrice(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc txGas(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc txInputData(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc txBlock(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc txStatus(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc txGasUsed(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc txCumulativeGasUsed(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc txCreatedContract(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc txLogs(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

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

proc blockHash(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc blockParent(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc blockNonce(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc blockTransactionsRoot(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc blockTransactionCount(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc blockStateRoot(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc blockReceiptsRoot(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc blockMiner(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc blockExtraData(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc blockGasLimit(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc blockGasUsed(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc blockTimestamp(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc blockLogsBloom(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc blockMixHash(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc blockDifficulty(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc blockTotalDifficulty(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc blockOmmerCount(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc blockOmmers(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc blockOmmerAt(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc blockOmmerHash(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc blockTransactions(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc blockTransactionAt(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc blockLogs(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc blockAccount(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc blockCall(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc blockEstimateGas(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

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

proc syncStateCurrentBlock(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc syncStateHighestBlock(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc syncStatePulledStates(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc syncStateKnownStates(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

const syncStateProcs = {
  "startingBlock": syncStateStartingBlock,
  "currentBlock":  syncStateCurrentBlock,
  "highestBlock":  syncStateHighestBlock,
  "pulledStates":  syncStatePulledStates,
  "knownStates":   syncStateKnownStates
}

proc pendingTransactionCount(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc pendingTransactions(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc pendingAccount(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc pendingCall(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc pendingEstimateGas(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

const pendingProcs = {
  "transactionCount": pendingTransactionCount,
  "transactions": pendingTransactions,
  "account": pendingAccount,
  "call": pendingCall,
  "estimateGas": pendingEstimateGas
}

proc queryBlock(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc queryBlocks(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc queryPending(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc queryTransaction(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc queryLogs(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc queryGasPrice(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc queryProtocolVersion(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

proc querySyncing(ud: RootRef, params: Args, parent: Node): RespResult {.apiPragma.} =
  var ctx = EthServer(ud)

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

  ctx.addResolvers(ud, ud.names[ethAccount    ], accountProcs)
  ctx.addResolvers(ud, ud.names[ethLog        ], logProcs)
  ctx.addResolvers(ud, ud.names[ethTransaction], txProcs)
  ctx.addResolvers(ud, ud.names[ethBlock      ], blockProcs)
  ctx.addResolvers(ud, ud.names[ethCallResult ], callResultProcs)
  ctx.addResolvers(ud, ud.names[ethSyncState  ], syncStateProcs)
  ctx.addResolvers(ud, ud.names[ethPending    ], pendingProcs)
  ctx.addResolvers(ud, ud.names[ethQuery      ], queryProcs)
