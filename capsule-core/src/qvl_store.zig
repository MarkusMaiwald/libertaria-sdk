//! Quasar Vector Lattice (QVL) Storage Service
//! Wraps DuckDB to store and analyze the trust graph.

const std = @import("std");
const c = @cImport({
    @cInclude("duckdb.h");
});

pub const QvlError = error{
    DbOpenFailed,
    ConnectionFailed,
    QueryFailed,
    ExecFailed,
    ExtensionLoadFailed,
};

const slash_mod = @import("l1_identity").slash;
const SlashReason = slash_mod.SlashReason;
const SlashSeverity = slash_mod.SlashSeverity;

const qvl_types = @import("qvl").types;
pub const NodeId = qvl_types.NodeId;
pub const RiskEdge = qvl_types.RiskEdge;

pub const QvlStore = struct {
    db: c.duckdb_database = null,
    conn: c.duckdb_connection = null,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, db_path: []const u8) !*QvlStore {
        const self = try allocator.create(QvlStore);
        self.* = .{
            .allocator = allocator,
            .db = null,
            .conn = null,
        };

        const db_path_c = try allocator.dupeZ(u8, db_path);
        defer allocator.free(db_path_c);

        var err_msg: [*c]u8 = null;
        if (c.duckdb_open_ext(db_path_c, &self.db, null, &err_msg) != c.DuckDBSuccess) {
            std.log.err("DuckDB: Failed to open database {s}: {s}", .{ db_path, err_msg });
            return error.DbOpenFailed;
        }

        if (c.duckdb_connect(self.db, &self.conn) != c.DuckDBSuccess) {
            return error.ConnectionFailed;
        }

        try self.initExtensions();
        try self.initSchema();

        std.log.info("DuckDB: QVL Store initialized at {s}", .{db_path});

        return self;
    }

    pub fn deinit(self: *QvlStore) void {
        if (self.conn != null) c.duckdb_disconnect(&self.conn);
        if (self.db != null) c.duckdb_close(&self.db);
        self.allocator.destroy(self);
    }

    fn initExtensions(self: *QvlStore) !void {
        const sql = "INSTALL prql; LOAD prql;";
        var res: c.duckdb_result = undefined;
        if (c.duckdb_query(self.conn, sql, &res) != c.DuckDBSuccess) {
            std.log.warn("DuckDB: PRQL extension not available. Falling back to SQL for analytics. Error: {s}", .{c.duckdb_result_error(&res)});
            c.duckdb_destroy_result(&res);
            return;
        }
        c.duckdb_destroy_result(&res);
        std.log.info("DuckDB: PRQL extension loaded.", .{});
    }

    fn initSchema(self: *QvlStore) !void {
        const sql =
            \\ CREATE TABLE IF NOT EXISTS qvl_vertices (
            \\     id INTEGER PRIMARY KEY,
            \\     did TEXT,
            \\     trust_score REAL DEFAULT 0.0,
            \\     last_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            \\ );
            \\ CREATE TABLE IF NOT EXISTS qvl_edges (
            \\     source INTEGER,
            \\     target INTEGER,
            \\     weight REAL,
            \\     nonce UBIGINT,
            \\     PRIMARY KEY(source, target)
            \\ );
            \\ CREATE TABLE IF NOT EXISTS slash_events (
            \\     timestamp UBIGINT,
            \\     target_did TEXT,
            \\     reason TEXT,
            \\     severity TEXT,
            \\     evidence_hash TEXT
            \\ );
        ;

        var res: c.duckdb_result = undefined;
        if (c.duckdb_query(self.conn, sql, &res) != c.DuckDBSuccess) {
            std.log.err("DuckDB: Schema init failed: {s}", .{c.duckdb_result_error(&res)});
            c.duckdb_destroy_result(&res);
            return error.ExecFailed;
        }
        c.duckdb_destroy_result(&res);
    }

    pub fn syncLattice(self: *QvlStore, nodes: []const NodeId, edges: []const RiskEdge) !void {
        // Clear old state (analytical snapshot)
        _ = try self.execSql("DELETE FROM qvl_vertices;");
        _ = try self.execSql("DELETE FROM qvl_edges;");

        // Batch insert vertices
        var appender: c.duckdb_appender = null;
        if (c.duckdb_appender_create(self.conn, null, "qvl_vertices", &appender) != c.DuckDBSuccess) return error.ExecFailed;
        defer _ = c.duckdb_appender_destroy(&appender);

        for (nodes) |node| {
            _ = c.duckdb_append_int32(appender, @intCast(node));
            _ = c.duckdb_append_null(appender); // DID unknown here
            _ = c.duckdb_append_double(appender, 0.0);
            _ = c.duckdb_appender_end_row(appender);
        }

        // Batch insert edges
        var edge_appender: c.duckdb_appender = null;
        if (c.duckdb_appender_create(self.conn, null, "qvl_edges", &edge_appender) != c.DuckDBSuccess) return error.ExecFailed;
        defer _ = c.duckdb_appender_destroy(&edge_appender);

        for (edges) |edge| {
            _ = c.duckdb_append_int32(edge_appender, @intCast(edge.from));
            _ = c.duckdb_append_int32(edge_appender, @intCast(edge.to));
            _ = c.duckdb_append_double(edge_appender, edge.risk);
            _ = c.duckdb_append_uint64(edge_appender, edge.nonce);
            _ = c.duckdb_appender_end_row(edge_appender);
        }
    }

    pub fn computeTrustRank(self: *QvlStore) !void {
        // Fallback to SQL for trust aggregation
        const sql =
            \\ SELECT target, AVG(weight) as avg_risk 
            \\ FROM qvl_edges 
            \\ GROUP BY target 
            \\ HAVING AVG(weight) > 0.5;
        ;
        var res: c.duckdb_result = undefined;
        if (c.duckdb_query(self.conn, sql, &res) != c.DuckDBSuccess) {
            std.log.err("DuckDB Analytics Error: {s}", .{c.duckdb_result_error(&res)});
            c.duckdb_destroy_result(&res);
            return error.QueryFailed;
        }
        c.duckdb_destroy_result(&res);
    }

    fn execSql(self: *QvlStore, sql: []const u8) !void {
        var res: c.duckdb_result = undefined;
        const sql_z = try self.allocator.dupeZ(u8, sql);
        defer self.allocator.free(sql_z);
        if (c.duckdb_query(self.conn, sql_z.ptr, &res) != c.DuckDBSuccess) {
            std.log.err("DuckDB SQL Error: {s}", .{c.duckdb_result_error(&res)});
            c.duckdb_destroy_result(&res);
            return error.ExecFailed;
        }
        c.duckdb_destroy_result(&res);
    }

    pub fn execPrql(self: *QvlStore, prql_query: []const u8) !void {
        const prql_buf = try std.fmt.allocPrintZ(self.allocator, "PRQL '{s}'", .{prql_query});
        defer self.allocator.free(prql_buf);

        var res: c.duckdb_result = undefined;
        if (c.duckdb_query(self.conn, prql_buf.ptr, &res) != c.DuckDBSuccess) {
            std.log.err("DuckDB PRQL Error: {s}", .{c.duckdb_result_error(&res)});
            c.duckdb_destroy_result(&res);
            return error.QueryFailed;
        }
        c.duckdb_destroy_result(&res);
    }
};
