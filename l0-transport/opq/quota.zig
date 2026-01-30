//! RFC-0020: OPQ (Offline Packet Queue) - Quota & Policy
//!
//! This module defines the "Policy" layer of the OPQ:
//! Node personas, retention periods, and storage limits.

const std = @import("std");

pub const Persona = enum {
    client,
    relay,
    gateway,
};

pub const Policy = struct {
    persona: Persona,
    max_retention_seconds: i64,
    max_storage_bytes: u64,
    segment_size: usize,

    pub fn init(persona: Persona) Policy {
        return switch (persona) {
            .client => Policy{
                .persona = .client,
                .max_retention_seconds = 3600, // 1 hour
                .max_storage_bytes = 5 * 1024 * 1024, // 5MB
                .segment_size = 1024 * 1024, // 1MB segments
            },
            .relay, .gateway => Policy{
                .persona = persona,
                .max_retention_seconds = 96 * 3600, // 96 hours
                .max_storage_bytes = 10 * 1024 * 1024 * 1024, // 10GB default
                .segment_size = 4 * 1024 * 1024, // 4MB segments
            },
        };
    }
};
