## NCP Core Types

This directory contains the Nexus Context Protocol prototype implementation.

### Structure

- `src/types.nim` - Core types (CID, ContextNode, Path)
- `src/l0_storage.nim` - File backend, CID generation (Blake3)
- `src/l1_index.nim` - B-Tree index, path-based addressing
- `tests/test_ncp.nim` - Unit tests

### Status

Feature 1 (Core Types): In Progress
