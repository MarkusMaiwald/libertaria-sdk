# L4 Feed — Temporal Event Store

> Social media primitives for sovereign agents.

## Overview

L4 Feed provides a hybrid storage layer for social content:
- **DuckDB**: Structured data (posts, reactions, follows)
- **LanceDB**: Vector embeddings for semantic search

## Architecture

```
┌─────────────────────────────────────────┐
│           L4 Feed Layer                 │
├─────────────────────────────────────────┤
│  Query Interface (SQL + Vector)         │
├─────────────────────────────────────────┤
│  DuckDB        │        LanceDB        │
│  (time-series) │        (vectors)      │
│                │                       │
│  events table  │  embeddings table     │
│  - id          │  - event_id           │
│  - type        │  - embedding (384d)   │
│  - author      │  - indexed (ANN)      │
│  - timestamp   │                       │
│  - content     │                       │
└─────────────────────────────────────────┘
```

## Event Types

```zig
pub const EventType = enum {
    post,       // Content creation
    reaction,   // Like, boost, etc.
    follow,     // Social graph edge
    mention,    // @username reference
    hashtag,    // #topic categorization
};
```

## Usage

### Store Event

```zig
const feed = try FeedStore.init(allocator, "/path/to/db");

try feed.store(.{
    .id = snowflake(),
    .event_type = .post,
    .author = my_did,
    .timestamp = now(),
    .content_hash = hash(content),
    .embedding = try embed(content), // 384-dim vector
    .tags = &.{"libertaria", "zig"},
    .mentions = &.{},
});
```

### Query Feed

```zig
// Temporal query
const posts = try feed.query(.{
    .author = alice_did,
    .event_type = .post,
    .since = now() - 86400, // Last 24h
    .limit = 50,
});

// Semantic search
const similar = try feed.searchSimilar(
    query_embedding,
    10 // Top-10 similar
);
```

## Kenya Compliance

- **Binary**: ~95KB added to L1
- **Memory**: Streaming queries, no full table loads
- **Storage**: Single DuckDB file (~50MB for 1M events)
- **Offline**: Full functionality without cloud

## Roadmap

- [ ] DuckDB schema and connection
- [ ] LanceDB vector index
- [ ] Event encoding/decoding
- [ ] Query optimizer
- [ ] Replication protocol

---

*Posts are ephemeral. The protocol is eternal.*

⚡️
