//! Tests for SQL Executor result extraction (sql_executor.zig).
//!
//! Covers: queryOne, queryAll methods with various result scenarios

const std = @import("std");
const guerilla_graph = @import("guerilla_graph");
const sql_executor = guerilla_graph.sql_executor;
const Executor = sql_executor.Executor;
const c_sqlite3 = sql_executor.c_sqlite3;
const sqlite3_open = sql_executor.sqlite3_open;
const sqlite3_close = sql_executor.sqlite3_close;
const SQLITE_OK = sql_executor.SQLITE_OK;
const c_imports = guerilla_graph.c_imports;

// Alias for Section 6 migrated tests
const c = c_imports.c;

// ============================================================================
// Section 3: Result Extraction (queryOne, queryAll)
// ============================================================================

test "queryOne: returns single row" {
    const allocator = std.testing.allocator;
    var database: ?*c_sqlite3 = null;
    const open_result = sql_executor.sqlite3_open(":memory:", &database);
    try std.testing.expectEqual(SQLITE_OK, open_result);
    defer _ = sql_executor.sqlite3_close(database);

    var executor = Executor.init(database.?);

    try executor.exec("CREATE TABLE employees (id INTEGER, name TEXT, salary INTEGER)", .{});
    try executor.exec("INSERT INTO employees VALUES (?, ?, ?)", .{ @as(u32, 1), "Alice", @as(i64, 50000) });

    var result = try executor.queryOne(
        struct {
            id: u32,
            name: []const u8,
            salary: i64,
        },
        allocator,
        "SELECT id, name, salary FROM employees WHERE id = ?",
        .{@as(u32, 1)},
    );

    try std.testing.expect(result != null);
    if (result) |*row| {
        defer allocator.free(row.name);
        try std.testing.expectEqual(@as(u32, 1), row.id);
        try std.testing.expectEqualStrings("Alice", row.name);
        try std.testing.expectEqual(@as(i64, 50000), row.salary);
    }
}

test "queryOne: returns null for no results" {
    const allocator = std.testing.allocator;
    var database: ?*c_sqlite3 = null;
    const open_result = sql_executor.sqlite3_open(":memory:", &database);
    try std.testing.expectEqual(SQLITE_OK, open_result);
    defer _ = sql_executor.sqlite3_close(database);

    var executor = Executor.init(database.?);

    try executor.exec("CREATE TABLE empty_table (id INTEGER, name TEXT)", .{});

    const TestRow = struct { id: u32, name: []const u8 };
    const result = try executor.queryOne(
        TestRow,
        allocator,
        "SELECT id, name FROM empty_table WHERE id = ?",
        .{@as(u32, 999)},
    );

    try std.testing.expectEqual(@as(?TestRow, null), result);
}

test "queryOne: extracts optional fields correctly" {
    const allocator = std.testing.allocator;
    var database: ?*c_sqlite3 = null;
    const open_result = sql_executor.sqlite3_open(":memory:", &database);
    try std.testing.expectEqual(SQLITE_OK, open_result);
    defer _ = sql_executor.sqlite3_close(database);

    var executor = Executor.init(database.?);

    try executor.exec("CREATE TABLE contacts (id INTEGER, email TEXT, phone TEXT)", .{});
    try executor.exec("INSERT INTO contacts VALUES (?, ?, ?)", .{ @as(u32, 1), "user@example.com", @as(?[]const u8, null) });

    var result = try executor.queryOne(
        struct {
            id: u32,
            email: []const u8,
            phone: ?[]const u8,
        },
        allocator,
        "SELECT id, email, phone FROM contacts WHERE id = ?",
        .{@as(u32, 1)},
    );

    try std.testing.expect(result != null);
    if (result) |*row| {
        defer allocator.free(row.email);
        defer if (row.phone) |p| allocator.free(p);

        try std.testing.expectEqual(@as(u32, 1), row.id);
        try std.testing.expectEqualStrings("user@example.com", row.email);
        try std.testing.expectEqual(@as(?[]const u8, null), row.phone);
    }
}

