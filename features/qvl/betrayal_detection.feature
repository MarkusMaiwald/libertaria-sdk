Feature: Bellman-Ford Betrayal Detection
  As a Libertaria security node
  I need to detect negative cycles in the trust graph
  So that I can identify collusion rings and betrayal patterns

  Background:
    Given a QVL database with the following trust edges:
      | from    | to      | level | risk  |
      | alice   | bob     | 3     | -0.3  |
      | bob     | charlie | 3     | -0.3  |
      | charlie | alice   | -7    | 1.0   |

  # Negative Cycle Detection
  Scenario: Detect simple negative cycle (betrayal ring)
    When I run Bellman-Ford from "alice"
    Then a negative cycle should be detected
    And the cycle should contain nodes: "alice", "bob", "charlie"
    And the anomaly score should be 1.0 (critical)

  Scenario: No cycle in legitimate trust chain
    Given a QVL database with the following trust edges:
      | from    | to      | level | risk  |
      | alice   | bob     | 3     | -0.3  |
      | bob     | charlie | 3     | -0.3  |
      | charlie | dave    | 3     | -0.3  |
    When I run Bellman-Ford from "alice"
    Then no negative cycle should be detected
    And the anomaly score should be 0.0

  Scenario: Multiple betrayal cycles
    Given a QVL database with the following trust edges:
      | from    | to      | level | risk  |
      | alice   | bob     | -5    | 0.5   |
      | bob     | alice   | -5    | 0.5   |
      | charlie | dave    | -5    | 0.5   |
      | dave    | charlie | -5    | 0.5   |
    When I run Bellman-Ford from "alice"
    Then 2 negative cycles should be detected
    And cycle 1 should contain: "alice", "bob"
    And cycle 2 should contain: "charlie", "dave"

  # Evidence Generation
  Scenario: Generate cryptographic evidence of betrayal
    Given a negative cycle has been detected:
      | node    | risk  |
      | alice   | -0.3  |
      | bob     | -0.3  |
      | charlie | 1.0   |
    When I generate evidence for the cycle
    Then the evidence should be a byte array
    And the evidence version should be 0x01
    And the evidence should contain all 3 node IDs
    And the evidence should contain all risk scores
    And the evidence hash should be deterministic

  Scenario: Evidence serialization format
    When I generate evidence for a cycle with nodes "alice", "bob"
    Then the evidence format should be:
      """
      version(1 byte) + cycle_len(4 bytes) + 
      [node_id(4 bytes) + risk(8 bytes)]...
      """

  # Performance Constraints (Kenya Rule)
  Scenario Outline: Bellman-Ford complexity with graph size
    Given a graph with <nodes> nodes and <edges> edges
    When I run Bellman-Ford
    Then the execution time should be less than <time_ms> milliseconds
    And the memory usage should be less than 10MB

    Examples:
      | nodes | edges | time_ms |
      | 100   | 500   | 50      |
      | 1000  | 5000  | 500     |
      | 10000 | 50000 | 5000    |

  # Early Exit Optimization
  Scenario: Early exit when no improvements possible
    Given a graph where no edges can be relaxed after pass 3
    When I run Bellman-Ford
    Then the algorithm should exit after pass 3
    And not run all |V|-1 passes
