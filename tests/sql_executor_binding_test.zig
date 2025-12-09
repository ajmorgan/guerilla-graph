//! Tests for SQL Executor parameter binding (sql_executor.zig).
//!
//! Covers: bindParams method with u32, i64, []const u8, optional types, mixed tuples

const std = @import("std");
const guerilla_graph = @import("guerilla_graph");
const sql_executor = guerilla_graph.sql_executor;
const Executor = sql_executor.Executor;
const c_imports = guerilla_graph.c_imports;
const c_sqlite3 = sql_executor.c_sqlite3;
const sqlite3_open = sql_executor.sqlite3_open;
const sqlite3_close = sql_executor.sqlite3_close;
const SQLITE_OK = sql_executor.SQLITE_OK;

// Alias for Section 6 migrated tests
const c = c_imports.c;

// ============================================================================
// Section 2: Parameter Binding (All Types)
// ============================================================================

test "bindParams: u32 parameter" {
    const allocator = std.testing.allocator;
    var database: ?*c_sqlite3 = null;
    const open_result = sqlite3_open(":memory:", &database);
    try std.testing.expectEqual(SQLITE_OK, open_result);
    defer _ = sqlite3_close(database);

    var executor = Executor.init(database.?);

    try executor.exec("CREATE TABLE test_u32 (id INTEGER, value INTEGER)", .{});
    try executor.exec("INSERT INTO test_u32 VALUES (?, ?)", .{ @as(u32, 1), @as(u32, 42) });

    var result = try executor.queryOne(
        struct { value: u32 },
        allocator,
        "SELECT value FROM test_u32 WHERE id = 1",
        .{},
    );
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(u32, 42), result.?.value);
}

test "bindParams: i64 parameter" {
    const allocator = std.testing.allocator;
    var database: ?*c_sqlite3 = null;
    const open_result = sqlite3_open(":memory:", &database);
    try std.testing.expectEqual(SQLITE_OK, open_result);
    defer _ = sqlite3_close(database);

    var executor = Executor.init(database.?);

    try executor.exec("CREATE TABLE test_i64 (id INTEGER, value INTEGER)", .{});
    try executor.exec("INSERT INTO test_i64 VALUES (?, ?)", .{ @as(u32, 1), @as(i64, 9223372036854775807) });

    var result = try executor.queryOne(
        struct { value: i64 },
        allocator,
        "SELECT value FROM test_i64 WHERE id = 1",
        .{},
    );
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(i64, 9223372036854775807), result.?.value);
}

test "bindParams: []const u8 slice parameter" {
    const allocator = std.testing.allocator;
    var database: ?*c_sqlite3 = null;
    const open_result = sqlite3_open(":memory:", &database);
    try std.testing.expectEqual(SQLITE_OK, open_result);
    defer _ = sqlite3_close(database);

    var executor = Executor.init(database.?);

    try executor.exec("CREATE TABLE test_slice (id INTEGER, text TEXT)", .{});

    const text_value: []const u8 = "Hello, World!";
    try executor.exec("INSERT INTO test_slice VALUES (?, ?)", .{ @as(u32, 1), text_value });

    var result = try executor.queryOne(
        struct { text: []const u8 },
        allocator,
        "SELECT text FROM test_slice WHERE id = 1",
        .{},
    );
    try std.testing.expect(result != null);
    if (result) |*row| {
        defer allocator.free(row.text);
        try std.testing.expectEqualStrings("Hello, World!", row.text);
    }
}

test "bindParams: string literal parameter" {
    const allocator = std.testing.allocator;
    var database: ?*c_sqlite3 = null;
    const open_result = sqlite3_open(":memory:", &database);
    try std.testing.expectEqual(SQLITE_OK, open_result);
    defer _ = sqlite3_close(database);

    var executor = Executor.init(database.?);

    try executor.exec("CREATE TABLE test_literal (id INTEGER, text TEXT)", .{});
    try executor.exec("INSERT INTO test_literal VALUES (?, ?)", .{ @as(u32, 1), "String literal" });

    var result = try executor.queryOne(
        struct { text: []const u8 },
        allocator,
        "SELECT text FROM test_literal WHERE id = 1",
        .{},
    );
    try std.testing.expect(result != null);
    if (result) |*row| {
        defer allocator.free(row.text);
        try std.testing.expectEqualStrings("String literal", row.text);
    }
}

