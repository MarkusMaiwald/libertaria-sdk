Feature: Proof-of-Path Integration with Reputation
  As a Libertaria security validator
  I need to verify trust paths cryptographically
  And maintain reputation scores based on verification history
  So that trust decay reflects actual behavior

  Background:
    Given a QVL database with established trust edges
    And a reputation map for all nodes

  # Reputation Scoring
  Scenario: Initial neutral reputation
    Given a new node "frank" joins the network
    Then "frank"'s reputation score should be 0.5 (neutral)
    And total_checks should be 0

  Scenario: Reputation increases with successful verification
    When node "alice" sends a PoP that verifies successfully
    Then "alice"'s reputation should increase
    And the increase should be damped (not immediate 1.0)
    And successful_checks should increment

  Scenario: Reputation decreases with failed verification
    When node "bob" sends a PoP that fails verification
    Then "bob"'s reputation should decrease
    And the decrease should be faster than increases (asymmetry)
    And total_checks should increment

  Scenario: Bayesian reputation update formula
    Given "charlie" has reputation 0.6 after 10 checks
    When a new verification succeeds
    Then the update should be: score = 0.7*0.6 + 0.3*(10/11)
    And the new score should be approximately 0.645

  # Reputation Decay
  Scenario: Time-based reputation decay
    Given "alice" has reputation 0.8 from verification at time T
    When half_life time passes without new verification
    Then "alice"'s reputation should decay to ~0.4
    When another half_life passes
    Then reputation should decay to ~0.2

  Scenario: Decay stops at minimum threshold
    Given "bob" has reputation 0.1 (low but not zero)
    When significant time passes
    Then "bob"'s reputation should not go below 0.05 (floor)

  # PoP Verification Flow
  Scenario: Successful PoP verification
    Given a valid Proof-of-Path from "alice" to "charlie"
    When I verify against the expected receiver and sender
    Then the verdict should be "valid"
    And "alice"'s reputation should increase
    And the verification should be logged with entropy stamp

  Scenario: Broken link in PoP
    Given a PoP with an edge that no longer exists
    When I verify the PoP
    Then the verdict should be "broken_link"
    And the specific broken edge should be identified
    And "alice"'s reputation should decrease

  Scenario: Expired edge in PoP
    Given a PoP containing an expired trust edge
    When I verify the PoP
    Then the verdict should be "expired"
    And the expiration timestamp should be reported

  Scenario: Invalid signature in PoP
    Given a PoP with a tampered signature
    When I verify the PoP
    Then the verdict should be "invalid_signature"
    And "alice"'s reputation should decrease significantly

  # A* Heuristic Integration
  Scenario: Reputation-guided pathfinding
    Given "alice" has reputation 0.9
    And "bob" has reputation 0.3
    When searching for a path through either node
    Then the algorithm should prefer "alice" (higher reputation)
    And the path cost through "alice" should be lower

  Scenario: Admissible heuristic guarantee
    Given any reputation configuration
    When using reputationHeuristic for A*
    Then the heuristic should never overestimate true cost
    And A* optimality should be preserved

  # Low Reputation Handling
  Scenario: Identify low-reputation nodes
    Given nodes with reputations:
      | node    | reputation |
      | alice   | 0.9        |
      | bob     | 0.2        |
      | charlie | 0.1        |
    When I query for nodes below threshold 0.3
    Then I should receive ["bob", "charlie"]

  Scenario: Quarantine trigger
    Given "mallory" has reputation < 0.2 after 10+ checks
    When the low-reputation threshold is 0.2
    Then "mallory" should be flagged for quarantine review
    And future PoPs from "mallory" should be extra scrutinized

  # Bulk Operations
  Scenario: Decay all reputations periodically
    Given 1000 nodes with various last_verified times
    When the daily decay job runs
    Then all reputations should be updated based on time since last verification
    And the operation should complete in < 100ms

  Scenario: Populate RiskGraph from reputation
    Given a CompactTrustGraph with raw trust levels
    And a ReputationMap with scores
    When I populate the RiskGraph
    Then each edge risk should be calculated as (1 - reputation)
    And the RiskGraph should be ready for Bellman-Ford
