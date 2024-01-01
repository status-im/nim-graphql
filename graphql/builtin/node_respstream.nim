# nim-graphql
# Copyright (c) 2021 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  ../common/[respstream, ast]

export respstream

type
  NodeRespStream* = ref object of RootRef
    cloneTree: bool
    node: Node

{.push gcsafe, raises: [] .}

proc serialize*(resp: NodeRespStream, n: Node) =
  if resp.cloneTree:
    resp.node = copyTree(n)
    return

  # simply return the same tree
  resp.node = n

proc getNode*(resp: NodeRespStream): Node =
  resp.node

proc init*(v: NodeRespStream, cloneTree: bool = false) =
  v.cloneTree = cloneTree

proc new*(_: type NodeRespStream, cloneTree: bool = false): NodeRespStream =
  let v = NodeRespStream()
  v.init(cloneTree)
  v

{.pop.}
