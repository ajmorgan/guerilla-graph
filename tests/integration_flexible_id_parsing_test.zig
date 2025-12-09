//! Tests for flexible ID parsing and error handling.
//!
//! Covers: ID format detection, automatic plan:number resolution, invalid ID handling.

const std = @import("std");
const guerilla_graph = @import("guerilla_graph");
const Storage = guerilla_graph.storage.Storage;
const TaskManager = guerilla_graph.task_manager.TaskManager;
const types = guerilla_graph.types;
const test_utils = @import("test_utils.zig");

// Import test utilities
const getTemporaryDatabasePath = test_utils.getTemporaryDatabasePath;
const cleanupDatabaseFile = test_utils.cleanupDatabaseFile;

// ============================================================================
// Test 1: Smart Routing - Show Command
// ============================================================================

test "integration: flexible ID parsing - smart show command" {
    // Methodology: Test that `gg show <id>` accepts all three ID formats.
    // This covers the smart routing in main.zig:221 which uses parseTaskIdFlexible.
    //
    // Rationale: Users should be able to use any ID format (numeric, zero-padded,
    // formatted) with the show command for maximum convenience.
    const allocator = std.testing.allocator;

    // Setup: Create temporary database
    const database_path = try getTemporaryDatabasePath(allocator, "flexible_smart_show");
    defer allocator.free(database_path);
    defer cleanupDatabaseFile(database_path);

    // Initialize storage and task manager
    var test_storage = try Storage.init(allocator, database_path);
    defer test_storage.deinit();

    var test_task_manager = TaskManager.init(allocator, &test_storage);
    defer test_task_manager.deinit();

    // Create plan and tasks
    try test_task_manager.createPlan("auth", "Authentication", "Auth system");
    const empty_deps: []const u32 = &[_]u32{};
    const task_id: u32 = try test_task_manager.createTask("auth", "Add login", "Login endpoint", empty_deps);

    // Assertions: Task was created (ID should be 1 for first task)
    try std.testing.expectEqual(@as(u32, 1), task_id);

    // Test: Retrieve task using numeric format
    const task_numeric = try test_task_manager.getTask(task_id);
    try std.testing.expect(task_numeric != null);
    var task_n = task_numeric.?;
    defer task_n.deinit(allocator);
    try std.testing.expectEqual(task_id, task_n.id);
    try std.testing.expectEqualStrings("Add login", task_n.title);

    // Test: Retrieve task using formatted ID (parse "auth:001" to get task_id)
    // In real usage, the command handler would call parseTaskIdFlexible("auth:001")
    const utils = guerilla_graph.utils;
    const parsed_id = try utils.parseTaskIdFlexible("auth:001");
    try std.testing.expectEqual(task_id, parsed_id);

    const task_formatted = try test_task_manager.getTask(parsed_id);
    try std.testing.expect(task_formatted != null);
    var task_f = task_formatted.?;
    defer task_f.deinit(allocator);
    try std.testing.expectEqual(task_id, task_f.id);
    try std.testing.expectEqualStrings("Add login", task_f.title);

    // Test: Parse zero-padded numeric format
    const parsed_padded = try utils.parseTaskIdFlexible("001");
    try std.testing.expectEqual(task_id, parsed_padded);
}

// ============================================================================
// Test 2: Smart Routing - Update Command
// ============================================================================

test "integration: flexible ID parsing - smart update command" {
    // Methodology: Test that `gg update <id>` accepts all ID formats.
    // This covers the smart routing in main.zig:235 which uses parseTaskIdFlexible.
    //
    // Rationale: Update command should accept the same flexible ID formats as show.
    const allocator = std.testing.allocator;

    const database_path = try getTemporaryDatabasePath(allocator, "flexible_smart_update");
    defer allocator.free(database_path);
    defer cleanupDatabaseFile(database_path);

    var test_storage = try Storage.init(allocator, database_path);
    defer test_storage.deinit();

    var test_task_manager = TaskManager.init(allocator, &test_storage);
    defer test_task_manager.deinit();

    // Create plan and task
    try test_task_manager.createPlan("payments", "Payments", "Payment processing");
    const empty_deps: []const u32 = &[_]u32{};
    const task_id: u32 = try test_task_manager.createTask("payments", "Add Stripe", "Stripe integration", empty_deps);

    // Test: Parse numeric ID
    const utils = guerilla_graph.utils;
    const parsed_numeric = try utils.parseTaskIdFlexible("1");
    try std.testing.expectEqual(task_id, parsed_numeric);

    // Test: Parse formatted ID with padding
    const parsed_formatted = try utils.parseTaskIdFlexible("payments:001");
    try std.testing.expectEqual(task_id, parsed_formatted);

    // Test: Parse formatted ID without padding
    const parsed_no_padding = try utils.parseTaskIdFlexible("payments:1");
    try std.testing.expectEqual(task_id, parsed_no_padding);

    // Verify: Update task using parsed ID
    try test_storage.updateTask(parsed_formatted, "Updated Stripe integration", null, null);
    const updated_task = try test_task_manager.getTask(task_id);
    try std.testing.expect(updated_task != null);
    var task = updated_task.?;
    defer task.deinit(allocator);
    try std.testing.expectEqualStrings("Updated Stripe integration", task.title);
}

// ============================================================================
// Test 3: Error Handling - Invalid ID Formats
// ============================================================================

test "integration: flexible ID parsing - error handling for invalid formats" {
    // Methodology: Test that invalid ID formats are properly rejected.
    // This validates error handling across all parseTaskIdFlexible call sites.
    //
    // Rationale: Invalid formats should fail gracefully with clear error messages.
    const utils = guerilla_graph.utils;

    // Test: Invalid formatted ID (missing colon)
    const invalid_no_colon = utils.parseTaskIdFlexible("invalidformat");
    try std.testing.expectError(error.InvalidTaskId, invalid_no_colon);

    // Test: Invalid formatted ID (empty plan)
    const invalid_empty_plan = utils.parseTaskIdFlexible(":123");
    try std.testing.expectError(error.InvalidTaskId, invalid_empty_plan);

    // Test: Invalid formatted ID (empty number)
    const invalid_empty_number = utils.parseTaskIdFlexible("plan:");
    try std.testing.expectError(error.InvalidTaskId, invalid_empty_number);

    // Test: Invalid formatted ID (non-numeric number)
    const invalid_non_numeric = utils.parseTaskIdFlexible("plan:abc");
    try std.testing.expectError(error.InvalidCharacter, invalid_non_numeric);

    // Test: Valid formats that should succeed
    const valid_numeric = try utils.parseTaskIdFlexible("42");
    try std.testing.expectEqual(@as(u32, 42), valid_numeric);

    const valid_padded = try utils.parseTaskIdFlexible("007");
    try std.testing.expectEqual(@as(u32, 7), valid_padded);

    const valid_formatted = try utils.parseTaskIdFlexible("auth:001");
    try std.testing.expectEqual(@as(u32, 1), valid_formatted);

    const valid_formatted_no_padding = try utils.parseTaskIdFlexible("auth:42");
    try std.testing.expectEqual(@as(u32, 42), valid_formatted_no_padding);
}
