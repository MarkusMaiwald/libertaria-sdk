//! Control Protocol for Capsule CLI <-> Daemon communication.
//! Uses a simple JSON-based request/response model over a Unix Domain Socket.

const std = @import("std");
const l1_identity = @import("l1_identity");
const qvl = l1_identity.qvl;

/// Commands sent from CLI to Daemon
pub const Command = union(enum) {
    /// Request general node status
    Status: void,
    /// Request list of connected peers
    Peers: void,
    /// Request list of federated sessions
    Sessions: void,
    /// Query QVL trust metrics
    QvlQuery: QvlQueryArgs,
    /// Manually trigger a Slash/Quarantine
    Slash: SlashArgs,
    /// Query the Slash Log
    SlashLog: SlashLogArgs,
    /// Ban a peer by DID
    Ban: BanArgs,
    /// Unban a peer by DID
    Unban: UnbanArgs,
    /// Manually set trust for a DID
    Trust: TrustArgs,
    /// Get DHT routing table info
    Dht: void,
    /// Get node identity information
    Identity: void,
    /// Emergency lockdown - block ALL traffic
    Lockdown: void,
    /// Resume normal operation
    Unlock: void,
    /// Set airlock state (open/restricted/closed)
    Airlock: AirlockArgs,
    /// Shutdown the daemon (admin only)
    Shutdown: void,
    /// Get Topology for Graph Visualization
    Topology: void,
    /// Start/Stop Relay Service
    RelayControl: RelayControlArgs,
    /// Get Relay Stats
    RelayStats: void,
    /// Build Circuit and Send Message
    RelaySend: RelaySendArgs,
};

pub const SlashArgs = struct {
    target_did: []const u8,
    reason: []const u8, // stringified enum
    severity: []const u8, // stringified enum
    duration: u32 = 0,
};

pub const SlashLogArgs = struct {
    limit: usize = 50,
};

pub const BanArgs = struct {
    target_did: []const u8,
    reason: []const u8,
};

pub const UnbanArgs = struct {
    target_did: []const u8,
};

pub const TrustArgs = struct {
    target_did: []const u8,
    score: f64,
};

pub const QvlQueryArgs = struct {
    /// Optional: Filter by specific DID (if null, returns global metrics)
    target_did: ?[]const u8 = null,
};

pub const AirlockArgs = struct {
    /// Airlock state: "open", "restricted", or "closed"
    state: []const u8,
};

pub const RelayControlArgs = struct {
    enable: bool,
    trust_threshold: f64 = 0.5,
};

pub const RelaySendArgs = struct {
    target_did: []const u8,
    message: []const u8,
};

/// Responses sent from Daemon to CLI
pub const Response = union(enum) {
    /// General status info
    NodeStatus: NodeStatus,
    /// List of peers
    PeerList: []const PeerInfo,
    /// List of sessions
    SessionList: []const SessionInfo,
    /// DHT info
    DhtInfo: DhtInfo,
    /// Identity info
    IdentityInfo: IdentityInfo,
    /// Lockdown status
    LockdownStatus: LockdownInfo,
    /// Topology info
    TopologyInfo: TopologyInfo,
    /// QVL query results
    QvlResult: QvlMetrics,
    /// Slash Log results
    SlashLogResult: []const SlashEvent,
    /// Simple success message
    Ok: []const u8,
    /// Error message
    Error: []const u8,
    /// Relay Statistics
    RelayStatsInfo: RelayStatsInfo,
};

pub const NodeStatus = struct {
    node_id: []const u8,
    state: []const u8, // e.g., "Running", "Syncing"
    peers_count: usize,
    uptime_seconds: i64,
    version: []const u8,
};

pub const PeerInfo = struct {
    id: []const u8,
    address: []const u8,
    state: []const u8, // "Active", "Federated"
    last_seen: i64,
};

pub const SessionInfo = struct {
    address: []const u8,
    did_short: []const u8,
    state: []const u8, // "Handshaking", "Active"
};

pub const QvlMetrics = struct {
    total_vertices: usize,
    total_edges: usize,
    trust_rank: f64, // Placeholder for now
};

pub const DhtInfo = struct {
    local_node_id: []const u8,
    routing_table_size: usize,
    known_nodes: usize,
};

pub const IdentityInfo = struct {
    did: []const u8,
    public_key: []const u8, // hex-encoded Ed25519 public key
    dht_node_id: []const u8,
};

pub const LockdownInfo = struct {
    is_locked: bool,
    airlock_state: []const u8, // "open", "restricted", "closed"
    locked_since: i64,
};

pub const TopologyInfo = struct {
    nodes: []const GraphNode,
    edges: []const GraphEdge,
};

pub const GraphNode = struct {
    id: []const u8, // short did or node id
    trust_score: f64,
    status: []const u8, // "active", "slashed", "ok"
    role: []const u8, // "self", "peer"
};

pub const GraphEdge = struct {
    source: []const u8,
    target: []const u8,
    weight: f64,
};

pub const SlashEvent = struct {
    timestamp: u64,
    target_did: []const u8,
    reason: []const u8,
    severity: []const u8,
    evidence_hash: []const u8,
};

pub const RelayStatsInfo = struct {
    enabled: bool,
    packets_forwarded: u64,
    packets_dropped: u64,
    trust_threshold: f64,
};
