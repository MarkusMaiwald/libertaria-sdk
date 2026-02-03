Feature: Aleph-Style Gossip Protocol
  As a Libertaria node in a partitioned network
  I need probabilistic message flooding with DAG references
  So that trust signals propagate despite intermittent connectivity

  Background:
    Given a network of 5 nodes: alpha, beta, gamma, delta, epsilon
    And each node has initialized gossip state
    And the erasure tolerance parameter k = 3

  # Gossip Message Structure
  Scenario: Create gossip message with DAG references
    Given node "alpha" has received messages with IDs [100, 101, 102]
    When "alpha" creates a gossip message of type "trust_vouch"
    Then the message should reference k=3 prior messages
    And the message ID should be computed from (sender + entropy + payload)
    And the message should have an entropy stamp

  Scenario: Gossip message types
    When I create a gossip message of type "<type>"
    Then the message type code should be <code>

    Examples:
      | type              | code |
      | trust_vouch       | 0    |
      | trust_revoke      | 1    |
      | reputation_update | 2    |
      | heartbeat         | 3    |

  # Probabilistic Flooding
  Scenario: Message propagation probability
    Given node "alpha" broadcasts a gossip message
    When the message reaches "beta"
    Then "beta" should forward with probability p = 0.7
    And the expected coverage after 3 hops should be > 80%

  Scenario: Duplicate detection via message ID
    Given node "beta" has seen message ID 12345
    When "beta" receives message ID 12345 again
    Then "beta" should not forward the duplicate
    And "beta" should update the seen timestamp

  # DAG Structure and Partition Detection
  Scenario: Build gossip DAG
    Given the following gossip sequence:
      | sender | refs      |
      | alpha  | []        |
      | beta   | [alpha:1] |
      | gamma  | [alpha:1, beta:1] |
    Then the DAG should have 3 nodes
    And "gamma" should have 2 incoming edges
    And the DAG depth should be 2

  Scenario: Detect network partition via coverage
    Given the network has partitioned into [alpha, beta] and [gamma, delta]
    When "alpha" tracks gossip coverage
    And messages from "alpha" fail to reach "gamma" for 60 seconds
    Then "alpha" should report "low_coverage" anomaly
    And the anomaly score should be > 0.7

  Scenario: Heal partition upon reconnection
    Given a partition exists between [alpha, beta] and [gamma]
    When the partition heals and "beta" reconnects to "gamma"
    Then "beta" should sync missing gossip messages
    And "gamma" should acknowledge receipt
    And the coverage anomaly should resolve

  # Entropy and Replay Protection
  Scenario: Entropy stamp ordering
    Given message A with entropy 1000
    And message B with entropy 2000
    Then message B is newer than message A
    And a node should reject messages with entropy < last_seen - window

  Scenario: Replay attack prevention
    Given node "alpha" has entropy window [1000, 2000]
    When "alpha" receives a message with entropy 500
    Then the message should be rejected as "stale"
    And "alpha" should not forward it

  # Erasure Tolerance
  Scenario: Message loss tolerance
    Given a gossip DAG with k=3 references per message
    When 30% of messages are lost randomly
    Then the DAG should remain connected with > 95% probability
    And reconstruction should be possible via redundant paths

  # Performance (Kenya Rule)
  Scenario: Gossip overhead
    Given a network with 1000 nodes
    When each node sends 1 message per minute
    Then the bandwidth per node should be < 10 KB/minute
    And the memory for gossip state should be < 1 MB