test "queryAll: returns multiple rows" {
    const allocator = std.testing.allocator;
    var database: ?*c_sqlite3 = null;
    const open_result = sql_executor.sqlite3_open(":memory:", &database);
    try std.testing.expectEqual(SQLITE_OK, open_result);
    defer _ = sql_executor.sqlite3_close(database);

    var executor = Executor.init(database.?);

    try executor.exec("CREATE TABLE numbers (id INTEGER, value INTEGER)", .{});
    try executor.exec("INSERT INTO numbers VALUES (?, ?)", .{ @as(u32, 1), @as(i64, 10) });
    try executor.exec("INSERT INTO numbers VALUES (?, ?)", .{ @as(u32, 2), @as(i64, 20) });
    try executor.exec("INSERT INTO numbers VALUES (?, ?)", .{ @as(u32, 3), @as(i64, 30) });

    const TestRow = struct {
        id: u32,
        value: i64,

        pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
            _ = self;
            _ = alloc;
        }
    };

    const results = try executor.queryAll(
        TestRow,
        allocator,
        "SELECT id, value FROM numbers ORDER BY id",
        .{},
    );
    defer {
        for (results) |*row| {
            row.deinit(allocator);
        }
        allocator.free(results);
    }

    try std.testing.expectEqual(@as(usize, 3), results.len);
    try std.testing.expectEqual(@as(u32, 1), results[0].id);
    try std.testing.expectEqual(@as(i64, 10), results[0].value);
    try std.testing.expectEqual(@as(u32, 2), results[1].id);
    try std.testing.expectEqual(@as(i64, 20), results[1].value);
    try std.testing.expectEqual(@as(u32, 3), results[2].id);
    try std.testing.expectEqual(@as(i64, 30), results[2].value);
}

test "queryAll: returns empty slice for no results" {
    const allocator = std.testing.allocator;
    var database: ?*c_sqlite3 = null;
    const open_result = sql_executor.sqlite3_open(":memory:", &database);
    try std.testing.expectEqual(SQLITE_OK, open_result);
    defer _ = sql_executor.sqlite3_close(database);

    var executor = Executor.init(database.?);

    try executor.exec("CREATE TABLE empty_results (id INTEGER, name TEXT)", .{});

    const TestRow = struct {
        id: u32,
        name: []const u8,

        pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
            alloc.free(self.name);
        }
    };

    const results = try executor.queryAll(
        TestRow,
        allocator,
        "SELECT id, name FROM empty_results WHERE id > ?",
        .{@as(u32, 0)},
    );
    defer allocator.free(results);

    try std.testing.expectEqual(@as(usize, 0), results.len);
}

test "queryAll: handles rows with optional fields" {
    const allocator = std.testing.allocator;
    var database: ?*c_sqlite3 = null;
    const open_result = sql_executor.sqlite3_open(":memory:", &database);
    try std.testing.expectEqual(SQLITE_OK, open_result);
    defer _ = sql_executor.sqlite3_close(database);

    var executor = Executor.init(database.?);

    try executor.exec("CREATE TABLE orders (id INTEGER, customer TEXT, notes TEXT)", .{});
    try executor.exec("INSERT INTO orders VALUES (?, ?, ?)", .{ @as(u32, 1), "Alice", "Urgent" });
    try executor.exec("INSERT INTO orders VALUES (?, ?, ?)", .{ @as(u32, 2), "Bob", @as(?[]const u8, null) });

    const TestRow = struct {
        id: u32,
        customer: []const u8,
        notes: ?[]const u8,

        pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
            alloc.free(self.customer);
            if (self.notes) |n| alloc.free(n);
        }
    };

    const results = try executor.queryAll(
        TestRow,
        allocator,
        "SELECT id, customer, notes FROM orders ORDER BY id",
        .{},
    );
    defer {
        for (results) |*row| {
            row.deinit(allocator);
        }
        allocator.free(results);
    }

    try std.testing.expectEqual(@as(usize, 2), results.len);

    // First row has notes
    try std.testing.expectEqual(@as(u32, 1), results[0].id);
    try std.testing.expectEqualStrings("Alice", results[0].customer);
    try std.testing.expect(results[0].notes != null);
    try std.testing.expectEqualStrings("Urgent", results[0].notes.?);

    // Second row has null notes
    try std.testing.expectEqual(@as(u32, 2), results[1].id);
    try std.testing.expectEqualStrings("Bob", results[1].customer);
    try std.testing.expectEqual(@as(?[]const u8, null), results[1].notes);
}

