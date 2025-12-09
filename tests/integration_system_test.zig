//! Integration tests for system health checks and diagnostics (integration_test.zig).
//!
//! Covers: Database health checks, system diagnostics, and JSON output formatting (future).

const std = @import("std");
const guerilla_graph = @import("guerilla_graph");
const Storage = guerilla_graph.storage.Storage;
const TaskManager = guerilla_graph.task_manager.TaskManager;
const storage = guerilla_graph.storage;
const task_manager = guerilla_graph.task_manager;
const test_utils = @import("test_utils.zig");

// Import test utilities
const getTemporaryDatabasePath = test_utils.getTemporaryDatabasePath;
const cleanupDatabaseFile = test_utils.cleanupDatabaseFile;

// ============================================================================
// Integration Test: Database Health Check
// ============================================================================

test "integration: database health check flow" {
    // Rationale: This test covers system health check workflow:
    // 1. Create a database with valid data
    // 2. Run health checks
    // 3. Verify health report indicates no errors
    // 4. Verify health report structure is valid
    const allocator = std.testing.allocator;

    // Create temporary database for this test
    const database_path = try getTemporaryDatabasePath(allocator, "health_check_flow");
    defer allocator.free(database_path);
    defer cleanupDatabaseFile(database_path);

    // Initialize storage and task manager
    var test_storage = try storage.Storage.init(allocator, database_path);
    defer test_storage.deinit();

    var test_task_manager = task_manager.TaskManager.init(allocator, &test_storage);
    defer test_task_manager.deinit();

    // Step 0: Create some valid data
    const plan_id = "health";
    try test_task_manager.createPlan(plan_id, "Health", "Health checks");

    const empty_deps: []const u32 = &[_]u32{};
    const task_result = try test_task_manager.createTask(plan_id, "Task 1", "First task", empty_deps);
    _ = task_result; // Ignore return value (task_id and plan_task_number)

    // Step 1: Run health checks
    var health_report = try test_task_manager.healthCheck();
    defer health_report.deinit(allocator);

    // Assertions: Valid database should have no critical errors
    try std.testing.expectEqual(@as(usize, 0), health_report.errors.len);
    try std.testing.expect(health_report.warnings.len >= 0); // Warnings are optional
}

// ============================================================================
// Integration Test: JSON Output Mode
// ============================================================================
// NOTE: This test is intentionally skipped as it requires format module
// implementation for JSON output, which is planned for a future phase.

test "integration: json output mode - requires format module" {
    // Rationale: This test would cover JSON output mode functionality:
    // 1. Format tasks/labels as JSON
    // 2. Verify JSON structure and validity
    // 3. Test error responses in JSON format
    //
    // SKIPPED: Requires format module with JSON serialization functions.
    // Format module is not yet implemented (future phase).
    return error.SkipZigTest;

    // const allocator = std.testing.allocator;
    //
    // // Create temporary database for this test
    // const database_path = try getTemporaryDatabasePath(allocator, "json_output_mode");
    // defer allocator.free(database_path);
    // defer cleanupDatabaseFile(database_path);
    //
    // // Initialize storage and task manager
    // var test_storage = try storage.Storage.init(allocator, database_path);
    // defer test_storage.deinit();
    //
    // var test_task_manager = task_manager.TaskManager.init(allocator, &test_storage);
    // defer test_task_manager.deinit();
    //
    // // Step 0: Create label and tasks
    // const plan_id = "json_test";
    // const created_plan_id = try test_task_manager.createPlan(plan_id, "JSON Test", "Testing JSON output");
    // defer allocator.free(created_plan_id);
    //
    // const task1_id = try test_task_manager.createTask(plan_id, "Task One", "First test task");
    // const task2_id = try test_task_manager.createTask(plan_id, "Task Two", "Second test task");
    // defer allocator.free(task1_id);
    // defer allocator.free(task2_id);
    //
    // // Step 1: Format task as JSON and verify valid JSON structure
    // var json_output = try format.formatTaskAsJSON(allocator, &task1_id);
    // defer allocator.free(json_output);
    //
    // // Assertions: Verify JSON output is valid and contains required fields
    // try std.testing.expect(std.mem.startsWith(u8, json_output, "{"));
    // try std.testing.expect(std.mem.endsWith(u8, json_output, "}"));
    // try std.testing.expect(std.mem.indexOf(u8, json_output, "\"id\"") != null);
    // try std.testing.expect(std.mem.indexOf(u8, json_output, "\"title\"") != null);
    // try std.testing.expect(std.mem.indexOf(u8, json_output, "\"status\"") != null);
    //
    // // Step 2: Format task list as JSON
    // var task_list: [2][]const u8 = .{ task1_id, task2_id };
    // var json_list_output = try format.formatTaskListAsJSON(allocator, &task_list);
    // defer allocator.free(json_list_output);
    //
    // // Assertions: Verify JSON list is array format
    // try std.testing.expect(std.mem.startsWith(u8, json_list_output, "["));
    // try std.testing.expect(std.mem.endsWith(u8, json_list_output, "]"));
    // try std.testing.expect(std.mem.count(u8, json_list_output, "{") >= 2);
    //
    // // Step 3: Test error response in JSON format
    // var error_json_output = try format.formatErrorAsJSON(allocator, "test error", "command_failed");
    // defer allocator.free(error_json_output);
    //
    // // Assertions: Verify error JSON structure
    // try std.testing.expect(std.mem.startsWith(u8, error_json_output, "{"));
    // try std.testing.expect(std.mem.indexOf(u8, error_json_output, "\"error\"") != null);
    // try std.testing.expect(std.mem.indexOf(u8, error_json_output, "\"message\"") != null);
}
