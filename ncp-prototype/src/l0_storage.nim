## l0_storage.nim: L0 Storage Layer for NCP
## File-based backend with CID content addressing
## RFC-NCP-001 Implementation

import std/[os, paths, sequtils, hashes]
import types

## Storage Configuration
type StorageConfig* = object
  rootPath*: string           ## Root directory for storage
  maxFileSize*: int64         ## Max file size (default: 100MB)
  compression*: bool          ## Enable compression (future)

## L0 Storage Handle
type L0Storage* = object
  config*: StorageConfig
  root*: string

proc initL0Storage*(rootPath: string): L0Storage =
  ## Initialize L0 Storage with root directory
  result.config.rootPath = rootPath
  result.config.maxFileSize = 100 * 1024 * 1024  # 100MB
  result.root = rootPath
  
  # Ensure directory exists
  createDir(rootPath)

## CID to file path mapping
## CID: [0x12, 0x34, 0x56, ...] -> path: "root/12/34/5678..."
proc cidToPath*(storage: L0Storage, cid: CID): string =
  ## Convert CID to filesystem path (content-addressed)
  let hex = cid.mapIt(it.toHex(2)).join()
  result = storage.root / hex[0..1] / hex[2..3] / hex[4..^1]

## Store data and return CID
proc store*(storage: L0Storage, data: openArray[byte]): CID =
  ## Store raw data, return CID
  let cid = generateCID(data)
  let path = storage.cidToPath(cid)
  
  # Create directory structure
  createDir(parentDir(path))
  
  # Write data
  writeFile(path, data)
  
  return cid

## Retrieve data by CID
proc retrieve*(storage: L0Storage, cid: CID): seq[byte] =
  ## Retrieve data by CID
  let path = storage.cidToPath(cid)
  if fileExists(path):
    result = readFile(path).toSeq.mapIt(byte(it))
  else:
    result = @[]  # Not found

## Check if CID exists
proc exists*(storage: L0Storage, cid: CID): bool =
  ## Check if content exists
  let path = storage.cidToPath(cid)
  return fileExists(path)

## Delete content by CID
proc delete*(storage: L0Storage, cid: CID): bool =
  ## Delete content, return success
  let path = storage.cidToPath(cid)
  if fileExists(path):
    removeFile(path)
    return true
  return false

## Export
export L0Storage, StorageConfig
export initL0Storage, cidToPath, store, retrieve, exists, delete
