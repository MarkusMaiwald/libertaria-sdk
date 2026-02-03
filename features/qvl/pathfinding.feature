Feature: A* Trust Pathfinding
  As a Libertaria agent
  I need to find reputation-guided paths through the trust graph
  So that I can verify trust relationships efficiently

  Background:
    Given a QVL database with the following trust topology:
      | from    | to      | level | risk  | reputation |
      | alice   | bob     | 3     | -0.3  | 0.8        |
      | bob     | charlie | 3     | -0.3  | 0.7        |
      | alice   | dave    | 3     | -0.3  | 0.9        |
      | dave    | charlie | 3     | -0.3  | 0.6        |
      | bob     | eve     | 3     | -0.3  | 0.2        |

  # Basic Pathfinding
  Scenario: Find shortest trust path
    When I search for a path from "alice" to "charlie"
    Then the path should be: "alice" → "bob" → "charlie"
    And the total cost should be approximately 0.6

  Scenario: No path exists
    When I search for a path from "alice" to "frank"
    Then the path should be null
    And the result should indicate "no path found"

  Scenario: Direct path preferred over indirect
    Given "alice" has direct trust level 7 to "charlie"
    When I search for a path from "alice" to "charlie"
    Then the path should be: "alice" → "charlie"
    And the path length should be 1

  # Reputation-Guided Pathfinding
  Scenario: Reputation heuristic avoids low-reputation nodes
    When I search for a path from "alice" to "eve"
    Then the path should be: "alice" → "bob" → "eve"
    And the algorithm should penalize "bob" for low reputation (0.2)

  Scenario: Zero heuristic degrades to Dijkstra
    When I search with zero heuristic from "alice" to "charlie"
    Then the result should be optimal (guaranteed shortest path)
    But the search should expand more nodes than with reputation heuristic

  # Path Verification
  Scenario: Verify constructed path
    Given a path: "alice" → "bob" → "charlie"
    When I verify the path against the graph
    Then each edge in the path should exist
    And no edge should be expired
    And the path verification should succeed

  Scenario: Verify path with expired edge
    Given a path: "alice" → "bob" → "charlie"
    And the edge "bob" → "charlie" has expired
    When I verify the path
    Then the verification should fail
    And the error should indicate "expired edge at hop 2"

  # Proof-of-Path
  Scenario: Generate Proof-of-Path bundle
    Given a valid path: "alice" → "bob" → "charlie"
    When I generate a Proof-of-Path
    Then the PoP should contain all edge signatures
    And the PoP should be verifiable by any node
    And the PoP should have a timestamp and entropy stamp

  Scenario: Verify Proof-of-Path
    Given a Proof-of-Path from "alice" to "charlie"
    When any node verifies the PoP
    Then the verification should succeed if all signatures are valid
    And the verification should fail if any signature is invalid

  # Path Constraints
  Scenario: Maximum path depth
    When I search for a path with max_depth 2 from "alice" to "charlie"
    And the shortest path requires 3 hops
    Then the search should return null
    And indicate "max depth exceeded"

  Scenario: Minimum trust threshold
    When I search for a path with minimum_trust_level 5
    And all edges have level 3
    Then no path should be found
    And the result should indicate "trust threshold not met"
