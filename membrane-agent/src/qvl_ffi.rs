//! QVL FFI - Rust bindings to Zig QVL C ABI
//!
//! Provides safe Rust wrappers around the C FFI exports from l1-identity/qvl_ffi.zig.

use std::os::raw::c_int;
use thiserror::Error;

// ============================================================================
// RAW FFI DECLARATIONS
// ============================================================================

/// Opaque handle to QVL context (Zig internals)
#[repr(C)]
pub struct QvlContext {
    _opaque: [u8; 0],
}

/// Anomaly score returned from betrayal detection
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct QvlAnomalyScore {
    pub node: u32,
    pub score: f64,
    pub reason: u8,
}

/// Risk edge for graph mutations
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct QvlRiskEdge {
    pub from: u32,
    pub to: u32,
    pub risk: f64,
    pub timestamp_ns: u64,
    pub nonce: u64,
    pub level: u8,
    pub expires_at_ns: u64,
}

/// Proof-of-Path verification verdict
#[repr(C)]
#[derive(Debug, Copy, Clone, PartialEq, Eq)]
pub enum PopVerdict {
    Valid = 0,
    InvalidEndpoints = 1,
    BrokenLink = 2,
    Revoked = 3,
    Replay = 4,
}

extern "C" {
    fn qvl_init() -> *mut QvlContext;
    fn qvl_deinit(ctx: *mut QvlContext);
    
    fn qvl_get_trust_score(
        ctx: *mut QvlContext,
        did: *const u8,
        did_len: usize,
    ) -> f64;
    
    fn qvl_get_reputation(ctx: *mut QvlContext, node_id: u32) -> f64;
    
    fn qvl_verify_pop(
        ctx: *mut QvlContext,
        proof_bytes: *const u8,
        proof_len: usize,
        sender_did: *const u8,
        receiver_did: *const u8,
    ) -> PopVerdict;
    
    fn qvl_detect_betrayal(
        ctx: *mut QvlContext,
        source_node: u32,
    ) -> QvlAnomalyScore;
    
    fn qvl_add_trust_edge(
        ctx: *mut QvlContext,
        edge: *const QvlRiskEdge,
    ) -> c_int;
    
    fn qvl_revoke_trust_edge(
        ctx: *mut QvlContext,
        from: u32,
        to: u32,
    ) -> c_int;

    fn qvl_get_did(
        ctx: *mut QvlContext,
        node_id: u32,
        out_did: *mut u8,
    ) -> bool;

    fn qvl_register_node(
        ctx: *mut QvlContext,
        did: *const u8,
        out_id: *mut u32,
    ) -> bool;

    fn qvl_get_betrayal_evidence(
        ctx: *mut QvlContext,
        node_id: u32,
        out_buf: *mut u8,
        buf_len: u32,
    ) -> u32;

    fn qvl_issue_slash_signal(
        ctx: *mut QvlContext,
        target_did: *const u8,
        reason: u8,
        evidence_hash: *const u8,
        out_signal: *mut u8,
    ) -> c_int;
}

// ============================================================================
// SAFE RUST WRAPPER
// ============================================================================

/// Anomaly reason enum (safe Rust version)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AnomalyReason {
    None,
    NegativeCycle,
    LowCoverage,
    BpDivergence,
    Unknown,
}

impl AnomalyReason {
    fn from_u8(val: u8) -> Self {
        match val {
            0 => Self::None,
            1 => Self::NegativeCycle,
            2 => Self::LowCoverage,
            3 => Self::BpDivergence,
            _ => Self::Unknown,
        }
    }
}

/// Anomaly score (safe Rust version)
#[derive(Debug, Clone)]
pub struct AnomalyScore {
    pub node: u32,
    pub score: f64,
    pub reason: AnomalyReason,
}

/// QVL client errors
#[derive(Error, Debug)]
pub enum QvlError {
    #[error("QVL initialization failed")]
    InitFailed,
    
    #[error("Invalid DID (must be 32 bytes)")]
    InvalidDid,
    
    #[error("Trust score query failed")]
    TrustScoreFailed,
    
