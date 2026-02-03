## l1_index.nim: L1 Index Layer for NCP
## B-Tree index for path-based addressing
## RFC-NCP-001 Implementation

import std/[tables, sequtils, algorithm, strutils]
import types

## Index Entry: Maps path to CID
type IndexEntry* = object
  path*: string      ## Hierarchical path (e.g., "/agents/frankie/tasks")
  cid*: CID          ## Content identifier
  timestamp*: int64  ## When indexed

## B-Tree Node (simplified for prototype)
type BTreeNode* = object
  isLeaf*: bool
  keys*: seq[string]      ## Paths
  values*: seq[CID]       ## CIDs
  children*: seq[int]     ## Child node indices (for internal nodes)

## L1 Index Handle
type L1Index* = object
  entries*: Table[string, IndexEntry]  ## Path -> Entry (simplified B-Tree)
  root*: string

proc initL1Index*(): L1Index =
  ## Initialize empty L1 Index
  result.entries = initTable[string, IndexEntry]()
  result.root = "/"

## Insert or update path -> CID mapping
proc insert*(index: var L1Index, path: string, cid: CID, timestamp: int64 = 0) =
  ## Index a path to CID mapping
  index.entries[path] = IndexEntry(
    path: path,
    cid: cid,
    timestamp: if timestamp == 0: getTime().toUnix() else: timestamp
  )

## Lookup CID by exact path
proc lookup*(index: L1Index, path: string): Option[CID] =
  ## Find CID by exact path
  if index.entries.hasKey(path):
    return some(index.entries[path].cid)
  return none(CID)

## List all paths under a prefix (directory listing)
proc list*(index: L1Index, prefix: string): seq[string] =
  ## List all paths starting with prefix
  result = @[]
  for path in index.entries.keys:
    if path.startsWith(prefix):
      result.add(path)
  result.sort()

## Find paths matching glob pattern (simplified)
proc glob*(index: L1Index, pattern: string): seq[string] =
  ## Find paths matching pattern
  ## Supports: * (any chars), ? (single char)
  result = @[]
  for path in index.entries.keys:
    # Simple glob matching (can be improved)
    if matchGlob(path, pattern):
      result.add(path)
  result.sort()

## Simple glob matcher
proc matchGlob*(s, pattern: string): bool =
  ## Match string against glob pattern
  var sIdx = 0
  var pIdx = 0
  
  while pIdx < pattern.len:
    if pattern[pIdx] == '*':
      # Match any sequence
      if pIdx == pattern.len - 1:
        return true  # * at end matches everything
      # Find next char after *
      let nextChar = pattern[pIdx + 1]
      while sIdx < s.len and s[sIdx] != nextChar:
        sIdx.inc
      pIdx += 2
    elif pattern[pIdx] == '?':
      # Match single char
      if sIdx >= s.len:
        return false
      sIdx.inc
      pIdx.inc
    else:
      # Match literal
      if sIdx >= s.len or s[sIdx] != pattern[pIdx]:
        return false
      sIdx.inc
      pIdx.inc
  
  return sIdx == s.len

## Delete path from index
proc remove*(index: var L1Index, path: string): bool =
  ## Remove path from index
  if index.entries.hasKey(path):
    index.entries.del(path)
    return true
  return false

## Get all indexed paths
proc paths*(index: L1Index): seq[string] =
  ## Return all indexed paths (sorted)
  result = toSeq(index.entries.keys)
  result.sort()

## Export
export L1Index, IndexEntry
export initL1Index, insert, lookup, list, glob, remove, paths, matchGlob
