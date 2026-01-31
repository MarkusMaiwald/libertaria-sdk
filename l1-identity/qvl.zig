//! L1 QVL (Quasar Vector Lattice) - Advanced Graph Engine
//!
//! RFC-0120 Extension: Betrayal Detection, Pathfinding, Gossip, and Inference
//!
//! This module extends the CompactTrustGraph with:
//! - Bellman-Ford negative-cycle detection (betrayal rings)
//! - A* reputation-guided pathfinding
//! - Aleph-style probabilistic gossip
//! - Loopy Belief Propagation for edge inference

pub const types = @import("qvl/types.zig");
pub const betrayal = @import("qvl/betrayal.zig");
pub const pathfinding = @import("qvl/pathfinding.zig");
pub const gossip = @import("qvl/gossip.zig");
pub const inference = @import("qvl/inference.zig");
pub const pop = @import("qvl/pop_integration.zig");

pub const RiskEdge = types.RiskEdge;
pub const NodeId = types.NodeId;
pub const AnomalyScore = types.AnomalyScore;

test {
    @import("std").testing.refAllDecls(@This());
}