test "bindParams: optional u32 with value" {
    const allocator = std.testing.allocator;
    var database: ?*c_sqlite3 = null;
    const open_result = sqlite3_open(":memory:", &database);
    try std.testing.expectEqual(SQLITE_OK, open_result);
    defer _ = sqlite3_close(database);

    var executor = Executor.init(database.?);

    try executor.exec("CREATE TABLE test_opt_u32 (id INTEGER, value INTEGER)", .{});

    const optional_value: ?u32 = 123;
    try executor.exec("INSERT INTO test_opt_u32 VALUES (?, ?)", .{ @as(u32, 1), optional_value });

    var result = try executor.queryOne(
        struct { value: ?u32 },
        allocator,
        "SELECT value FROM test_opt_u32 WHERE id = 1",
        .{},
    );
    try std.testing.expect(result != null);
    try std.testing.expect(result.?.value != null);
    try std.testing.expectEqual(@as(u32, 123), result.?.value.?);
}

test "bindParams: optional u32 with null" {
    const allocator = std.testing.allocator;
    var database: ?*c_sqlite3 = null;
    const open_result = sqlite3_open(":memory:", &database);
    try std.testing.expectEqual(SQLITE_OK, open_result);
    defer _ = sqlite3_close(database);

    var executor = Executor.init(database.?);

    try executor.exec("CREATE TABLE test_opt_null (id INTEGER, value INTEGER)", .{});

    const null_value: ?u32 = null;
    try executor.exec("INSERT INTO test_opt_null VALUES (?, ?)", .{ @as(u32, 1), null_value });

    var result = try executor.queryOne(
        struct { value: ?u32 },
        allocator,
        "SELECT value FROM test_opt_null WHERE id = 1",
        .{},
    );
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(?u32, null), result.?.value);
}

test "bindParams: optional i64 with value" {
    const allocator = std.testing.allocator;
    var database: ?*c_sqlite3 = null;
    const open_result = sqlite3_open(":memory:", &database);
    try std.testing.expectEqual(SQLITE_OK, open_result);
    defer _ = sqlite3_close(database);

    var executor = Executor.init(database.?);

    try executor.exec("CREATE TABLE test_opt_i64 (id INTEGER, value INTEGER)", .{});

    const optional_value: ?i64 = 456789;
    try executor.exec("INSERT INTO test_opt_i64 VALUES (?, ?)", .{ @as(u32, 1), optional_value });

    var result = try executor.queryOne(
        struct { value: ?i64 },
        allocator,
        "SELECT value FROM test_opt_i64 WHERE id = 1",
        .{},
    );
    try std.testing.expect(result != null);
    try std.testing.expect(result.?.value != null);
    try std.testing.expectEqual(@as(i64, 456789), result.?.value.?);
}

test "bindParams: optional i64 with null" {
    const allocator = std.testing.allocator;
    var database: ?*c_sqlite3 = null;
    const open_result = sqlite3_open(":memory:", &database);
    try std.testing.expectEqual(SQLITE_OK, open_result);
    defer _ = sqlite3_close(database);

    var executor = Executor.init(database.?);

    try executor.exec("CREATE TABLE test_opt_i64_null (id INTEGER, timestamp INTEGER)", .{});

    const null_timestamp: ?i64 = null;
    try executor.exec("INSERT INTO test_opt_i64_null VALUES (?, ?)", .{ @as(u32, 1), null_timestamp });

    var result = try executor.queryOne(
        struct { timestamp: ?i64 },
        allocator,
        "SELECT timestamp FROM test_opt_i64_null WHERE id = 1",
        .{},
    );
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(?i64, null), result.?.timestamp);
}

test "bindParams: optional []const u8 with value" {
    const allocator = std.testing.allocator;
    var database: ?*c_sqlite3 = null;
    const open_result = sqlite3_open(":memory:", &database);
    try std.testing.expectEqual(SQLITE_OK, open_result);
    defer _ = sqlite3_close(database);

    var executor = Executor.init(database.?);

    try executor.exec("CREATE TABLE test_opt_text (id INTEGER, description TEXT)", .{});

    const optional_text: ?[]const u8 = "Optional description";
    try executor.exec("INSERT INTO test_opt_text VALUES (?, ?)", .{ @as(u32, 1), optional_text });

    var result = try executor.queryOne(
        struct { description: ?[]const u8 },
        allocator,
        "SELECT description FROM test_opt_text WHERE id = 1",
        .{},
    );
    try std.testing.expect(result != null);
    if (result) |*row| {
        defer if (row.description) |desc| allocator.free(desc);
        try std.testing.expect(row.description != null);
        try std.testing.expectEqualStrings("Optional description", row.description.?);
    }
}

