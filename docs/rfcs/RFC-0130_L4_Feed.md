# RFC-0130: L4 Feed — Temporal Event Store

**Status:** Draft  
**Author:** Jarvis (Silicon Architect and Representative for Agents in Libertaria)  
**Date:** 2026-02-03  
**Target:** Janus SDK v0.2.0  

---

## Summary

L4 Feed ist das temporale Event-Storage-Layer für Libertaria. Es speichert soziale Primitive (Posts, Reactions, Follows) mit hybridem Ansatz:

- **DuckDB:** Strukturierte Queries (Zeitreihen, Aggregations)
- **LanceDB:** Vektor-Search für semantische Ähnlichkeit

## Kenya Compliance

| Constraint | Status | Implementation |
|------------|--------|----------------|
| RAM <10MB | ✅ Planned | DuckDB in-memory mode, LanceDB mmap |
| No cloud | ✅ | Embedded storage only |
| <1MB binary | ⚠️ TBD | Stripped DuckDB + custom LanceDB bindings |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    L4 Feed Layer                            │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────┐        ┌──────────────┐                   │
│  │   DuckDB     │        │  LanceDB     │                   │
│  │  (events)    │        │ (embeddings) │                   │
│  ├──────────────┤        ├──────────────┤                   │
│  │ - Timeline   │        │ - ANN search │                   │
│  │ - Counts     │        │ - Similarity │                   │
│  │ - Replies    │        │ - Clustering │                   │
│  └──────────────┘        └──────────────┘                   │
│          │                       │                          │
│          └───────────┬───────────┘                          │
│                      │                                       │
│              ┌───────▼───────┐                               │
│              │  FeedStore    │                               │
│              └───────────────┘                               │
└─────────────────────────────────────────────────────────────┘
```

## Data Model

### Event Types

```zig
pub const EventType = enum {
    post,           // Original content
    reaction,       // like, boost, bookmark
    follow,         // Social graph edge (directed)
    mention,        // @username reference
    hashtag,        // #topic tag
    edit,           // Content modification
    delete,         // Tombstone (soft delete)
};
```

### FeedEvent Structure

| Field | Type | Description |
|-------|------|-------------|
| id | u64 | Snowflake ID (time-sortable, 64-bit) |
| event_type | EventType | Enum discriminator |
| author | [32]u8 | DID (Decentralized Identifier) |
| timestamp | i64 | Unix nanoseconds |
| content_hash | [32]u8 | Blake3 hash of canonical content |
| parent_id | ?u64 | For replies/threading |
| embedding | ?[384]f32 | 384-dim vector (LanceDB) |
| tags | []string | Hashtags |
| mentions | [][32]u8 | Referenced DIDs |

## DuckDB Schema

```sql
-- Events table (structured data)
CREATE TABLE events (
    id UBIGINT PRIMARY KEY,
    event_type TINYINT,
    author BLOB(32),
    timestamp BIGINT,
    content_hash BLOB(32),
    parent_id UBIGINT,
    tags VARCHAR[],
    embedding_ref INTEGER  -- Index into LanceDB
);

-- Indexes for common queries
CREATE INDEX idx_author_time ON events(author, timestamp DESC);
CREATE INDEX idx_parent ON events(parent_id);
CREATE INDEX idx_time ON events(timestamp DESC);

-- FTS for content search (optional)
CREATE TABLE event_content (
    id UBIGINT PRIMARY KEY REFERENCES events(id),
    text_content VARCHAR
);
```

## LanceDB Schema

```python
# Python pseudocode for schema
import lancedb
from lancedb.pydantic import LanceModel, Vector

class Embedding(LanceModel):
    id: int  # Matches events.id
    vector: Vector(384)  # 384-dim embedding
    
    # Metadata for filtering
    event_type: int
    author: bytes  # 32 bytes DID
    timestamp: int
```

## Query Patterns

### 1. Timeline (Home Feed)
```sql
SELECT * FROM events 
WHERE author IN (SELECT following FROM follows WHERE follower = ?)
ORDER BY timestamp DESC
LIMIT 50;
```

### 2. Thread (Conversation)
```sql
WITH RECURSIVE thread AS (
    SELECT * FROM events WHERE id = ?
    UNION ALL
    SELECT e.* FROM events e
    JOIN thread t ON e.parent_id = t.id
)
SELECT * FROM thread ORDER BY timestamp;
```

### 3. Semantic Search (LanceDB)
```python
# Find similar posts
table.search(query_embedding) \
    .where("event_type = 0") \  # Only posts
    .limit(20) \
    .to_pandas()
```

## Synchronization Strategy

1. **Write Path:**
   - Insert into DuckDB (ACID transaction)
   - Generate embedding (local model, ONNX Runtime)
   - Insert into LanceDB (async, eventual consistency)

2. **Read Path:**
   - DuckDB: Structured queries, counts, timelines
   - LanceDB: Vector similarity, clustering
   - Hybrid: Vector + time filter (LanceDB filter API)

## Implementation Phases

### Phase 1: DuckDB Core (Sprint 4)
- [ ] DuckDB Zig bindings (C API wrapper)
- [ ] Event storage/retrieval
- [ ] Timeline queries
- [ ] Thread reconstruction

### Phase 2: LanceDB Integration (Sprint 5)
- [ ] LanceDB Rust bindings (via C FFI)
- [ ] Embedding storage
- [ ] ANN search
- [ ] Hybrid queries

### Phase 3: Optimization (Sprint 6)
- [ ] WAL for durability
- [ ] Compression (zstd for content)
- [ ] Incremental backups
- [ ] RAM usage optimization

## Dependencies

| Library | Version | Purpose | Size |
|---------|---------|---------|------|
| DuckDB | 0.9.2 | Structured storage | ~15MB → 5MB stripped |
| LanceDB | 0.9.x | Vector storage | ~20MB → 8MB stripped |
| ONNX Runtime | 1.16 | Embeddings | Optional, ~50MB |

**Total binary impact:** ~13MB (DuckDB + LanceDB stripped, ohne ONNX)

## Open Questions

1. **Embedding Model:** All-MiniLM-L6-v2 (22MB) oder kleiner?
2. **Sync Strategy:** LanceDB als optionaler Index (graceful degradation)?
3. **Replication:** Event sourcing für Node-to-Node sync?

---

*Sovereign; Kinetic; Anti-Fragile.* ⚡️
