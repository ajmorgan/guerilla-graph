//! Integration tests for task lifecycle state transitions.
//!
//! Covers: Task state transitions (open → in_progress → completed).

const std = @import("std");
const guerilla_graph = @import("guerilla_graph");
const Storage = guerilla_graph.storage.Storage;
const TaskManager = guerilla_graph.task_manager.TaskManager;
const storage = guerilla_graph.storage;
const task_manager = guerilla_graph.task_manager;
const types = guerilla_graph.types;
const test_utils = @import("test_utils.zig");

// Import test utilities
const getTemporaryDatabasePath = test_utils.getTemporaryDatabasePath;
const cleanupDatabaseFile = test_utils.cleanupDatabaseFile;

// ============================================================================
// Integration Test: Task Lifecycle (Create → Start → Complete)
// ============================================================================

test "integration: task lifecycle - create, start, complete" {
    // Methodology: Test the complete task lifecycle from creation through completion.
    // This test validates:
    // 1. Task creation with status=open, completed_at=null
    // 2. Starting task transitions to status=in_progress, updated_at changes
    // 3. Completing task transitions to status=completed, completed_at is set
    //
    // Rationale: This test ensures all state transitions work correctly and timestamps
    // are managed properly throughout the task lifecycle. Each transition is verified
    // with assertions on status fields and timestamp updates.
    const allocator = std.testing.allocator;

    // Create temporary database for this test
    const database_path = try getTemporaryDatabasePath(allocator, "task_lifecycle");
    defer allocator.free(database_path);
    defer cleanupDatabaseFile(database_path);

    // Initialize storage and task manager
    var test_storage = try storage.Storage.init(allocator, database_path);
    defer test_storage.deinit();

    var test_task_manager = task_manager.TaskManager.init(allocator, &test_storage);
    defer test_task_manager.deinit();

    // Step 0: Create prerequisite label
    const plan_id = "lifecycle";
    try test_task_manager.createPlan(plan_id, "Task Lifecycle Test", "Testing state transitions");

    // Step 1: Create a task and verify initial state
    // Rationale: Tasks start in 'open' status with no completed_at timestamp
    const empty_deps: []const u32 = &[_]u32{};
    const task_id: u32 = try test_task_manager.createTask(
        plan_id,
        "Implement feature",
        "Test task for lifecycle validation",
        empty_deps,
    );

    // Verify task was created successfully
    const task_after_create_opt = try test_storage.getTask(task_id);
    try std.testing.expect(task_after_create_opt != null);
    var task_after_create = task_after_create_opt.?;
    defer task_after_create.deinit(allocator);

    // Assertions: Initial state should be open with no completed_at
    try std.testing.expectEqual(task_id, task_after_create.id);
    try std.testing.expectEqual(types.TaskStatus.open, task_after_create.status);
    try std.testing.expect(task_after_create.completed_at == null);
    try std.testing.expect(task_after_create.created_at > 0);
    try std.testing.expectEqual(task_after_create.created_at, task_after_create.updated_at);

    // Capture initial timestamps for comparison
    const initial_created_at = task_after_create.created_at;
    const initial_updated_at = task_after_create.updated_at;

    // Step 2: Start the task (open -> in_progress)
    // Rationale: Starting a task should update status to in_progress and bump updated_at
    try test_storage.startTask(task_id);

    const task_after_start_opt = try test_storage.getTask(task_id);
    try std.testing.expect(task_after_start_opt != null);
    var task_after_start = task_after_start_opt.?;
    defer task_after_start.deinit(allocator);

    // Assertions: Status should be in_progress, completed_at still null, updated_at changed
    try std.testing.expectEqual(types.TaskStatus.in_progress, task_after_start.status);
    try std.testing.expect(task_after_start.completed_at == null);
    try std.testing.expectEqual(initial_created_at, task_after_start.created_at);
    try std.testing.expect(task_after_start.updated_at >= initial_updated_at);

    // Capture updated timestamp
    const after_start_updated_at = task_after_start.updated_at;

    // Step 3: Complete the task (in_progress -> completed)
    // Rationale: Completing a task should set status to completed, set completed_at, update updated_at
    try test_storage.completeTask(task_id);

    const task_after_complete_opt = try test_storage.getTask(task_id);
    try std.testing.expect(task_after_complete_opt != null);
    var task_after_complete = task_after_complete_opt.?;
    defer task_after_complete.deinit(allocator);

    // Assertions: Status should be completed, completed_at set, updated_at changed
    try std.testing.expectEqual(types.TaskStatus.completed, task_after_complete.status);
    try std.testing.expect(task_after_complete.completed_at != null);
    try std.testing.expect(task_after_complete.completed_at.? > 0);
    try std.testing.expectEqual(initial_created_at, task_after_complete.created_at);
    try std.testing.expect(task_after_complete.updated_at >= after_start_updated_at);
    try std.testing.expect(task_after_complete.completed_at.? >= after_start_updated_at);

    // Final assertions: Verify timestamps are ordered correctly
    // created_at <= all other timestamps
    const completed_at_value = task_after_complete.completed_at.?;
    try std.testing.expect(initial_created_at <= initial_updated_at);
    try std.testing.expect(initial_created_at <= after_start_updated_at);
    try std.testing.expect(initial_created_at <= completed_at_value);
    try std.testing.expect(initial_created_at <= task_after_complete.updated_at);
}
