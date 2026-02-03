Feature: Loopy Belief Propagation
  As a Libertaria node under eclipse attack
  I need Bayesian inference over the trust DAG
  So that I can estimate trust under uncertainty and detect anomalies

  Background:
    Given a trust graph with partial visibility:
      | from    | to      | observed | prior_trust |
      | alice   | bob     | true     | 0.6         |
      | bob     | charlie | false    | unknown     |
      | alice   | dave    | true     | 0.8         |

  # Belief Propagation Core
  Scenario: Propagate beliefs through observed edges
    When I run Belief Propagation from "alice"
    Then the belief for "bob" should converge to ~0.6
    And the belief for "alice" should be 1.0 (self-trust)

  Scenario: Infer unobserved edge from network structure
    Given "alice" trusts "bob" (0.6)
    And "bob" is likely to trust "charlie" (transitivity)
    When I run BP with max_iterations 100
    Then the belief for "charlie" should be > 0.5
    And < 0.6 (less certain than direct observation)

  Scenario: Convergence detection
    When I run BP with epsilon 1e-6
    Then the algorithm should stop when max belief delta < epsilon
    And the converged flag should be true
    And iterations should be < max_iterations

  Scenario: Non-convergence handling
    Given a graph with oscillating beliefs (bipartite structure)
    When I run BP with damping 0.5
    Then the algorithm should force convergence via damping
    Or report non-convergence after max_iterations

  # Anomaly Scoring
  Scenario: Anomaly from BP divergence
    Given a node with belief 0.9 from one path
    And belief 0.1 from another path (conflict)
    When BP converges
    Then the anomaly score should be high (> 0.7)
    And the reason should be "bp_divergence"

  Scenario: Eclipse attack detection
    Given an adversary controls 90% of observed edges to "victim"
    And the adversary reports uniformly positive trust
    When BP runs with honest nodes as priors
    Then the victim's belief should remain moderate (not extreme)
    And the coverage metric should indicate "potential_eclipse"

  # Damping and Stability
  Scenario Outline: Damping factor effects
    Given a graph prone to oscillation
    When I run BP with damping <damping>
    Then convergence should occur in <iterations> iterations

    Examples:
      | damping | iterations |
      | 0.0     | > 100     |
      | 0.5     | ~50        |
      | 0.9     | ~20        |

  # Integration with Bellman-Ford
  Scenario: BP complements negative cycle detection
    Given a graph with a near-negative-cycle (ambiguous betrayal)
    When Bellman-Ford is inconclusive
    And BP reports high anomaly for involved nodes
    Then the combined evidence suggests investigation

  # Performance Constraints
  Scenario: BP complexity
    Given a graph with 1000 nodes and 5000 edges
    When I run BP with epsilon 1e-6
    Then convergence should occur within 50 iterations
    And total time should be < 100ms
    And memory should be O(|V| + |E|)
