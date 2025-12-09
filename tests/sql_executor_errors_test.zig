//! Tests for SQL Executor error handling (sql_executor.zig).
//!
//! Covers: Invalid SQL, failed operations, proper error propagation

const std = @import("std");
const guerilla_graph = @import("guerilla_graph");
const sql_executor = guerilla_graph.sql_executor;
const Executor = sql_executor.Executor;
const c_sqlite3 = sql_executor.c_sqlite3;
const sqlite3_open = sql_executor.sqlite3_open;
const sqlite3_close = sql_executor.sqlite3_close;
const SQLITE_OK = sql_executor.SQLITE_OK;

// ============================================================================
// Section 4: Error Handling
// ============================================================================

test "exec: invalid SQL syntax fails" {
    var database: ?*c_sqlite3 = null;
    const open_result = sqlite3_open(":memory:", &database);
    try std.testing.expectEqual(SQLITE_OK, open_result);
    defer _ = sqlite3_close(database);

    var executor = Executor.init(database.?);

    const result = executor.exec("INVALID SQL SYNTAX HERE", .{});
    try std.testing.expectError(error.PrepareStatementFailed, result);
}

test "exec: statement fails during execution" {
    var database: ?*c_sqlite3 = null;
    const open_result = sqlite3_open(":memory:", &database);
    try std.testing.expectEqual(SQLITE_OK, open_result);
    defer _ = sqlite3_close(database);

    var executor = Executor.init(database.?);

    // Create table with NOT NULL constraint
    try executor.exec("CREATE TABLE strict_table (id INTEGER NOT NULL)", .{});

    // Attempt to insert NULL (will fail due to constraint)
    const result = executor.exec("INSERT INTO strict_table VALUES (?)", .{@as(?u32, null)});
    try std.testing.expectError(error.StepFailed, result);
}

test "queryOne: invalid SQL syntax fails" {
    const allocator = std.testing.allocator;
    var database: ?*c_sqlite3 = null;
    const open_result = sqlite3_open(":memory:", &database);
    try std.testing.expectEqual(SQLITE_OK, open_result);
    defer _ = sqlite3_close(database);

    var executor = Executor.init(database.?);

    const result = executor.queryOne(
        struct { id: u32 },
        allocator,
        "SELECT FROM WHERE INVALID",
        .{},
    );
    try std.testing.expectError(error.PrepareStatementFailed, result);
}

test "queryAll: invalid SQL syntax fails" {
    const allocator = std.testing.allocator;
    var database: ?*c_sqlite3 = null;
    const open_result = sqlite3_open(":memory:", &database);
    try std.testing.expectEqual(SQLITE_OK, open_result);
    defer _ = sqlite3_close(database);

    var executor = Executor.init(database.?);

    const TestRow = struct {
        id: u32,
        pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
            _ = self;
            _ = alloc;
        }
    };

    const result = executor.queryAll(
        TestRow,
        allocator,
        "BAD SQL QUERY",
        .{},
    );
    try std.testing.expectError(error.PrepareStatementFailed, result);
}

test "queryOne: query on non-existent table fails" {
    const allocator = std.testing.allocator;
    var database: ?*c_sqlite3 = null;
    const open_result = sqlite3_open(":memory:", &database);
    try std.testing.expectEqual(SQLITE_OK, open_result);
    defer _ = sqlite3_close(database);

    var executor = Executor.init(database.?);

    const result = executor.queryOne(
        struct { id: u32 },
        allocator,
        "SELECT id FROM nonexistent_table",
        .{},
    );
    try std.testing.expectError(error.PrepareStatementFailed, result);
}
