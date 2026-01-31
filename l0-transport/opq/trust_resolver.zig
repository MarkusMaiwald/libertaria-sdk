//! RFC-0120: L0 Trust Resolver Interface
//!
//! Provides the mechanism for L1 to inject trust data into the transport layer
//! for prioritized resource allocation.

const std = @import("std");
const quota = @import("quota.zig");

pub const TrustResolver = struct {
    context: ?*anyopaque,
    resolve_fn: *const fn (ctx: ?*anyopaque, hint: [24]u8) quota.TrustCategory,

    /// Resolve a DID hint to a trust category.
    /// L0 is intentionally dumb; it just calls this function.
    pub fn resolve(self: TrustResolver, hint: [24]u8) quota.TrustCategory {
        return self.resolve_fn(self.context, hint);
    }

    /// Default resolver: everything is a peer.
    pub fn noop() TrustResolver {
        return .{
            .context = null,
            .resolve_fn = struct {
                fn func(_: ?*anyopaque, _: [24]u8) quota.TrustCategory {
                    return .peer;
                }
            }.func,
        };
    }
};
