//! Membrane Agent - L2 Trust-Based Policy Enforcement
//!
//! Library components for the Membrane Agent daemon.

pub mod qvl_ffi;

pub use qvl_ffi::{
    QvlClient, QvlError, AnomalyScore, AnomalyReason,
    PopVerdict, QvlRiskEdge,
};