    #[error("Graph mutation failed")]
    MutationFailed,
    
    #[error("Null context")]
    NullContext,
}

/// Safe Rust wrapper around QVL FFI
pub struct QvlClient {
    ctx: *mut QvlContext,
}

impl QvlClient {
    /// Initialize QVL context
    pub fn new() -> Result<Self, QvlError> {
        let ctx = unsafe { qvl_init() };
        if ctx.is_null() {
            return Err(QvlError::InitFailed);
        }
        Ok(Self { ctx })
    }
    
    /// Get trust score for a DID
    pub fn get_trust_score(&self, did: &[u8; 32]) -> Result<f64, QvlError> {
        if self.ctx.is_null() {
            return Err(QvlError::NullContext);
        }
        
        let score = unsafe {
            qvl_get_trust_score(self.ctx, did.as_ptr(), 32)
        };
        
        if score < 0.0 {
            Err(QvlError::TrustScoreFailed)
        } else {
            Ok(score)
        }
    }
    
    /// Get reputation for a node ID
    pub fn get_reputation(&self, node_id: u32) -> Result<f64, QvlError> {
        if self.ctx.is_null() {
            return Err(QvlError::NullContext);
        }
        
        let score = unsafe {
            qvl_get_reputation(self.ctx, node_id)
        };
        
        if score < 0.0 {
            Err(QvlError::TrustScoreFailed)
        } else {
            Ok(score)
        }
    }
    
    /// Verify a Proof-of-Path
    pub fn verify_pop(
        &self,
        proof: &[u8],
        sender_did: &[u8; 32],
        receiver_did: &[u8; 32],
    ) -> Result<PopVerdict, QvlError> {
        if self.ctx.is_null() {
            return Err(QvlError::NullContext);
        }
        
        let verdict = unsafe {
            qvl_verify_pop(
                self.ctx,
                proof.as_ptr(),
                proof.len(),
                sender_did.as_ptr(),
                receiver_did.as_ptr(),
            )
        };
        
        Ok(verdict)
    }
    
    /// Detect betrayal (Bellman-Ford negative cycle detection)
    pub fn detect_betrayal(&self, source_node: u32) -> Result<AnomalyScore, QvlError> {
        if self.ctx.is_null() {
            return Err(QvlError::NullContext);
        }
        
        let raw_score = unsafe {
            qvl_detect_betrayal(self.ctx, source_node)
        };
        
        Ok(AnomalyScore {
            node: raw_score.node,
            score: raw_score.score,
            reason: AnomalyReason::from_u8(raw_score.reason),
        })
    }
    
    /// Add a trust edge to the risk graph
    pub fn add_trust_edge(&self, edge: QvlRiskEdge) -> Result<(), QvlError> {
        if self.ctx.is_null() {
            return Err(QvlError::NullContext);
        }
        
        let result = unsafe {
            qvl_add_trust_edge(self.ctx, &edge as *const QvlRiskEdge)
        };
        
        if result == 0 {
            Ok(())
        } else {
            Err(QvlError::MutationFailed)
        }
    }
    
    /// Revoke a trust edge
    pub fn revoke_trust_edge(&self, from: u32, to: u32) -> Result<(), QvlError> {
        if self.ctx.is_null() {
            return Err(QvlError::NullContext);
        }
        
        let result = unsafe {
            qvl_revoke_trust_edge(self.ctx, from, to)
        };
        
        if result == 0 {
            Ok(())
        } else {
            Err(QvlError::MutationFailed)
        }
    }

    /// Get DID for a node ID
    pub fn get_did(&self, node_id: u32) -> Option<[u8; 32]> {
        if self.ctx.is_null() {
            return None;
        }

        let mut out = [0u8; 32];
        let result = unsafe {
            qvl_get_did(self.ctx, node_id, out.as_mut_ptr())
        };

        if result {
            Some(out)
        } else {
            None
        }
    }

