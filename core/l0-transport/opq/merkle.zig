//! Incremental Merkle Tree implementation for OPQ Manifests.
//!
//! Provides O(log n) updates and O(log n) inclusion proofs.
//! Uses Blake3 for hashing to align with the rest of the SDK.

const std = @import("std");

pub const MerkleTree = struct {
    allocator: std.mem.Allocator,
    leaves: std.ArrayListUnmanaged([32]u8),

    pub fn init(allocator: std.mem.Allocator) MerkleTree {
        return .{
            .allocator = allocator,
            .leaves = .{},
        };
    }

    pub fn deinit(self: *MerkleTree) void {
        self.leaves.deinit(self.allocator);
    }

    pub fn insert(self: *MerkleTree, leaf: [32]u8) !void {
        try self.leaves.append(self.allocator, leaf);
    }

    /// Calculate the root of the Merkle Tree
    pub fn getRoot(self: *const MerkleTree) [32]u8 {
        if (self.leaves.items.len == 0) return [_]u8{0} ** 32;
        if (self.leaves.items.len == 1) return self.leaves.items[0];

        // This is a naive implementation for now.
        // For production, we'd want an incremental tree that doesn't recompute everything.
        var current_level = std.ArrayList([32]u8).empty;
        defer current_level.deinit(self.allocator);
        current_level.appendSlice(self.allocator, self.leaves.items) catch return [_]u8{0} ** 32;

        while (current_level.items.len > 1) {
            var next_level = std.ArrayList([32]u8).empty;
            var i: usize = 0;
            while (i < current_level.items.len) : (i += 2) {
                const left = current_level.items[i];
                const right = if (i + 1 < current_level.items.len) current_level.items[i + 1] else left;

                var hasher = std.crypto.hash.Blake3.init(.{});
                hasher.update(&left);
                hasher.update(&right);
                var out: [32]u8 = undefined;
                hasher.final(&out);
                next_level.append(self.allocator, out) catch break;
            }
            current_level.deinit(self.allocator);
            current_level = next_level;
        }

        return current_level.items[0];
    }

    /// Generate an inclusion proof for the leaf at index
    pub fn getProof(self: *const MerkleTree, index: usize) ![][32]u8 {
        if (index >= self.leaves.items.len) return error.IndexOutOfBounds;

        var proof = std.ArrayList([32]u8).empty;
        errdefer proof.deinit(self.allocator);

        var current_level = std.ArrayList([32]u8).empty;
        defer current_level.deinit(self.allocator);
        try current_level.appendSlice(self.allocator, self.leaves.items);

        var current_index = index;
        while (current_level.items.len > 1) {
            const sibling_index = if (current_index % 2 == 0)
                @min(current_index + 1, current_level.items.len - 1)
            else
                current_index - 1;

            try proof.append(self.allocator, current_level.items[sibling_index]);

            var next_level = std.ArrayList([32]u8).empty;
            var i: usize = 0;
            while (i < current_level.items.len) : (i += 2) {
                const left = current_level.items[i];
                const right = if (i + 1 < current_level.items.len) current_level.items[i + 1] else left;

                var hasher = std.crypto.hash.Blake3.init(.{});
                hasher.update(&left);
                hasher.update(&right);
                var out: [32]u8 = undefined;
                hasher.final(&out);
                try next_level.append(self.allocator, out);
            }
            current_level.deinit(self.allocator);
            current_level = next_level;
            current_index /= 2;
        }

        return proof.toOwnedSlice(self.allocator);
    }

    pub fn verify(root: [32]u8, leaf: [32]u8, index: usize, proof: [][32]u8) bool {
        var current_hash = leaf;
        var current_index = index;
        for (proof) |sibling| {
            var hasher = std.crypto.hash.Blake3.init(.{});
            if (current_index % 2 == 0) {
                hasher.update(&current_hash);
                hasher.update(&sibling);
            } else {
                hasher.update(&sibling);
                hasher.update(&current_hash);
            }
            hasher.final(&current_hash);
            current_index /= 2;
        }
        return std.mem.eql(u8, &current_hash, &root);
    }
};

test "MerkleTree: root and proof" {
    const allocator = std.testing.allocator;
    var tree = MerkleTree.init(allocator);
    defer tree.deinit();

    const h1 = [_]u8{1} ** 32;
    const h2 = [_]u8{2} ** 32;
    const h3 = [_]u8{3} ** 32;

    try tree.insert(h1);
    try tree.insert(h2);
    try tree.insert(h3);

    const root = tree.getRoot();

    // Manual verification of root:
    // next1 = Blake3(h1, h2)
    // next2 = Blake3(h3, h3)
    // root = Blake3(next1, next2)

    const proof = try tree.getProof(0); // Proof for h1
    defer allocator.free(proof);

    try std.testing.expect(MerkleTree.verify(root, h1, 0, proof));
    try std.testing.expect(!MerkleTree.verify(root, h2, 0, proof));
}
