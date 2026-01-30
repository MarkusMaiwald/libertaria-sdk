//! Force compilation and export of all crypto FFI functions
//! This module is imported by test harnesses to ensure Zig-exported functions
//! are available to C code that calls them.

pub const fips202_bridge = @import("fips202_bridge.zig");

// Re-export key functions to ensure they're included in the binary
pub const shake128 = fips202_bridge.shake128;
pub const shake256 = fips202_bridge.shake256;
pub const sha3_256 = fips202_bridge.sha3_256;
pub const sha3_512 = fips202_bridge.sha3_512;
pub const kyber_shake128_absorb_once = fips202_bridge.kyber_shake128_absorb_once;
pub const kyber_shake256_prf = fips202_bridge.kyber_shake256_prf;