    /// Register a DID and get its Node ID
    pub fn register_node(&self, did: &[u8; 32]) -> Result<u32, QvlError> {
        if self.ctx.is_null() {
            return Err(QvlError::NullContext);
        }
        let mut out_id = 0u32;
        let result = unsafe {
            qvl_register_node(self.ctx, did.as_ptr(), &mut out_id)
        };
        if result {
            Ok(out_id)
        } else {
            Err(QvlError::MutationFailed)
        }
    }

    /// Get betrayal evidence (Proof of Cycle)
    pub fn get_betrayal_evidence(&self, node_id: u32) -> Result<Vec<u8>, QvlError> {
        if self.ctx.is_null() {
            return Err(QvlError::NullContext);
        }

        // First call to get length
        let len = unsafe {
            qvl_get_betrayal_evidence(self.ctx, node_id, std::ptr::null_mut(), 0)
        };

        if len == 0 {
            return Err(QvlError::MutationFailed); // No evidence or cycle
        }

        let mut buf = vec![0u8; len as usize];
        let written = unsafe {
            qvl_get_betrayal_evidence(self.ctx, node_id, buf.as_mut_ptr(), len)
        };

        if written != len {
            return Err(QvlError::MutationFailed);
        }
        Ok(buf)
    }

    /// Issue a SlashSignal (returns 82-byte serialized signal for signing/broadcast)
    pub fn issue_slash_signal(&self, target_did: &[u8; 32], reason: u8, evidence_hash: &[u8; 32]) -> Result<[u8; 82], QvlError> {
        if self.ctx.is_null() {
            return Err(QvlError::NullContext);
        }

        let mut out = [0u8; 82];
        let result = unsafe {
            qvl_issue_slash_signal(
                self.ctx,
                target_did.as_ptr(),
                reason,
                evidence_hash.as_ptr(),
                out.as_mut_ptr(),
            )
        };

        if result == 0 {
            Ok(out)
        } else {
            Err(QvlError::MutationFailed)
        }
    }
}

impl Drop for QvlClient {
    fn drop(&mut self) {
        if !self.ctx.is_null() {
            unsafe { qvl_deinit(self.ctx) }
        }
    }
}

// Mark as Send + Sync (QVL is thread-safe via C allocator)
unsafe impl Send for QvlClient {}
unsafe impl Sync for QvlClient {}

// ============================================================================
// TESTS
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_qvl_init_deinit() {
        let client = QvlClient::new().expect("QVL init failed");
        drop(client);  // Verify deinit doesn't crash
    }
    
    #[test]
    fn test_get_reputation() {
        let client = QvlClient::new().unwrap();
        let score = client.get_reputation(42).unwrap();
        assert_eq!(score, 0.5);  // Default neutral reputation
    }
    
    #[test]
    fn test_add_edge() {
        let client = QvlClient::new().unwrap();
        let edge = QvlRiskEdge {
            from: 0,
            to: 1,
            risk: 0.5,
            timestamp_ns: 1000,
            nonce: 0,
            level: 3,
            expires_at_ns: 2000,
        };
        
        client.add_trust_edge(edge).expect("Add edge failed");
    }
    
    #[test]
    fn test_detect_betrayal_no_cycle() {
        let client = QvlClient::new().unwrap();
        let anomaly = client.detect_betrayal(0).unwrap();
        
        // No betrayal in empty graph
        assert_eq!(anomaly.score, 0.0);
        assert_eq!(anomaly.reason, AnomalyReason::None);
    }

    #[test]
    fn test_issue_slash_signal() {
        let client = QvlClient::new().unwrap();
        let target = [1u8; 32];
        let reason = 1; // BetrayalNegativeCycle
        let evidence_hash = [0xFAu8; 32];

        let signal = client.issue_slash_signal(&target, reason, &evidence_hash).unwrap();
        // Verify first byte (target DID[0] = 1)
        assert_eq!(signal[0], 1);
        // Verify reason (offset 32 = 1)
        assert_eq!(signal[32], 1);
        // Verify evidence hash (offset 33)
        assert_eq!(signal[33], 0xFA); 
        // Verify severity (offset 32 + 1 + 32 + 8 = 73 ? Check packing)
        // With packed(u64 aligned?), offsets might vary if not careful.
        // But [33] should be start of evidence.
    }
}
