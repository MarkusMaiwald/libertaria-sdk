//! Policy Enforcer - Trust-based routing and access control
//!
//! Queries QVL for trust scores and makes policy decisions.

use crate::qvl_ffi::{QvlClient, QvlError};
use std::sync::Arc;

/// Policy decision for packet handling
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PolicyDecision {
    /// Accept packet for normal processing/relay
    Accept,
    /// Deprioritize packet (low-priority queue)
    Deprioritize,
    /// Drop packet silently
    Drop,
    /// Treat as neutral (no trust data available)
    Neutral,
}

/// Trust-based policy enforcer
pub struct PolicyEnforcer {
    qvl: Arc<QvlClient>,
    
    // Policy thresholds
    drop_threshold: f64,      // Below this: drop
    untrusted_threshold: f64, // Below this: deprioritize
}

impl PolicyEnforcer {
    /// Create new policy enforcer
    pub fn new(qvl: Arc<QvlClient>) -> Self {
        Self {
            qvl,
            drop_threshold: 0.1,      // Drop if trust < 0.1
            untrusted_threshold: 0.5, // Deprioritize if trust < 0.5
        }
    }
    
    /// Create with custom thresholds
    pub fn with_thresholds(
        qvl: Arc<QvlClient>,
        drop_threshold: f64,
        untrusted_threshold: f64,
    ) -> Self {
        Self {
            qvl,
            drop_threshold,
            untrusted_threshold,
        }
    }
    
    /// Decide whether to accept a packet from a DID
    pub fn should_accept_packet(&self, sender_did: &[u8; 32]) -> PolicyDecision {
        match self.qvl.get_trust_score(sender_did) {
            Ok(score) if score < self.drop_threshold => PolicyDecision::Drop,
            Ok(score) if score < self.untrusted_threshold => PolicyDecision::Deprioritize,
            Ok(_) => PolicyDecision::Accept,
            Err(QvlError::TrustScoreFailed) | Err(QvlError::InvalidDid) => PolicyDecision::Neutral,
            Err(_) => PolicyDecision::Neutral,
        }
    }
    
    /// Check if a node should be flagged for betrayal
    pub fn check_for_betrayal(&self, node_id: u32) -> Option<f64> {
        match self.qvl.detect_betrayal(node_id) {
            Ok(anomaly) if anomaly.score > 0.7 => Some(anomaly.score),
            _ => None,
        }
    }
    
    /// Batch check multiple nodes for betrayal
    pub fn batch_check_betrayal(&self, node_ids: &[u32]) -> Vec<(u32, f64)> {
        node_ids
            .iter()
            .filter_map(|&node_id| {
                self.check_for_betrayal(node_id)
                    .map(|score| (node_id, score))
            })
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_policy_enforcer_neutral() {
        let qvl = Arc::new(QvlClient::new().unwrap());
        let enforcer = PolicyEnforcer::new(qvl);
        
        let unknown_did = [0u8; 32];
        let decision = enforcer.should_accept_packet(&unknown_did);
        
        // Unknown DIDs should be treated as neutral
        assert_eq!(decision, PolicyDecision::Neutral);
    }
    
    #[test]
    fn test_betrayal_check_clean_graph() {
        let qvl = Arc::new(QvlClient::new().unwrap());
        let enforcer = PolicyEnforcer::new(qvl);
        
        // Empty graph should have no betrayal
        let result = enforcer.check_for_betrayal(0);
        assert_eq!(result, None);
    }
    
    #[test]
    fn test_batch_check() {
        let qvl = Arc::new(QvlClient::new().unwrap());
        let enforcer = PolicyEnforcer::new(qvl);
        
        let nodes = vec![0, 1, 2, 3, 4];
        let betrayals = enforcer.batch_check_betrayal(&nodes);
        
        // Clean graph should have no betrayals
        assert_eq!(betrayals.len(), 0);
    }
}
