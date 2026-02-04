Feature: RFC-0015 Polymorphic Noise Generator (PNG)
  As a Libertaria protocol developer
  I want cryptographically secure per-session traffic shaping
  So that state-level DPI cannot fingerprint or correlate sessions

  Background:
    Given the PNG is initialized with ChaCha20 RNG
    And the entropy source is the ECDH shared secret

  # ============================================================================
  # Seed Derivation and Determinism
  # ============================================================================

  Scenario: PNG seed derives from ECDH shared secret
    Given Alice and Bob perform X25519 ECDH
    And the shared secret is 32 bytes
    When Alice derives PNG seed via HKDF-SHA256
    And Bob derives PNG seed via HKDF-SHA256
    Then both seeds should be 256 bits
    And the seeds should be identical
    And the derivation should use "Libertaria-PNG-v1" as context

  Scenario: Different sessions produce different seeds
    Given Alice and Bob perform ECDH for Session A
    And Alice and Bob perform ECDH for Session B
    When PNG seeds are derived for both sessions
    Then the seeds should be different
    And the Hamming distance should be ~128 bits

  Scenario: PNG seed has sufficient entropy
    Given 1000 independent ECDH handshakes
    When PNG seeds are derived for all sessions
    Then no seed collisions should occur
    And the distribution should pass Chi-square randomness test

  # ============================================================================
  # Epoch Profile Generation
  # ============================================================================

  Scenario: Epoch profile contains all noise parameters
    Given a PNG with valid seed
    When the first epoch profile is generated
    Then it should contain size_distribution variant
    And size_mean and size_stddev parameters
    And timing_distribution variant
    And timing_lambda parameter
    And dummy_probability between 0.0 and 0.15
    And epoch_packet_count between 100 and 1000

  Scenario: Sequential epochs are deterministic
    Given a PNG with seed S
    When epoch 0 profile is generated
    And epoch 1 profile is generated
    And a second PNG with same seed S
    When epoch 0 and 1 profiles are generated again
    Then all corresponding epochs should match exactly

  Scenario: Different seeds produce uncorrelated epochs
    Given PNG A with seed S1
    And PNG B with seed S2
    When 10 epochs are generated for both
    Then size_mean of corresponding epochs should not correlate
    And timing_lambda values should not correlate
    And Kolmogorov-Smirnov test should show different distributions

  # ============================================================================
  # Packet Size Noise
  # ============================================================================

  Scenario Outline: Packet size distributions match theoretical models
    Given the epoch profile specifies <distribution> distribution
    And size_mean = <mean> bytes
    And size_stddev = <stddev> bytes
    When 10000 packet sizes are sampled
    Then the empirical distribution should match theoretical <distribution>
    And the Chi-square test p-value should be > 0.05

    Examples:
      | distribution | mean  | stddev |
      | Normal       | 1440  | 200    |
      | Pareto       | 1440  | 400    |
      | Bimodal      | 1200  | 300    |
      | LogNormal    | 1500  | 250    |

  Scenario: Packet sizes stay within valid bounds
    Given any epoch profile
    When packet sizes are sampled
    Then all sizes should be >= 64 bytes
    And all sizes should be <= 1500 bytes (Ethernet MTU)
    And sizes should never exceed interface MTU

  Scenario: Bimodal distribution matches video streaming
    Given video streaming capture data
    And epoch specifies Bimodal distribution
    When PNG samples packet sizes
    Then the two modes should be at ~600 bytes and ~1440 bytes
    And the ratio should be approximately 1:3
    And the distribution should match YouTube 1080p captures

  # ============================================================================
  # Timing Noise (Inter-packet Jitter)
  # ============================================================================

  Scenario Outline: Timing distributions match theoretical models
    Given the epoch profile specifies <distribution> timing
    And timing_lambda = <lambda>
    When 10000 inter-packet delays are sampled
    Then the empirical distribution should match theoretical <distribution>

    Examples:
      | distribution | lambda |
      | Exponential  | 0.01   |
      | Gamma        | 0.005  |
      | Pareto       | 0.001  |

  Scenario: Timing jitter prevents clock skew attacks
    Given an adversary measures inter-packet timing
    When the PNG applies jitter with Exponential distribution
    Then the coefficient of variation should be high (>0.5)
    And timing side-channel attacks should fail

  Scenario: Maximum latency bound enforcement
    Given real-time voice application requirements
    And maximum acceptable latency of 500ms
    When timing noise is applied
    Then no single packet should be delayed >500ms
    And 99th percentile latency should be <300ms

  # ============================================================================
  # Dummy Packet Injection
  # ============================================================================

  Scenario: Dummy injection rate follows probability
    Given dummy_probability = 0.10 (10%)
    When 10000 transmission opportunities occur
    Then approximately 1000 dummy packets should be injected
    And the binomial 95% confidence interval should contain the count

  Scenario: Dummy packets are indistinguishable from real
    Given a mix of real and dummy packets
    When examined by adversary
    Then packet sizes should have same distribution
    And timing should follow same patterns
    And entropy analysis should not distinguish them

  Scenario: Bursty dummy injection pattern
    Given dummy_distribution = Bursty
    And dummy_probability = 0.15
    When dummies are injected
    Then they should arrive in clusters (bursts)
    And inter-burst gaps should follow exponential distribution
    And intra-burst timing should be rapid

  # ============================================================================
  # Epoch Rotation
  # ============================================================================

  Scenario: Epoch rotates after packet count threshold
    Given epoch_packet_count = 500
    When 499 packets are transmitted
    Then the profile should remain unchanged
    When the 500th packet is transmitted
    Then epoch rotation should trigger
    And a new epoch profile should be generated

  Scenario: Epoch rotation preserves session state
    Given an active encrypted session
    And epoch rotation triggers
    When the new epoch begins
    Then encryption keys should remain valid
    And sequence numbers should continue monotonically
    And no rekeying should be required

  Scenario: Maximum epoch duration prevents indefinite exposure
    Given epoch_packet_count = 1000
    And a low-bandwidth application sends 1 packet/minute
    When 60 minutes elapse with only 60 packets
    Then the epoch should rotate anyway (time-based fallback)
    And the maximum epoch duration should be 10 minutes

  # ============================================================================
  # Integration with Transport Skins
  # ============================================================================

  Scenario: PNG noise applied before skin wrapping
    Given MIMIC_HTTPS skin is active
    And an LWF frame of 1350 bytes
    When PNG adds padding noise
    Then the total size should follow epoch's distribution
    And the padding should be added before TLS encryption
    And the WebSocket frame should contain padded payload

  Scenario: PNG noise subtraction by receiving peer
    Given PNG adds 50 bytes of padding to a packet
    When the packet arrives at destination
    And the peer uses same PNG seed
    Then the padding should be identifiable
    And the original 1350-byte LWF frame should be recoverable

  Scenario: Different skins use same PNG instance
    Given a session starts with RAW skin
    And PNG is seeded
    When skin switches to MIMIC_HTTPS
    Then the PNG should continue same epoch sequence
    And noise patterns should remain consistent

  # ============================================================================
  # Statistical Security Tests
  # ============================================================================

  Scenario: NIST SP 800-22 randomness tests
    Given 1MB of PNG output (ChaCha20 keystream)
    When subjected to NIST statistical test suite
    Then all 15 tests should pass
    Including Frequency, Runs, FFT, Template matching

  Scenario: Dieharder randomness tests
    Given 10MB of PNG output
    When subjected to Dieharder test suite
    Then no tests should report "WEAK" or "FAILED"

  Scenario: Avalanche effect on seed changes
    Given PNG seed S1 produces output stream O1
    When one bit is flipped in seed (S2 = S1 XOR 0x01)
    And output stream O2 is generated
    Then O1 and O2 should differ in ~50% of bits
    And the correlation coefficient should be ~0

  # ============================================================================
  # Performance and Resource Usage
  # ============================================================================

  Scenario: PNG generation is fast enough for line rate
    Given 1 Gbps network interface
    And 1500 byte packets
    When PNG generates noise for each packet
    Then generation time should be <1μs per packet
    And CPU usage should be <5% of one core

  Scenario: PNG memory footprint is minimal
    Given the PNG is initialized
    When measuring memory usage
    Then ChaCha20 state should use ≤136 bytes
    And epoch profile should use ≤64 bytes
    And total PNG overhead should be <1KB per session

  Scenario: PNG works on constrained devices
    Given a device with 10MB RAM (Kenya compliance)
    When 1000 concurrent sessions are active
    Then total PNG memory should be <10MB
    And each session PNG overhead should be <10KB