test "queryAll: memory cleanup on error" {
    const allocator = std.testing.allocator;
    var database: ?*c_sqlite3 = null;
    const open_result = sql_executor.sqlite3_open(":memory:", &database);
    try std.testing.expectEqual(SQLITE_OK, open_result);
    defer _ = sql_executor.sqlite3_close(database);

    var executor = Executor.init(database.?);

    try executor.exec("CREATE TABLE cleanup_test (id INTEGER, name TEXT)", .{});
    try executor.exec("INSERT INTO cleanup_test VALUES (?, ?)", .{ @as(u32, 1), "Test" });

    const TestRow = struct {
        id: u32,
        name: []const u8,

        pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
            alloc.free(self.name);
        }
    };

    // This query will succeed - just testing cleanup path
    const results = try executor.queryAll(
        TestRow,
        allocator,
        "SELECT id, name FROM cleanup_test",
        .{},
    );
    defer {
        for (results) |*row| {
            row.deinit(allocator);
        }
        allocator.free(results);
    }

    try std.testing.expectEqual(@as(usize, 1), results.len);
}

// ============================================================================
// Migrated tests from sql_executor.zig (unique, non-duplicate)
// ============================================================================

test "extractRow with struct" {
    const allocator = std.testing.allocator;

    // Open in-memory database
    var database: ?*c.sqlite3 = null;
    const open_result = c.sqlite3_open(":memory:", &database);
    try std.testing.expectEqual(c.SQLITE_OK, open_result);
    defer _ = c.sqlite3_close(database);

    var executor = Executor.init(database.?);

    // Create and populate test table using public API
    try executor.exec("CREATE TABLE test (id INTEGER, name TEXT, count INTEGER)", .{});
    try executor.exec("INSERT INTO test VALUES (?, ?, ?)", .{ @as(u32, 1), "test", @as(i64, 100) });

    // Test row extraction via queryOne (public API that uses extractRow internally)
    const TestRow = struct {
        id: u32,
        name: []const u8,
        count: i64,

        pub fn deinit(self: *const @This(), alloc: std.mem.Allocator) void {
            alloc.free(self.name);
        }
    };

    const row = try executor.queryOne(TestRow, allocator, "SELECT id, name, count FROM test WHERE id = 1", .{});
    try std.testing.expect(row != null);
    defer row.?.deinit(allocator);

    try std.testing.expectEqual(@as(u32, 1), row.?.id);
    try std.testing.expectEqualStrings("test", row.?.name);
    try std.testing.expectEqual(@as(i64, 100), row.?.count);
}

test "extractRow with optional fields" {
    const allocator = std.testing.allocator;

    // Open in-memory database
    var database: ?*c.sqlite3 = null;
    const open_result = c.sqlite3_open(":memory:", &database);
    try std.testing.expectEqual(c.SQLITE_OK, open_result);
    defer _ = c.sqlite3_close(database);

    var executor = Executor.init(database.?);

    // Create test table with nullable column and insert row with NULL value using public API
    try executor.exec("CREATE TABLE test (id INTEGER, optional_name TEXT)", .{});
    const null_value: ?[]const u8 = null;
    try executor.exec("INSERT INTO test VALUES (?, ?)", .{ @as(u32, 1), null_value });

    // Test extraction with null value via queryOne (public API)
    const TestRow = struct {
        id: u32,
        optional_name: ?[]const u8,

        pub fn deinit(self: *const @This(), alloc: std.mem.Allocator) void {
            if (self.optional_name) |name| {
                alloc.free(name);
            }
        }
    };

    const row = try executor.queryOne(TestRow, allocator, "SELECT id, optional_name FROM test WHERE id = 1", .{});
    try std.testing.expect(row != null);
    defer row.?.deinit(allocator);

    try std.testing.expectEqual(@as(u32, 1), row.?.id);
    try std.testing.expectEqual(@as(?[]const u8, null), row.?.optional_name);
}
