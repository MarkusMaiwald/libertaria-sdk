const std = @import("std");

pub const Database = opaque {};
pub const Connection = opaque {};
pub const Result = opaque {};
pub const Appender = opaque {};

pub const State = enum {
    ok,
    err,
};

pub extern "c" fn duckdb_open(path: [*c]const u8, out_db: **Database) State;
pub extern "c" fn duckdb_close(db: *Database) void;
pub extern "c" fn duckdb_connect(db: *Database, out_con: **Connection) State;
pub extern "c" fn duckdb_disconnect(con: *Connection) void;
pub extern "c" fn duckdb_query(con: *Connection, query: [*c]const u8, out_res: ?**Result) State;
pub extern "c" fn duckdb_destroy_result(res: *Result) void;

pub const DB = struct {
    ptr: *Database,
    
    pub fn open(path: []const u8) !DB {
        var db: *Database = undefined;
        const c_path = try std.cstr.addNullByte(std.heap.page_allocator, path);
        defer std.heap.page_allocator.free(c_path);
        
        if (duckdb_open(c_path.ptr, &db) != .ok) {
            return error.DuckDBOpenFailed;
        }
        return DB{ .ptr = db };
    }
    
    pub fn close(self: *DB) void {
        duckdb_close(self.ptr);
    }
    
    pub fn connect(self: *DB) !Conn {
        var con: *Connection = undefined;
        if (duckdb_connect(self.ptr, &con) != .ok) {
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
        
        if (duckdb_query(self.ptr, c_sql.ptr, null) != .ok) {
            return error.DuckDBQueryFailed;
        }
    }
};
