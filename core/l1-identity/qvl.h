/**
 * QVL C API - Quasar Vector Lattice Trust Substrate
 *
 * C ABI for L1 identity/trust layer. Enables Rust Membrane Agents
 * and other C-compatible languages to consume QVL functions.
 *
 * Thread Safety: Single-threaded only (initial version)
 * Memory Management: Caller owns context via qvl_init/qvl_deinit
 */

#ifndef QVL_H
#define QVL_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stddef.h>
#include <stdint.h>

/* ========================================================================
 * OPAQUE CONTEXT
 * ======================================================================== */

/**
 * Opaque handle for QVL context
 * Contains: risk graph, reputation map, trust graph
 */
typedef struct QvlContext QvlContext;

/* ========================================================================
 * ENUMS
 * ======================================================================== */

/**
 * Proof-of-Path verification verdict
 */
typedef enum {
    QVL_POP_VALID = 0,              /**< Path is valid */
    QVL_POP_INVALID_ENDPOINTS = 1,  /**< Sender/receiver mismatch */
    QVL_POP_BROKEN_LINK = 2,        /**< Missing trust edge in path */
    QVL_POP_REVOKED = 3,            /**< Trust edge was revoked */
    QVL_POP_REPLAY = 4              /**< Replay attack detected */
} QvlPopVerdict;

/**
 * Anomaly detection reason
 */
typedef enum {
    QVL_ANOMALY_NONE = 0,           /**< No anomaly */
    QVL_ANOMALY_NEGATIVE_CYCLE = 1, /**< Bellman-Ford negative cycle */
    QVL_ANOMALY_LOW_COVERAGE = 2,   /**< Gossip partition detected */
    QVL_ANOMALY_BP_DIVERGENCE = 3   /**< Belief Propagation divergence */
} QvlAnomalyReason;

/* ========================================================================
 * STRUCTS
 * ======================================================================== */

/**
 * Anomaly score from betrayal detection
 */
typedef struct {
    uint32_t node;      /**< Node ID flagged */
    double score;       /**< 0.0-1.0 (0.9+ = critical) */
    uint8_t reason;     /**< QvlAnomalyReason enum */
} QvlAnomalyScore;

/**
 * Risk edge for graph mutations
 */
typedef struct {
    uint32_t from;          /**< Source node ID */
    uint32_t to;            /**< Target node ID */
    double risk;            /**< -1.0 to 1.0 (negative = betrayal) */
    uint64_t timestamp_ns;  /**< Nanoseconds since epoch */
    uint64_t nonce;         /**< L0 sequence for path provenance */
    uint8_t level;          /**< Trust level 0-3 */
    uint64_t expires_at_ns; /**< Expiration timestamp (ns) */
} QvlRiskEdge;

/* ========================================================================
 * CONTEXT MANAGEMENT
 * ======================================================================== */

/**
 * Initialize QVL context
 *
 * @return Opaque context handle, or NULL on allocation failure
 */
QvlContext* qvl_init(void);

/**
 * Cleanup and free QVL context
 *
 * @param ctx Context to destroy (NULL-safe)
 */
void qvl_deinit(QvlContext* ctx);

/* ========================================================================
 * TRUST SCORING
 * ======================================================================== */

/**
 * Get trust score for a DID
 *
 * @param ctx QVL context
 * @param did 32-byte DID
 * @param did_len Length of DID (must be 32)
 * @return Trust score 0.0-1.0, or -1.0 on error
 */
double qvl_get_trust_score(
    QvlContext* ctx,
    const uint8_t* did,
    size_t did_len
);

/**
 * Get reputation score for a node ID
 *
 * @param ctx QVL context
 * @param node_id Node identifier
 * @return Reputation score 0.0-1.0, or -1.0 on error
 */
double qvl_get_reputation(QvlContext* ctx, uint32_t node_id);

/* ========================================================================
 * PROOF-OF-PATH
 * ======================================================================== */

/**
 * Verify a serialized Proof-of-Path
 *
 * @param ctx QVL context
 * @param proof_bytes Serialized proof data
 * @param proof_len Length of proof bytes
 * @param sender_did 32-byte sender DID
 * @param receiver_did 32-byte receiver DID
 * @return Verification verdict (QvlPopVerdict)
 */
QvlPopVerdict qvl_verify_pop(
    QvlContext* ctx,
    const uint8_t* proof_bytes,
    size_t proof_len,
    const uint8_t* sender_did,
    const uint8_t* receiver_did
);

/* ========================================================================
 * BETRAYAL DETECTION
 * ======================================================================== */

/**
 * Run Bellman-Ford betrayal detection from source node
 *
 * @param ctx QVL context
 * @param source_node Starting node for detection
 * @return Anomaly score (0.0 = clean, 0.9+ = critical)
 */
QvlAnomalyScore qvl_detect_betrayal(QvlContext* ctx, uint32_t source_node);

/* ========================================================================
 * GRAPH MUTATIONS
 * ======================================================================== */

/**
 * Add trust edge to risk graph
 *
 * @param ctx QVL context
 * @param edge Edge to add
 * @return 0 on success, non-zero on error
 */
int qvl_add_trust_edge(QvlContext* ctx, const QvlRiskEdge* edge);

/**
 * Revoke trust edge
 *
 * @param ctx QVL context
 * @param from Source node ID
 * @param to Target node ID
 * @return 0 on success, -2 if not found
 */
int qvl_revoke_trust_edge(QvlContext* ctx, uint32_t from, uint32_t to);

#ifdef __cplusplus
}
#endif

#endif /* QVL_H */
