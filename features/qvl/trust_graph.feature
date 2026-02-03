Feature: QVL Trust Graph Core
  As a Libertaria node operator
  I need to manage trust relationships in a graph
  So that I can establish verifiable trust paths between agents

  Background:
    Given a new QVL database is initialized
    And the following DIDs are registered:
      | did           | alias    |
      | did:alice:123 | alice    |
      | did:bob:456   | bob      |
      | did:charlie:789 | charlie |

  # RiskGraph Basic Operations
  Scenario: Add trust edge between two nodes
    When "alice" grants trust level 3 to "bob"
    Then the graph should contain an edge from "alice" to "bob"
    And the edge should have trust level 3
    And "bob" should be in "alice"'s outgoing neighbors

  Scenario: Remove trust edge
    Given "alice" has granted trust to "bob"
    When "alice" revokes trust from "bob"
    Then the edge from "alice" to "bob" should not exist
    And "bob" should not be in "alice"'s outgoing neighbors

  Scenario: Query incoming trust edges
    Given "alice" has granted trust to "charlie"
    And "bob" has granted trust to "charlie"
    When I query incoming edges for "charlie"
    Then I should receive 2 edges
    And the edges should be from "alice" and "bob"

  Scenario: Trust edge with TTL expiration
    When "alice" grants trust level 5 to "bob" with TTL 86400 seconds
    Then the edge should have an expiration timestamp
    And the edge should be valid immediately
    When 86401 seconds pass
    Then the edge should be expired
    And querying the edge should return null

  # RiskEdge Properties
  Scenario Outline: Risk score calculation from trust level
    When "alice" grants trust level <level> to "bob"
    Then the risk score should be <risk>

    Examples:
      | level | risk  |
      | 7     | -1.0  |
      | 3     | -0.3  |
      | 0     | 0.0   |
      | -3    | 0.3   |
      | -7    | 1.0   |

  Scenario: Edge metadata includes entropy stamp
    When "alice" grants trust to "bob" at entropy 1234567890
    Then the edge should have entropy stamp 1234567890
    And the edge should have a unique nonce

  Scenario: Betrayal edge detection
    When "alice" grants trust level -7 to "bob"
    Then the edge should be marked as betrayal
    And the risk score should be positive
