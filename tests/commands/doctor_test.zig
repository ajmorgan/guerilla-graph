//! Tests for doctor command (doctor_commands.handleDoctor).
//!
//! Tests verify health check behavior:
//! - Executing without arguments (stub implementation)
//! - JSON output mode support
//! - Argument validation (rejects any arguments)

const std = @import("std");
const guerilla_graph = @import("guerilla_graph");
const doctor_commands = guerilla_graph.doctor_commands;
const Storage = guerilla_graph.storage.Storage;
const utils = guerilla_graph.utils;
const CommandError = doctor_commands.CommandError;
const test_utils = @import("../test_utils.zig");

test "special_commands.handleDoctor: executes without error (stub, no arguments)" {
    // Methodology: Verify stub implementation runs without crashing.
    // Storage.healthCheck exists and is ready. Integration blocked on workspace discovery.

    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    // Create temp storage
    const db_path = try test_utils.getTemporaryDatabasePath(allocator, "test_doctor_exec");
    defer allocator.free(db_path);
    defer test_utils.cleanupDatabaseFile(io, db_path);

    var test_storage = try Storage.init(allocator, db_path);
    defer test_storage.deinit();

    const args = &[_][]const u8{};

    // Should not error even though it's a no-op stub
    try doctor_commands.handleDoctor(io, allocator, args, false, &test_storage);
}

test "special_commands.handleDoctor: json output mode (stub)" {
    // Methodology: Verify stub implementation runs without crashing in JSON mode.
    // JSON output mode will be fully implemented when workspace discovery is complete.

    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    // Create temp storage
    const db_path = try test_utils.getTemporaryDatabasePath(allocator, "test_doctor_json");
    defer allocator.free(db_path);
    defer test_utils.cleanupDatabaseFile(io, db_path);

    var test_storage = try Storage.init(allocator, db_path);
    defer test_storage.deinit();

    const args = &[_][]const u8{};

    // Should not error with JSON mode enabled
    try doctor_commands.handleDoctor(io, allocator, args, true, &test_storage);
}

test "special_commands.handleDoctor: rejects arguments" {
    // Methodology: Doctor command takes no arguments.
    // Any provided arguments should be rejected.

    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    // Create temp storage
    const db_path = try test_utils.getTemporaryDatabasePath(allocator, "test_doctor_reject");
    defer allocator.free(db_path);
    defer test_utils.cleanupDatabaseFile(io, db_path);

    var test_storage = try Storage.init(allocator, db_path);
    defer test_storage.deinit();

    const args = &[_][]const u8{"--something"};

    const result = doctor_commands.handleDoctor(io, allocator, args, false, &test_storage);
    try std.testing.expectError(CommandError.InvalidArgument, result);
}

test "special_commands.handleDoctor: rejects extra positional arguments" {
    // Methodology: Doctor command takes no positional arguments.
    // Any provided positional arguments should be rejected.

    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    // Create temp storage
    const db_path = try test_utils.getTemporaryDatabasePath(allocator, "test_doctor_extra");
    defer allocator.free(db_path);
    defer test_utils.cleanupDatabaseFile(io, db_path);

    var test_storage = try Storage.init(allocator, db_path);
    defer test_storage.deinit();

    const args = &[_][]const u8{"extra"};

    const result = doctor_commands.handleDoctor(io, allocator, args, false, &test_storage);
    try std.testing.expectError(CommandError.InvalidArgument, result);
}

// ============================================================================
// Blocked Command Tests (merged from commands/blocked_test.zig)
// ============================================================================

const blocked_commands = guerilla_graph.blocked_commands;

test "blocked_commands.handleQueryBlocked: executes without error (stub)" {
    // Methodology: Verify stub implementation runs without crashing.
    // Storage.getBlockedTasks exists and is ready (but needs modification to return blocker counts).
    // Integration blocked on workspace discovery.

    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    // Create temp storage
    const db_path = try test_utils.getTemporaryDatabasePath(allocator, "test_blocked_exec");
    defer allocator.free(db_path);
    defer test_utils.cleanupDatabaseFile(io, db_path);

    var test_storage = try Storage.init(allocator, db_path);
    defer test_storage.deinit();

    const args = &[_][]const u8{};

    // Should not error even though it's a no-op stub
    try blocked_commands.handleQueryBlocked(io, allocator, args, false, &test_storage);
}

test "blocked_commands.handleQueryBlocked: json output mode (stub)" {
    // Methodology: Verify JSON output mode executes without error.
    // JSON mode is used by tools that parse gg output programmatically.

    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    // Create temp storage
    const db_path = try test_utils.getTemporaryDatabasePath(allocator, "test_blocked_json");
    defer allocator.free(db_path);
    defer test_utils.cleanupDatabaseFile(io, db_path);

    var test_storage = try Storage.init(allocator, db_path);
    defer test_storage.deinit();

    const args = &[_][]const u8{};

    // Should not error even though it's a stub
    try blocked_commands.handleQueryBlocked(io, allocator, args, true, &test_storage);
}

test "blocked_commands.handleQueryBlocked: rejects extra arguments" {
    // Methodology: Verify command properly validates arguments.
    // Command takes no arguments and should reject any provided arguments.

    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    // Create temp storage
    const db_path = try test_utils.getTemporaryDatabasePath(allocator, "test_blocked_args");
    defer allocator.free(db_path);
    defer test_utils.cleanupDatabaseFile(io, db_path);

    var test_storage = try Storage.init(allocator, db_path);
    defer test_storage.deinit();

    const args = &[_][]const u8{"unexpected-arg"}; // Command takes no arguments

    const result = blocked_commands.handleQueryBlocked(io, allocator, args, false, &test_storage);

    // Should fail with invalid argument
    try std.testing.expectError(CommandError.InvalidArgument, result);
}
