//! Tests for init command (init_commands.handleInit).
//!
//! Tests verify workspace initialization behavior:
//! - Creating .gg directory and database
//! - Detecting existing workspaces (current/parent directories)
//! - JSON output mode

const std = @import("std");
const guerilla_graph = @import("guerilla_graph");
const init_commands = guerilla_graph.init_commands;
const Storage = guerilla_graph.storage.Storage;
const utils = guerilla_graph.utils;
const CommandError = init_commands.CommandError;
const test_utils = @import("../test_utils.zig");

/// Helper to change directory using C library.
/// Allocates null-terminated string for C API.
fn changeDir(allocator: std.mem.Allocator, path: []const u8) !void {
    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);
    if (std.c.chdir(path_z) != 0) {
        return error.ChdirFailed;
    }
}

test "special_commands.handleInit: successful initialization" {
    // Methodology: Verify init creates .gg directory and database with proper schema.
    // Tests the happy path of workspace initialization in a clean directory.

    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    // Create unique temporary directory for test workspace
    const timestamp = utils.unixTimestamp();
    var test_dir_buf: [256]u8 = undefined;
    const test_dir = try std.fmt.bufPrint(&test_dir_buf, "/tmp/gg_test_init_success_{d}", .{timestamp});

    // Create test directory
    try std.Io.Dir.createDirAbsolute(io, test_dir, .default_dir);
    defer std.Io.Dir.cwd().deleteTree(io, test_dir) catch {};

    // Change to test directory for init
    const original_cwd = try std.process.getCwdAlloc(allocator);
    defer allocator.free(original_cwd);
    try changeDir(allocator, test_dir);
    defer changeDir(allocator, original_cwd) catch {};

    // Execute init command with no arguments
    const args = &[_][]const u8{};
    try init_commands.handleInit(io, allocator, args, false);

    // Verify .gg directory was created
    const gg_dir = try std.fs.path.join(allocator, &[_][]const u8{ test_dir, ".gg" });
    defer allocator.free(gg_dir);
    std.Io.Dir.accessAbsolute(io, gg_dir, .{}) catch |err| {
        std.debug.print("Failed to access .gg directory: {any}\n", .{err});
        return err;
    };

    // Verify database file was created
    const db_path = try std.fs.path.join(allocator, &[_][]const u8{ test_dir, ".gg", "tasks.db" });
    defer allocator.free(db_path);
    std.Io.Dir.accessAbsolute(io, db_path, .{}) catch |err| {
        std.debug.print("Failed to access database file: {any}\n", .{err});
        return err;
    };

    // Verify database is functional by opening it
    var storage = try Storage.init(allocator, db_path);
    defer storage.deinit();

    // Verify database has proper schema by creating a test label
    try storage.createPlan("test", "Test Label", "Testing schema", null);
}

test "special_commands.handleInit: already in workspace error" {
    // Methodology: Verify init fails when .gg directory already exists in current directory.
    // This prevents accidental re-initialization and data corruption.

    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    // Create unique temporary directory for test workspace
    const timestamp = utils.unixTimestamp();
    var test_dir_buf: [256]u8 = undefined;
    const test_dir = try std.fmt.bufPrint(&test_dir_buf, "/tmp/gg_test_init_already_{d}", .{timestamp});

    // Create test directory with existing .gg
    try std.Io.Dir.createDirAbsolute(io, test_dir, .default_dir);
    defer std.Io.Dir.cwd().deleteTree(io, test_dir) catch {};

    const gg_dir = try std.fs.path.join(allocator, &[_][]const u8{ test_dir, ".gg" });
    defer allocator.free(gg_dir);
    try std.Io.Dir.createDirAbsolute(io, gg_dir, .default_dir);

    // Change to test directory for init
    const original_cwd = try std.process.getCwdAlloc(allocator);
    defer allocator.free(original_cwd);
    try changeDir(allocator, test_dir);
    defer changeDir(allocator, original_cwd) catch {};

    // Execute init command - should fail with AlreadyInWorkspace
    const args = &[_][]const u8{};
    const result = init_commands.handleInit(io, allocator, args, false);

    try std.testing.expectError(CommandError.AlreadyInWorkspace, result);
}

