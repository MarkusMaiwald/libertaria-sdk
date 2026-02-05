/**
 * QVL FFI Test - C ABI Validation
 *
 * Tests:
 * - Context lifecycle
 * - Trust scoring
 * - Graph mutations
 * - Error handling
 */

#include "qvl.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>

void test_context_lifecycle() {
    printf("Test: Context lifecycle...\n");
    
    QvlContext* ctx = qvl_init();
    assert(ctx != NULL && "qvl_init should return non-NULL");
    
    qvl_deinit(ctx);
    printf("  PASS\n");
}

void test_trust_scoring() {
    printf("Test: Trust scoring...\n");
    
    QvlContext* ctx = qvl_init();
    assert(ctx != NULL);
    
    // Get reputation for unknown node (should return neutral 0.5)
    double score = qvl_get_reputation(ctx, 42);
    assert(score == 0.5 && "Unknown node should have neutral reputation");
    
    qvl_deinit(ctx);
    printf("  PASS\n");
}

void test_add_edge() {
    printf("Test: Add trust edge...\n");
    
    QvlContext* ctx = qvl_init();
    assert(ctx != NULL);
    
    QvlRiskEdge edge = {
        .from = 0,
        .to = 1,
        .risk = 0.5,
        .timestamp_ns = 1000,
        .nonce = 0,
        .level = 3,
        .expires_at_ns = 2000
    };
    
    int result = qvl_add_trust_edge(ctx, &edge);
    assert(result == 0 && "Adding edge should succeed");
    
    qvl_deinit(ctx);
    printf("  PASS\n");
}

void test_revoke_edge() {
    printf("Test: Revoke trust edge...\n");
    
    QvlContext* ctx = qvl_init();
    assert(ctx != NULL);
    
    // Add edge first
    QvlRiskEdge edge = {
        .from = 0,
        .to = 1,
        .risk = 0.5,
        .timestamp_ns = 1000,
        .nonce = 0,
        .level = 3,
        .expires_at_ns = 2000
    };
    qvl_add_trust_edge(ctx, &edge);
    
    // Revoke it
    int result = qvl_revoke_trust_edge(ctx, 0, 1);
    assert(result == 0 && "Revoking existing edge should succeed");
    
    // Try to revoke again (should fail)
    result = qvl_revoke_trust_edge(ctx, 0, 1);
    assert(result == -2 && "Revoking non-existent edge should return -2");
    
    qvl_deinit(ctx);
    printf("  PASS\n");
}

void test_get_trust_score() {
    printf("Test: Get trust score by DID...\n");
    
    QvlContext* ctx = qvl_init();
    assert(ctx != NULL);
    
    uint8_t did[32];
    memset(did, 0x42, 32);
    
    double score = qvl_get_trust_score(ctx, did, 32);
    assert(score == 0.5 && "Unknown DID should have neutral score");
    
    // Invalid length
    score = qvl_get_trust_score(ctx, did, 16);
    assert(score == -1.0 && "Invalid DID length should return -1.0");
    
    qvl_deinit(ctx);
    printf("  PASS\n");
}

void test_null_safety() {
    printf("Test: NULL safety...\n");
    
    // All functions should handle NULL context gracefully
    double score = qvl_get_reputation(NULL, 0);
    assert(score == -1.0 && "NULL context should return error");
    
    qvl_deinit(NULL); // Should not crash
    
    printf("  PASS\n");
}

int main() {
    printf("=== QVL FFI C ABI Validation ===\n\n");
    
    test_context_lifecycle();
    test_trust_scoring();
    test_add_edge();
    test_revoke_edge();
    test_get_trust_score();
    test_null_safety();
    
    printf("\n=== All tests passed! ===\n");
    return 0;
}
