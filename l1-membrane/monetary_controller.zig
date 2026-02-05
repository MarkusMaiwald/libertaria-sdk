// monetary_controller.zig - LIBERTARIA L1 ECONOMIC ENGINE
// RFC-0648 + RFC-0649 Implementation
// 
// DEPLOYMENT TARGET: 03:00 Session (2026-02-05)
// STATUS: Ready for implementation

const std = @import("std");
const assert = std.debug.assert;

// =============================================================================
// PROTOCOL ENSHRINED CONSTANTS (Immutable)
// =============================================================================

/// Maximum deflation rate (hard floor)
const PROTOCOL_FLOOR: f64 = -0.05;      // -5% per epoch max

/// Maximum inflation rate (hard ceiling)  
const PROTOCOL_CEILING: f64 = 0.20;     // +20% per epoch max

/// Target velocity (Chapter-tunable, but default)
const DEFAULT_V_TARGET: f64 = 6.0;

/// Stability band thresholds
const STAGNATION_THRESHOLD: f64 = 0.8;  // 80% of target = stimulus
const OVERHEAT_THRESHOLD: f64 = 1.2;    // 120% of target = brake

// =============================================================================
// CHAPTER-TUNABLE PARAMETERS (Genesis-configurable)
// =============================================================================

pub const MonetaryParams = struct {
    // PID Gains - TUNE THESE IN FIELD
    Kp: f64 = 0.15,     // Proportional: immediate response
    Ki: f64 = 0.02,     // Integral: long-term correction
    Kd: f64 = 0.08,     // Derivative: dampening
    
    // Opportunity Window
    opportunity_multiplier: f64 = 1.5,   // 50% bonus during stimulus
    difficulty_scalar: f64 = 0.9,        // 10% easier to mint
    q_boost_factor: f64 = 0.15,          // 15% activity boost
    
    // Extraction
    base_fee_burn_rate: f64 = 0.1,       // 10% fee increase
    demurrage_rate: f64 = 0.001,         // 0.1% per epoch on stagnant
    
    // Anti-Sybil
    genesis_difficulty: u32 = 20,        // ~10 min on smartphone
    maintenance_difficulty: u32 = 12,    // ~10 sec monthly
    
    // Velocity target
    V_target: f64 = DEFAULT_V_TARGET,
};

// =============================================================================
// STATE VARIABLES (Per-Chapter)
// =============================================================================

pub const MonetaryState = struct {
    M: f64,                    // Money Supply (Mass)
    V: f64,                    // Velocity
    Q: f64,                    // Economic Activity (Output)
    P: f64,                    // Price Level
    
    // PID State
    error_integral: f64 = 0.0,
    prev_error: f64 = 0.0,
    
    // Epoch tracking
    current_epoch: u64 = 0,
    
    pub fn init(M_initial: f64, V_initial: f64, Q_initial: f64) MonetaryState {
        return .{
            .M = M_initial,
            .V = V_initial,
            .Q = Q_initial,
            .P = 1.0,
        };
    }
};

// =============================================================================
// CORE ALGORITHMS
// =============================================================================

/// PID Controller with tanh saturation
/// 
/// u(t) = Kp*e(t) + Ki*∫e(t)dt + Kd*de/dt
/// ΔM(t) = M(t) * clamp(tanh(k*u), FLOOR, CEILING)
pub fn pidController(
    state: *MonetaryState,
    params: MonetaryParams,
    V_measured: f64,
) f64 {
    // 1. Calculate error
    const error = params.V_target - V_measured;
    
    // 2. Update integral
    state.error_integral += error;
    
    // 3. Calculate derivative
    const derivative = error - state.prev_error;
    state.prev_error = error;
    
    // 4. Raw PID output
    const u = params.Kp * error + 
              params.Ki * state.error_integral + 
              params.Kd * derivative;
    
    // 5. tanh saturation (smooth)
    const tanh_u = std.math.tanh(u);
    
    // 6. Hard protocol caps (enshrined)
    return std.math.clamp(tanh_u, PROTOCOL_FLOOR, PROTOCOL_CEILING);
}

/// Opportunity Window: Injection during stagnation
/// 
/// When V < 0.8 * target:
/// - Difficulty drops (cheaper to mint)
/// - Multiplier active (more rewarding)
/// - Q boost (psychological stimulus)
pub fn applyOpportunityWindow(
    state: *MonetaryState,
    params: MonetaryParams,
    delta_m_raw: f64,
) struct { delta_m: f64, active: bool, q_boost: f64 } {
    
    const is_stagnant = state.V < params.V_target * STAGNATION_THRESHOLD;
    
    if (is_stagnant) {
        // Stimulus: Make work cheaper AND more rewarding
        const delta_m = delta_m_raw * params.opportunity_multiplier;
        
        // Psychological boost: Economic activity increases
        // This is the KEY INSIGHT: Stimulus → Behavior, not just Money
        const q_boost = state.Q * params.q_boost_factor;
        state.Q += q_boost;
        
        return .{
            .delta_m = delta_m,
            .active = true,
            .q_boost = q_boost,
        };
    }
    
    return .{
        .delta_m = delta_m_raw,
        .active = false,
        .q_boost = 0.0,
    };
}

