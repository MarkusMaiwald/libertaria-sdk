//! Anomaly Alert System - P0/P1 prioritized alerting
//!
//! Emits and tracks critical security alerts from QVL betrayal detection.

use crate::qvl_ffi::{AnomalyScore, AnomalyReason};
use chrono::{DateTime, Utc};
use std::sync::{Arc, Mutex};
use tracing::{error, warn, info};

/// Alert priority level
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum AlertPriority {
    /// P0: Critical - immediate action required (score >= 0.9)
    Critical = 0,
    /// P1: Warning - investigate soon (score >= 0.7)
    Warning = 1,
    /// P2: Info - monitor (score >= 0.5)
    Info = 2,
}

/// Security alert
#[derive(Clone, Debug)]
pub struct Alert {
    pub timestamp: DateTime<Utc>,
    pub priority: AlertPriority,
    pub node: u32,
    pub score: f64,
    pub reason: AnomalyReason,
}

impl Alert {
    fn from_anomaly(anomaly: AnomalyScore) -> Self {
        let priority = if anomaly.score >= 0.9 {
            AlertPriority::Critical
        } else if anomaly.score >= 0.7 {
            AlertPriority::Warning
        } else {
            AlertPriority::Info
        };
        
        Self {
            timestamp: Utc::now(),
            priority,
            node: anomaly.node,
            score: anomaly.score,
            reason: anomaly.reason,
        }
    }
}

/// Anomaly alert system
pub struct AnomalyAlertSystem {
    alerts: Arc<Mutex<Vec<Alert>>>,
    max_alerts: usize,
}

impl AnomalyAlertSystem {
    /// Create new alert system
    pub fn new() -> Self {
        Self {
            alerts: Arc::new(Mutex::new(Vec::new())),
            max_alerts: 1000,
        }
    }
    
    /// Create with custom capacity
    pub fn with_capacity(max_alerts: usize) -> Self {
        Self {
            alerts: Arc::new(Mutex::new(Vec::with_capacity(max_alerts))),
            max_alerts,
        }
    }
    
    /// Emit an alert from anomaly score
    pub fn emit(&self, anomaly: AnomalyScore) {
        let alert = Alert::from_anomaly(anomaly);
        
        // Log based on priority
        match alert.priority {
            AlertPriority::Critical => {
                error!(
                    "🚨 P0 CRITICAL ANOMALY: node={}, score={:.3}, reason={:?}",
                    alert.node, alert.score, alert.reason
                );
            }
            AlertPriority::Warning => {
                warn!(
                    "⚠️  P1 WARNING: node={}, score={:.3}, reason={:?}",
                    alert.node, alert.score, alert.reason
                );
            }
            AlertPriority::Info => {
                info!(
                    "ℹ️  P2 INFO: node={}, score={:.3}, reason={:?}",
                    alert.node, alert.score, alert.reason
                );
            }
        }
        
        // Store alert
        let mut alerts = self.alerts.lock().unwrap();
        
        // Enforce max capacity (FIFO eviction)
        if alerts.len() >= self.max_alerts {
            alerts.remove(0);
        }
        
        alerts.push(alert);
    }
    
    /// Get all critical (P0) alerts
    pub fn get_critical_alerts(&self) -> Vec<Alert> {
        let alerts = self.alerts.lock().unwrap();
        alerts
            .iter()
            .filter(|a| a.priority == AlertPriority::Critical)
            .cloned()
            .collect()
    }
    
    /// Get all alerts above a priority threshold
    pub fn get_alerts_above(&self, min_priority: AlertPriority) -> Vec<Alert> {
        let alerts = self.alerts.lock().unwrap();
        alerts
            .iter()
            .filter(|a| a.priority <= min_priority)
            .cloned()
            .collect()
    }
    
    /// Get alert count by priority
    pub fn count_by_priority(&self, priority: AlertPriority) -> usize {
        let alerts = self.alerts.lock().unwrap();
        alerts.iter().filter(|a| a.priority == priority).count()
    }
    
    /// Clear all alerts
    pub fn clear(&self) {
        let mut alerts = self.alerts.lock().unwrap();
        alerts.clear();
    }
    
    /// Get total alert count
    pub fn total_count(&self) -> usize {
        let alerts = self.alerts.lock().unwrap();
        alerts.len()
    }
}

impl Default for AnomalyAlertSystem {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_alert_priority_from_score() {
        let anomaly_critical = AnomalyScore {
            node: 1,
            score: 0.95,
            reason: AnomalyReason::NegativeCycle,
        };
        
        let alert = Alert::from_anomaly(anomaly_critical);
        assert_eq!(alert.priority, AlertPriority::Critical);
        
        let anomaly_warning = AnomalyScore {
            node: 2,
            score: 0.75,
            reason: AnomalyReason::NegativeCycle,
        };
        
        let alert = Alert::from_anomaly(anomaly_warning);
        assert_eq!(alert.priority, AlertPriority::Warning);
    }
    
    #[test]
    fn test_alert_system_capacity() {
        let system = AnomalyAlertSystem::with_capacity(3);
        
        for i in 0..5 {
            let anomaly = AnomalyScore {
                node: i,
                score: 0.9,
                reason: AnomalyReason::NegativeCycle,
            };
            system.emit(anomaly);
        }
        
        // Should only keep last 3 alerts
        assert_eq!(system.total_count(), 3);
    }
    
    #[test]
    fn test_filter_by_priority() {
        let system = AnomalyAlertSystem::new();
        
        // Add mix of priorities
        system.emit(AnomalyScore { node: 1, score: 0.95, reason: AnomalyReason::NegativeCycle });
        system.emit(AnomalyScore { node: 2, score: 0.75, reason: AnomalyReason::LowCoverage });
        system.emit(AnomalyScore { node: 3, score: 0.55, reason: AnomalyReason::BpDivergence });
        
        let critical = system.get_critical_alerts();
        assert_eq!(critical.len(), 1);
        assert_eq!(critical[0].node, 1);
        
        let warnings_and_above = system.get_alerts_above(AlertPriority::Warning);
        assert_eq!(warnings_and_above.len(), 2);
    }
}