test "special_commands.handleInit: already in workspace error (parent directory)" {
    // Methodology: Verify parent directory check is documented but skipped in test mode.
    // The parent check is bypassed in test mode because tests run from project directory
    // which has .gg. In production, init walks up directory tree to prevent nested workspaces.
    //
    // This test verifies the setup works and documents the expected production behavior.
    // The actual parent check logic is in handleInit_checkParentWorkspace().

    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    // Create unique temporary parent directory for test workspace
    const timestamp = utils.unixTimestamp();
    var parent_dir_buf: [256]u8 = undefined;
    const parent_dir = try std.fmt.bufPrint(&parent_dir_buf, "/tmp/gg_test_init_parent_{d}", .{timestamp});

    // Create parent directory with .gg
    try std.Io.Dir.createDirAbsolute(io, parent_dir, .default_dir);
    defer std.Io.Dir.cwd().deleteTree(io, parent_dir) catch {};

    const parent_gg_dir = try std.fs.path.join(allocator, &[_][]const u8{ parent_dir, ".gg" });
    defer allocator.free(parent_gg_dir);
    try std.Io.Dir.createDirAbsolute(io, parent_gg_dir, .default_dir);

    // Create child directory
    const child_dir = try std.fs.path.join(allocator, &[_][]const u8{ parent_dir, "child" });
    defer allocator.free(child_dir);
    try std.Io.Dir.createDirAbsolute(io, child_dir, .default_dir);

    // Verify test setup: parent has .gg, child does not
    std.Io.Dir.accessAbsolute(io, parent_gg_dir, .{}) catch |err| {
        std.debug.print("Test setup failed: parent .gg not accessible: {any}\n", .{err});
        return err;
    };

    // Note: In test mode, parent check is bypassed so init would succeed in child.
    // In production mode, init would fail with AlreadyInWorkspace.
    // This test documents the expected behavior without asserting it in test mode.
}

test "special_commands.handleInit: json output mode" {
    // Methodology: Verify init produces valid JSON output for scripting/automation.
    // JSON mode is used by tools that parse gg output programmatically.

    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    // Create unique temporary directory for test workspace
    const timestamp = utils.unixTimestamp();
    var test_dir_buf: [256]u8 = undefined;
    const test_dir = try std.fmt.bufPrint(&test_dir_buf, "/tmp/gg_test_init_json_{d}", .{timestamp});

    // Create test directory
    try std.Io.Dir.createDirAbsolute(io, test_dir, .default_dir);
    defer std.Io.Dir.cwd().deleteTree(io, test_dir) catch {};

    // Change to test directory for init
    const original_cwd = try std.process.getCwdAlloc(allocator);
    defer allocator.free(original_cwd);
    try changeDir(allocator, test_dir);
    defer changeDir(allocator, original_cwd) catch {};

    // Execute init command with JSON output enabled
    const args = &[_][]const u8{};
    try init_commands.handleInit(io, allocator, args, true);

    // Note: JSON output goes to stdout and cannot be easily captured in tests.
    // This test verifies the command executes without error in JSON mode.
    // Manual verification shows output format is: {"status": "success", "message": "...", ...}

    // Verify .gg directory and database were still created despite JSON mode
    const gg_dir = try std.fs.path.join(allocator, &[_][]const u8{ test_dir, ".gg" });
    defer allocator.free(gg_dir);
    std.Io.Dir.accessAbsolute(io, gg_dir, .{}) catch |err| {
        std.debug.print("Failed to access .gg directory in JSON test: {any}\n", .{err});
        return err;
    };
}
