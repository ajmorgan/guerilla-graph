//! Tests for SQL Executor basic operations (sql_executor.zig).
//!
//! Covers: Executor.init, exec method with various SQL operations

const std = @import("std");
const guerilla_graph = @import("guerilla_graph");
const sql_executor = guerilla_graph.sql_executor;
const Executor = sql_executor.Executor;
const c_sqlite3 = sql_executor.c_sqlite3;
const sqlite3_open = sql_executor.sqlite3_open;
const sqlite3_close = sql_executor.sqlite3_close;
const SQLITE_OK = sql_executor.SQLITE_OK;

// ============================================================================
// Section 1: Basic Operations (init, exec)
// ============================================================================

test "Executor.init: successful initialization" {
    var database: ?*c_sqlite3 = null;
    const open_result = sqlite3_open(":memory:", &database);
    try std.testing.expectEqual(SQLITE_OK, open_result);
    defer _ = sqlite3_close(database);

    const executor = Executor.init(database.?);

    // Verify executor holds valid database pointer
    try std.testing.expect(@intFromPtr(executor.database) != 0);
    try std.testing.expectEqual(database.?, executor.database);
}

test "exec: CREATE TABLE with no parameters" {
    var database: ?*c_sqlite3 = null;
    const open_result = sqlite3_open(":memory:", &database);
    try std.testing.expectEqual(SQLITE_OK, open_result);
    defer _ = sqlite3_close(database);

    var executor = Executor.init(database.?);

    // Execute CREATE TABLE statement
    try executor.exec(
        "CREATE TABLE test_table (id INTEGER PRIMARY KEY, name TEXT)",
        .{},
    );

    // Verify table was created (query sqlite_master)
    const check_result = try executor.queryOne(
        struct { name: []const u8 },
        std.testing.allocator,
        "SELECT name FROM sqlite_master WHERE type='table' AND name='test_table'",
        .{},
    );
    try std.testing.expect(check_result != null);
    if (check_result) |*result| {
        defer std.testing.allocator.free(result.name);
        try std.testing.expectEqualStrings("test_table", result.name);
    }
}

test "exec: INSERT with parameters" {
    const allocator = std.testing.allocator;
    var database: ?*c_sqlite3 = null;
    const open_result = sqlite3_open(":memory:", &database);
    try std.testing.expectEqual(SQLITE_OK, open_result);
    defer _ = sqlite3_close(database);

    var executor = Executor.init(database.?);

    // Setup table
    try executor.exec("CREATE TABLE users (id INTEGER, name TEXT, age INTEGER)", .{});

    // Insert rows with parameters
    try executor.exec("INSERT INTO users VALUES (?, ?, ?)", .{ @as(u32, 1), "Alice", @as(i64, 30) });
    try executor.exec("INSERT INTO users VALUES (?, ?, ?)", .{ @as(u32, 2), "Bob", @as(i64, 25) });

    // Verify rows were inserted
    const count_result = try executor.queryOne(
        struct { count: i64 },
        allocator,
        "SELECT COUNT(*) as count FROM users",
        .{},
    );
    try std.testing.expect(count_result != null);
    try std.testing.expectEqual(@as(i64, 2), count_result.?.count);
}

test "exec: UPDATE with parameters" {
    const allocator = std.testing.allocator;
    var database: ?*c_sqlite3 = null;
    const open_result = sqlite3_open(":memory:", &database);
    try std.testing.expectEqual(SQLITE_OK, open_result);
    defer _ = sqlite3_close(database);

    var executor = Executor.init(database.?);

    // Setup and populate table
    try executor.exec("CREATE TABLE products (id INTEGER, price INTEGER)", .{});
    try executor.exec("INSERT INTO products VALUES (?, ?)", .{ @as(u32, 1), @as(i64, 100) });

    // Update row
    try executor.exec("UPDATE products SET price = ? WHERE id = ?", .{ @as(i64, 150), @as(u32, 1) });

    // Verify update
    var result = try executor.queryOne(
        struct { price: i64 },
        allocator,
        "SELECT price FROM products WHERE id = 1",
        .{},
    );
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(i64, 150), result.?.price);
}

test "exec: DELETE with parameters" {
    const allocator = std.testing.allocator;
    var database: ?*c_sqlite3 = null;
    const open_result = sqlite3_open(":memory:", &database);
    try std.testing.expectEqual(SQLITE_OK, open_result);
    defer _ = sqlite3_close(database);

    var executor = Executor.init(database.?);

    // Setup and populate table
    try executor.exec("CREATE TABLE items (id INTEGER)", .{});
    try executor.exec("INSERT INTO items VALUES (?)", .{@as(u32, 1)});
    try executor.exec("INSERT INTO items VALUES (?)", .{@as(u32, 2)});

    // Delete one row
    try executor.exec("DELETE FROM items WHERE id = ?", .{@as(u32, 1)});

    // Verify deletion
    const count_result = try executor.queryOne(
        struct { count: i64 },
        allocator,
        "SELECT COUNT(*) as count FROM items",
        .{},
    );
    try std.testing.expect(count_result != null);
    try std.testing.expectEqual(@as(i64, 1), count_result.?.count);
}

// ============================================================================
// Tests migrated from inline tests in sql_executor.zig
// ============================================================================

// NOTE: Section 6 test originally used 'c.' prefix pattern with c_sqlite3 import.
// This version uses re-exported constants from sql_executor for consistency.
test "exec method with parameterless statement" {
    // Open in-memory database
    var database: ?*c_sqlite3 = null;
    const open_result = sqlite3_open(":memory:", &database);
    try std.testing.expectEqual(SQLITE_OK, open_result);
    defer _ = sqlite3_close(database);

    var executor = Executor.init(database.?);

    // Test exec with CREATE TABLE (no parameters)
    try executor.exec("CREATE TABLE test (id INTEGER, name TEXT)", .{});

    // Test exec with INSERT (with parameters)
    try executor.exec("INSERT INTO test VALUES (?, ?)", .{ @as(u32, 1), "Alice" });
    try executor.exec("INSERT INTO test VALUES (?, ?)", .{ @as(u32, 2), "Bob" });
}
