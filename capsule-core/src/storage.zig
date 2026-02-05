//! Persistent Storage Service for Capsule Core
//! Wraps SQLite to store peer discovery data and QVL trust graph.

const std = @import("std");
const c = @cImport({
    @cInclude("sqlite3.h");
});
const l0_transport = @import("l0_transport");
const dht = l0_transport.dht;

pub const RemoteNode = dht.RemoteNode;
pub const ID_LEN = dht.ID_LEN;

pub const StorageError = error{
    DbOpenFailed,
    ExecFailed,
    PrepareFailed,
    StepFailed,
};

pub const StorageService = struct {
    db: ?*c.sqlite3 = null,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, db_path: []const u8) !*StorageService {
        const self = try allocator.create(StorageService);
        self.* = .{
            .allocator = allocator,
            .db = null,
        };

        const db_path_c = try allocator.dupeZ(u8, db_path);
        defer allocator.free(db_path_c);

        if (c.sqlite3_open(db_path_c, &self.db) != c.SQLITE_OK) {
            std.log.err("SQLite: Failed to open database {s}: {s}", .{ db_path, c.sqlite3_errmsg(self.db) });
            return error.DbOpenFailed;
        }

        try self.initSchema();
        std.log.info("SQLite: Database initialized at {s}", .{db_path});

        return self;
    }

    pub fn deinit(self: *StorageService) void {
        if (self.db) |db| {
            _ = c.sqlite3_close(db);
        }
        self.allocator.destroy(self);
    }

    fn initSchema(self: *StorageService) !void {
        const sql =
            \\ PRAGMA journal_mode = WAL;
            \\ CREATE TABLE IF NOT EXISTS peers (
            \\     id BLOB PRIMARY KEY,
            \\     address TEXT NOT NULL,
            \\     last_seen INTEGER NOT NULL,
            \\     seen_count INTEGER DEFAULT 1,
            \\     x25519_key BLOB
            \\ );
            \\ CREATE TABLE IF NOT EXISTS qvl_nodes (
            \\     did BLOB PRIMARY KEY,
            \\     trust_score REAL DEFAULT 0.0
            \\ );
            \\ CREATE TABLE IF NOT EXISTS qvl_edges (
            \\     source BLOB,
            \\     target BLOB,
            \\     weight REAL,
            \\     PRIMARY KEY(source, target)
            \\ );
            \\ CREATE TABLE IF NOT EXISTS banned_peers (
            \\     did TEXT PRIMARY KEY,
            \\     reason TEXT NOT NULL,
            \\     banned_at INTEGER NOT NULL
            \\ );
        ;

        var err_msg: [*c]u8 = null;
        if (c.sqlite3_exec(self.db, sql, null, null, &err_msg) != c.SQLITE_OK) {
            std.log.err("SQLite: Schema init failed: {s}", .{err_msg});
            c.sqlite3_free(err_msg);
            return error.ExecFailed;
        }
    }

    pub fn savePeer(self: *StorageService, node: RemoteNode) !void {
        const sql = "INSERT INTO peers (id, address, last_seen, x25519_key) VALUES (?, ?, ?, ?) " ++
            "ON CONFLICT(id) DO UPDATE SET address=excluded.address, last_seen=excluded.last_seen, seen_count=seen_count+1, x25519_key=excluded.x25519_key;";

        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null) != c.SQLITE_OK) {
            std.log.err("SQLite: Prepare failed for savePeer: {s}", .{c.sqlite3_errmsg(self.db)});
            return error.PrepareFailed;
        }
        defer _ = c.sqlite3_finalize(stmt);

        // Bind ID
        _ = c.sqlite3_bind_blob(stmt, 1, &node.id, @intCast(node.id.len), null);

        // Bind Address
        var addr_buf: [1024]u8 = undefined;
        const addr_str = try std.fmt.bufPrintZ(&addr_buf, "{any}", .{node.address});
        _ = c.sqlite3_bind_text(stmt, 2, addr_str.ptr, -1, null);

        // Bind Last Seen
        _ = c.sqlite3_bind_int64(stmt, 3, node.last_seen);

        // Bind Key
        _ = c.sqlite3_bind_blob(stmt, 4, &node.key, 32, null);

        if (c.sqlite3_step(stmt) != c.SQLITE_DONE) return error.StepFailed;
    }

    pub fn loadPeers(self: *StorageService, allocator: std.mem.Allocator) ![]RemoteNode {
        const sql = "SELECT id, address, last_seen, x25519_key FROM peers;";
        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null) != c.SQLITE_OK) {
            std.log.err("SQLite: Prepare failed for loadPeers: {s}", .{c.sqlite3_errmsg(self.db)});
            return error.PrepareFailed;
        }
        defer _ = c.sqlite3_finalize(stmt);

        var list = std.ArrayList(RemoteNode){};
        defer list.deinit(allocator);

        while (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
            const id_ptr = c.sqlite3_column_blob(stmt, 0);
            const id_len = c.sqlite3_column_bytes(stmt, 0);
            const addr_ptr = c.sqlite3_column_text(stmt, 1);
            const last_seen = c.sqlite3_column_int64(stmt, 2);
            const key_ptr = c.sqlite3_column_blob(stmt, 3);
            const key_len = c.sqlite3_column_bytes(stmt, 3);

            if (id_len != ID_LEN) continue;

            var node: RemoteNode = undefined;
            @memcpy(&node.id, @as([*]const u8, @ptrCast(id_ptr))[0..ID_LEN]);

            const addr_str = std.mem.span(addr_ptr);
            node.address = try std.net.Address.parseIp(addr_str, 0); // Port logic handled via federation later
            node.last_seen = last_seen;
            if (key_len == 32) {
                @memcpy(&node.key, @as([*]const u8, @ptrCast(key_ptr))[0..32]);
            } else {
                @memset(&node.key, 0);
            }

            try list.append(allocator, node);
        }

        const out = try allocator.alloc(RemoteNode, list.items.len);
        @memcpy(out, list.items);
        return out;
    }

    /// Ban a peer by DID
    pub fn banPeer(self: *StorageService, did: []const u8, reason: []const u8) !void {
        const now = std.time.timestamp();
        const sql = "INSERT OR REPLACE INTO banned_peers (did, reason, banned_at) VALUES (?, ?, ?)";

        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null) != c.SQLITE_OK) return error.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt);

        _ = c.sqlite3_bind_text(stmt, 1, did.ptr, @intCast(did.len), null);
        _ = c.sqlite3_bind_text(stmt, 2, reason.ptr, @intCast(reason.len), null);
        _ = c.sqlite3_bind_int64(stmt, 3, now);

        if (c.sqlite3_step(stmt) != c.SQLITE_DONE) return error.StepFailed;
    }

    /// Unban a peer by DID
    pub fn unbanPeer(self: *StorageService, did: []const u8) !void {
        const sql = "DELETE FROM banned_peers WHERE did = ?";

        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null) != c.SQLITE_OK) return error.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt);

        _ = c.sqlite3_bind_text(stmt, 1, did.ptr, @intCast(did.len), null);

        if (c.sqlite3_step(stmt) != c.SQLITE_DONE) return error.StepFailed;
    }

    /// Check if a peer is banned
    pub fn isBanned(self: *StorageService, did: []const u8) !bool {
        const sql = "SELECT COUNT(*) FROM banned_peers WHERE did = ?";

        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null) != c.SQLITE_OK) return error.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt);

        _ = c.sqlite3_bind_text(stmt, 1, did.ptr, @intCast(did.len), null);

        if (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
            const count = c.sqlite3_column_int64(stmt, 0);
            return count > 0;
        }
        return false;
    }
};
