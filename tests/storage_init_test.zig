//! Tests for Storage initialization and basic operations.
//!
//! Extracted from storage_test.zig (lines 34-149).
//! Covers: init/deinit, schema creation, transactions, bindText/bindInt64 smoke tests.

const std = @import("std");
const guerilla_graph = @import("guerilla_graph");
const Storage = guerilla_graph.storage.Storage;
const SqliteError = guerilla_graph.storage.SqliteError;
const test_utils = @import("test_utils.zig");

// Use re-exported C types from storage to ensure type compatibility
const c = guerilla_graph.storage.c_funcs;

// Import test utilities
const getTemporaryDatabasePath = test_utils.getTemporaryDatabasePath;
const cleanupDatabaseFile = test_utils.cleanupDatabaseFile;
const bindText = test_utils.bindText;
const bindInt64 = test_utils.bindInt64;

test "Storage: init and deinit" {
    const allocator = std.testing.allocator;

    // Test with temporary database file
    const temp_path = "/tmp/test_storage_init.db";

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();

    // Assertions: Verify storage initialized correctly
    try std.testing.expect(storage.database != null);
    try std.testing.expectEqual(allocator, storage.allocator);
}

test "Storage: init creates schema" {
    const allocator = std.testing.allocator;

    // Test with temporary database file
    const temp_path = "/tmp/test_storage_schema.db";

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();

    // Verify tables exist by querying sqlite_master
    const database = storage.database;

    const check_table_sql = "SELECT name FROM sqlite_master WHERE type='table' AND name=?";

    // Check plans table
    var statement: ?*c.sqlite3_stmt = null;
    var result = c.sqlite3_prepare_v2(database, check_table_sql, -1, &statement, null);
    try std.testing.expectEqual(c.SQLITE_OK, result);
    defer _ = c.sqlite3_finalize(statement);

    try bindText(statement.?, 1, "plans");
    result = c.sqlite3_step(statement.?);
    try std.testing.expectEqual(c.SQLITE_ROW, result); // Should find table
}

test "Storage: transaction management" {
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_storage_transaction.db";

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();

    // Test begin/commit
    try storage.beginTransaction();
    try storage.commit();

    // Test begin/rollback
    try storage.beginTransaction();
    storage.rollback(); // Should not error
}

test "bindText: successful binding" {
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_bind_text.db";

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();

    const database = storage.database;

    // Prepare a simple query with text parameter
    const sql = "SELECT ?";
    var statement: ?*c.sqlite3_stmt = null;
    const result = c.sqlite3_prepare_v2(database, sql, -1, &statement, null);
    defer _ = c.sqlite3_finalize(statement);

    try std.testing.expectEqual(c.SQLITE_OK, result);

    // Test binding
    try bindText(statement.?, 1, "test-value");

    // Verify by executing and reading back
    const step_result = c.sqlite3_step(statement.?);
    try std.testing.expectEqual(c.SQLITE_ROW, step_result);

    const text_result = c.sqlite3_column_text(statement.?, 0);
    const text_slice = std.mem.span(text_result);
    try std.testing.expectEqualStrings("test-value", text_slice);
}

test "bindInt64: successful binding" {
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_bind_int64.db";

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();

    const database = storage.database;

    // Prepare a simple query with integer parameter
    const sql = "SELECT ?";
    var statement: ?*c.sqlite3_stmt = null;
    const result = c.sqlite3_prepare_v2(database, sql, -1, &statement, null);
    defer _ = c.sqlite3_finalize(statement);

    try std.testing.expectEqual(c.SQLITE_OK, result);

    // Test binding
    const test_value: i64 = 1234567890;
    try bindInt64(statement.?, 1, test_value);

    // Verify by executing and reading back
    const step_result = c.sqlite3_step(statement.?);
    try std.testing.expectEqual(c.SQLITE_ROW, step_result);

    const int_result = c.sqlite3_column_int64(statement.?, 0);
    try std.testing.expectEqual(test_value, int_result);
}