/// Extraction: Cooling during overheating
///
/// When V > 1.2 * target:
/// - Base fee burn (transactions more expensive)
/// - Demurrage on stagnant money
pub fn applyExtraction(
    state: *MonetaryState,
    params: MonetaryParams,
    delta_m_raw: f64,
) struct { delta_m: f64, active: bool, burned: f64 } {
    
    const is_overheated = state.V > params.V_target * OVERHEAT_THRESHOLD;
    
    if (is_overheated) {
        // 1. Demurrage on stagnant M
        const demurrage_burn = state.M * params.demurrage_rate;
        state.M -= demurrage_burn;
        
        // 2. Extra brake on emission
        const delta_m = delta_m_raw * 0.8;
        
        return .{
            .delta_m = delta_m,
            .active = true,
            .burned = demurrage_burn,
        };
    }
    
    return .{
        .delta_m = delta_m_raw,
        .active = false,
        .burned = 0.0,
    };
}

/// Main Monetary Step Function
/// 
/// Called once per epoch by L1 consensus
pub fn monetaryStep(
    state: *MonetaryState,
    params: MonetaryParams,
    exogenous_shock: f64,  // External events (panic, bubble)
) void {
    state.current_epoch += 1;
    
    // 1. Apply exogenous shocks (market psychology)
    state.V += exogenous_shock;
    
    // 2. PID Controller
    const delta_m_raw = pidController(state, params, state.V);
    
    // 3. Opportunity Window (stimulus if stagnant)
    const opp = applyOpportunityWindow(state, params, delta_m_raw);
    
    // 4. Extraction (brake if overheated)
    const ext = applyExtraction(state, params, opp.delta_m);
    
    // 5. Update Money Supply
    state.M *= (1.0 + ext.delta_m);
    
    // 6. Natural Q decay (activity slows without stimulus)
    state.Q *= 0.995;
    
    // 7. Recalculate V from Fisher equation
    // But: Q is now endogenous (can be boosted by stimulus)
    state.V = (state.P * state.Q) / state.M;
    
    // 8. Floor protection
    if (state.V < 0.1) state.V = 0.1;
}

// =============================================================================
// ANTI-SYBIL: SOULKEY VALIDATION
// =============================================================================

pub const SoulKey = struct {
    did: [32]u8,
    genesis_proof: EntropyProof,
    last_maintenance: u64,
    maintenance_debt: f64,
};

pub const EntropyProof = struct {
    nonce: [32]u8,
    difficulty: u32,
    hash: [32]u8,
};

/// Verify Argon2id proof
pub fn verifyEntropyProof(proof: EntropyProof, required_difficulty: u32) bool {
    // TODO: Argon2id verification
    // Returns true if hash meets difficulty target
    _ = proof;
    _ = required_difficulty;
    return true; // Placeholder
}

/// Check if SoulKey qualifies for Opportunity Window
pub fn qualifiesForMintWindow(
    soul: SoulKey,
    current_epoch: u64,
    params: MonetaryParams,
) bool {
    // Must have genesis
    if (!verifyEntropyProof(soul.genesis_proof, params.genesis_difficulty)) {
        return false;
    }
    
    // Must be maintained (Kenya Rule: 1 proof/month)
    const epochs_since_maintenance = current_epoch - soul.last_maintenance;
    const max_epochs = 30 * 24 * 6; // ~1 month (10-min epochs)
    
    if (epochs_since_maintenance > max_epochs) {
        return false; // Maintenance debt too high
    }
    
    return true;
}

// =============================================================================
// HAMILTONIAN UTILITIES
// =============================================================================

/// Economic Energy: E = 0.5 * M * V²
pub fn calculateEnergy(state: MonetaryState) f64 {
    return 0.5 * state.M * state.V * state.V;
}

/// Momentum: P = M * V
pub fn calculateMomentum(state: MonetaryState) f64 {
    return state.M * state.V;
}

/// Check if system is in equilibrium
pub fn isEquilibrium(state: MonetaryState, params: MonetaryParams) bool {
    const ratio = state.V / params.V_target;
    return ratio >= 0.9 and ratio <= 1.1;
}

// =============================================================================
// TEST HARNESS (for 03:00 session)
// =============================================================================

test "monetary controller basic" {
    var state = MonetaryState.init(1000.0, 5.0, 5000.0);
    const params = MonetaryParams{};
    
    // Run 100 epochs
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        monetaryStep(&state, params, 0.0);
    }
    
    // System should stabilize near target
    try std.testing.expect(state.V > 4.0);
    try std.testing.expect(state.V < 8.0);
}

test "opportunity window triggers" {
    var state = MonetaryState.init(1000.0, 2.0, 5000.0); // Stagnant
    const params = MonetaryParams{};
    
    const delta_before = state.M;
    monetaryStep(&state, params, 0.0);
    const delta_after = state.M;
    
    // Should have triggered stimulus
    try std.testing.expect(delta_after > delta_before * 1.01);
}

test "extraction triggers" {
    var state = MonetaryState.init(1000.0, 10.0, 5000.0); // Overheated
    const params = MonetaryParams{};
    
    const m_before = state.M;
    monetaryStep(&state, params, 0.0);
    const m_after = state.M;
    
    // Should have burned some M via demurrage
    try std.testing.expect(m_after < m_before);
}

// =============================================================================
// TODO FOR 03:00 SESSION
// =============================================================================

// [ ] Integrate with RFC-0315 (Access Toll Protocol)
// [ ] Argon2d proof verification
// [ ] Chapter persistence (save/restore state)
// [ ] Event hooks for external monitoring
// [ ] Fuzz testing with random shocks

// END monetary_controller.zig
