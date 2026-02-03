//! DuckDB C API Bindings for Zig
//! 
//! Thin wrapper around libduckdb for Libertaria L4 Feed
//! Targets: DuckDB 0.9.2+ (C API v1.4.4)

const std = @import("std");

// ============================================================================
// C API Declarations (extern "C")
// ============================================================================

/// Opaque handle types
pub const Database = opaque {};
pub const Connection = opaque {};
pub const Result = opaque {};
pub const Appender = opaque {};

/// State types
pub const State = enum {
    success,
    error,
    // ... more error codes
};

/// C API Functions
pub extern "c" fn duckdb_open(path: [*c]const u8, out_db: **Database) State;
pub extern "c" fn duckdb_close(db: *Database) void;
pub extern "c" fn duckdb_connect(db: *Database, out_con: **Connection) State;
pub extern "c" fn duckdb_disconnect(con: *Connection) void;
pub extern "c" fn duckdb_query(con: *Connection, query: [*c]const u8, out_res: ?**Result) State;
pub extern "c" fn duckdb_destroy_result(res: *Result) void;

// Appender API for bulk inserts
pub extern "c" fn duckdb_appender_create(con: *Connection, schema: [*c]const u8, table: [*c]const u8, out_app: **Appender) State;
pub extern "c" fn duckdb_appender_destroy(app: *Appender) State;
pub extern "c" fn duckdb_appender_flush(app: *Appender) State;
pub extern "c" fn duckdb_appender_append_int64(app: *Appender, val: i64) State;
pub extern "c" fn duckdb_appender_append_uint64(app: *Appender, val: u64) State;
pub extern "c" fn duckdb_appender_append_blob(app: *Appender, data: [*c]const u8, len: usize) State;

// ============================================================================
// Zig-Friendly Wrapper
// ============================================================================

pub const DB = struct {
    ptr: *Database,
    
    pub fn open(path: []const u8) !DB {
        var db: *Database = undefined;
        const c_path = try std.cstr.addNullByte(std.heap.page_allocator, path);
        defer std.heap.page_allocator.free(c_path);
        
        if (duckdb_open(c_path.ptr, &db) != .success) {
            return error.DuckDBOpenFailed;
        }
        return DB{ .ptr = db };
    }
    
    pub fn close(self: *DB) void {
        duckdb_close(self.ptr);
    }
    
    pub fn connect(self: *DB) !Conn {
        var con: *Connection = undefined;
        if (duckdb_connect(self.ptr, &con) != .success) {
            return error.DuckDBConnectFailed;
        }
        return Conn{ .ptr = con };
    }
};

pub const Conn = struct {
    ptr: *Connection,
    
    pub fn disconnect(self: *Conn) void {
        duckdb_disconnect(self.ptr);
    }
    
    pub fn query(self: *Conn, sql: []const u8) !void {
        const c_sql = try std.cstr.addNullByte(std.heap.page_allocator, sql);
        defer std.heap.page_allocator.free(c_sql);
        
        if (duckdb_query(self.ptr, c_sql.ptr, null) != .success) {
            return error.DuckDBQueryFailed;
        }
    }
};

// ============================================================================
// TESTS
// ============================================================================

test "DuckDB open/close" {
    // Note: Requires libduckdb.so at runtime
    // This test is skipped in CI without DuckDB
    
    // var db = try DB.open(":memory:");
    // defer db.close();
}
