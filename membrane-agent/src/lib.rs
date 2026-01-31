//! Membrane Agent - L2 Trust-Based Policy Enforcement
//!
//! Library components for the Membrane Agent daemon.

pub mod qvl_ffi;
pub mod policy_enforcer;
pub mod anomaly_alerts;
pub mod event_listener;

pub use qvl_ffi::{
    QvlClient, QvlError, AnomalyScore, AnomalyReason,
    PopVerdict, QvlRiskEdge,
};
pub use policy_enforcer::{PolicyEnforcer, PolicyDecision};
pub use anomaly_alerts::{AnomalyAlertSystem, Alert, AlertPriority};
pub use event_listener::{EventListener, EventListenerConfig, L0Event};