test "bindParams: optional []const u8 with null" {
    const allocator = std.testing.allocator;
    var database: ?*c_sqlite3 = null;
    const open_result = sqlite3_open(":memory:", &database);
    try std.testing.expectEqual(SQLITE_OK, open_result);
    defer _ = sqlite3_close(database);

    var executor = Executor.init(database.?);

    try executor.exec("CREATE TABLE test_opt_text_null (id INTEGER, note TEXT)", .{});

    const null_text: ?[]const u8 = null;
    try executor.exec("INSERT INTO test_opt_text_null VALUES (?, ?)", .{ @as(u32, 1), null_text });

    var result = try executor.queryOne(
        struct { note: ?[]const u8 },
        allocator,
        "SELECT note FROM test_opt_text_null WHERE id = 1",
        .{},
    );
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(?[]const u8, null), result.?.note);
}

test "bindParams: mixed types in single query" {
    const allocator = std.testing.allocator;
    var database: ?*c_sqlite3 = null;
    const open_result = sqlite3_open(":memory:", &database);
    try std.testing.expectEqual(SQLITE_OK, open_result);
    defer _ = sqlite3_close(database);

    var executor = Executor.init(database.?);

    try executor.exec(
        "CREATE TABLE test_mixed (id INTEGER, name TEXT, age INTEGER, salary INTEGER, nickname TEXT)",
        .{},
    );

    const optional_nickname: ?[]const u8 = "Big Boss";
    try executor.exec(
        "INSERT INTO test_mixed VALUES (?, ?, ?, ?, ?)",
        .{ @as(u32, 42), "John Doe", @as(i64, 35), @as(i64, 75000), optional_nickname },
    );

    var result = try executor.queryOne(
        struct {
            id: u32,
            name: []const u8,
            age: i64,
            salary: i64,
            nickname: ?[]const u8,
        },
        allocator,
        "SELECT id, name, age, salary, nickname FROM test_mixed WHERE id = 42",
        .{},
    );

    try std.testing.expect(result != null);
    if (result) |*row| {
        defer allocator.free(row.name);
        defer if (row.nickname) |nn| allocator.free(nn);

        try std.testing.expectEqual(@as(u32, 42), row.id);
        try std.testing.expectEqualStrings("John Doe", row.name);
        try std.testing.expectEqual(@as(i64, 35), row.age);
        try std.testing.expectEqual(@as(i64, 75000), row.salary);
        try std.testing.expect(row.nickname != null);
        try std.testing.expectEqualStrings("Big Boss", row.nickname.?);
    }
}

test "bindParams: empty parameter tuple" {
    var database: ?*c_sqlite3 = null;
    const open_result = sqlite3_open(":memory:", &database);
    try std.testing.expectEqual(SQLITE_OK, open_result);
    defer _ = sqlite3_close(database);

    var executor = Executor.init(database.?);

    // Should succeed with no parameters
    try executor.exec("CREATE TABLE test_empty (id INTEGER PRIMARY KEY AUTOINCREMENT)", .{});
    try executor.exec("INSERT INTO test_empty DEFAULT VALUES", .{});

    // Verify insertion
    const allocator = std.testing.allocator;
    const count_result = try executor.queryOne(
        struct { count: i64 },
        allocator,
        "SELECT COUNT(*) as count FROM test_empty",
        .{},
    );
    try std.testing.expect(count_result != null);
    try std.testing.expectEqual(@as(i64, 1), count_result.?.count);
}

// ============================================================================
// Tests migrated from inline tests in sql_executor.zig
// ============================================================================

test "bindParams with multiple types" {
    // Open in-memory database
    var database: ?*c.sqlite3 = null;
    const open_result = c.sqlite3_open(":memory:", &database);
    try std.testing.expectEqual(c.SQLITE_OK, open_result);
    defer _ = c.sqlite3_close(database);

    var executor = Executor.init(database.?);

    // Create test table
    try executor.exec("CREATE TABLE test (id INTEGER, name TEXT, value INTEGER, optional_text TEXT)", .{});

    // Test binding multiple parameter types using exec (which uses bindParams internally)
    const test_name = "test_item";
    const optional_text: ?[]const u8 = null;
    try executor.exec("INSERT INTO test VALUES (?, ?, ?, ?)", .{ @as(u32, 42), test_name, @as(i64, 123456), optional_text });
}
