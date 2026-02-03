## types.nim: Core Types for Nexus Context Protocol
## RFC-NCP-001 Implementation
## Author: Frankie (Silicon Architect)

import std/[tables, options, times]

## Content Identifier (CID) using Blake3
## 256-bit hash for content-addressed storage
type CID* = array[32, uint8]

## Content types for Context Nodes
type ContentType* = enum
  ctText       ## Plain text content
  ctImage      ## Image data
  ctEmbedding  ## Vector embedding (L2)
  ctToolCall   ## Tool/function call
  ctMemory     ## Agent memory
  ctSignature  ## Cryptographic signature

## Context Node: The fundamental unit of NCP
## Represents any piece of context in the system
type ContextNode* = object
  cid*: CID                    ## Content identifier (Blake3 hash)
  parent*: Option[CID]         ## Previous version (for versioning)
  path*: string                ## Hierarchical path /agent/task/subtask
  contentType*: ContentType    ## Type of content
  data*: seq[byte]             ## Raw content bytes
  embedding*: Option[seq[float32]]  ## Vector embedding (optional)
  timestamp*: int64            ## Unix nanoseconds
  metadata*: Table[string, string]  ## Key-value metadata

## Path utilities for hierarchical addressing
type Path* = object
  segments*: seq[string]
  absolute*: bool

proc initPath*(path: string): Path =
  ## Parse a path string into segments
  ## Example: "/agents/frankie/tasks" -> ["agents", "frankie", "tasks"]
  result.absolute = path.startsWith("/")
  result.segments = path.split("/").filterIt(it.len > 0)

proc toString*(p: Path): string =
  ## Convert path back to string
  result = if p.absolute: "/" else: ""
  result.add(p.segments.join("/"))

## CID Generation (placeholder - actual Blake3 integration later)
proc generateCID*(data: openArray[byte]): CID =
  ## Generate content identifier from data
  ## TODO: Integrate with actual Blake3 library
  ## For now: simple XOR-based hash (NOT for production)
  var result: CID
  for i in 0..<32:
    result[i] = 0
  for i, b in data:
    result[i mod 32] = result[i mod 32] xor uint8(b)
  return result

## Context Node Operations
proc initContextNode*(
  path: string,
  contentType: ContentType,
  data: openArray[byte]
): ContextNode =
  ## Initialize a new ContextNode
  result.path = path
  result.contentType = contentType
  result.data = @data
  result.cid = generateCID(data)
  result.timestamp = getTime().toUnix() * 1_000_000_000  # nanoseconds
  result.metadata = initTable[string, string]()

## Export utility functions
export CID, ContentType, ContextNode, Path
export initPath, toString, generateCID, initContextNode
