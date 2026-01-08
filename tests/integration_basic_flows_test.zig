//! Integration tests for basic CRUD workflows (integration_test.zig).
//!
//! Covers: Label creation, task creation/retrieval, label listing, task deletion,
//! and AUTOINCREMENT ID sequencing.

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
// Integration Test: Feature Creation Flow
// ============================================================================

test "integration: create-label flow" {
    // Rationale: This test covers the complete workflow:
    // 1. Create a label through the task manager
    // 2. Retrieve the label to verify it was created
    // 3. Verify the label has correct fields
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    // Create temporary database for this test
    const database_path = try getTemporaryDatabasePath(allocator, "create_label_flow");
    defer allocator.free(database_path);
    defer cleanupDatabaseFile(io, database_path);

    // Initialize storage
    var test_storage = try Storage.init(allocator, database_path);
    defer test_storage.deinit();

    // Initialize task manager
    var test_task_manager = TaskManager.init(allocator, &test_storage);
    defer test_task_manager.deinit();

    // Step 1: Create a label
    const plan_id = "authentication";
    const title = "Authentication System";
    const description = "User login, registration, and session management";

    try test_task_manager.createPlan(plan_id, title, description);

    // Step 2: Retrieve the label
    const retrieved_label = try test_task_manager.getPlan(plan_id);
    try std.testing.expect(retrieved_label != null);
    var label = retrieved_label.?;
    defer label.deinit(allocator);

    // Assertions: Verify label has correct fields
    try std.testing.expectEqualStrings(plan_id, label.slug);
    try std.testing.expect(label.id > 0); // INTEGER ID should be positive
    try std.testing.expectEqualStrings(title, label.title);
    try std.testing.expectEqualStrings(description, label.description);
    // LabelSummary includes task counts (should all be 0 for new label)
    try std.testing.expectEqual(@as(u32, 0), label.total_tasks);
    try std.testing.expectEqual(@as(u32, 0), label.completed_tasks);
}

// ============================================================================
// Integration Test: Task Creation and Retrieval
// ============================================================================

test "integration: create-task and show flow" {
    // Rationale: This test covers task creation workflow:
    // 1. Create a label first (prerequisite for tasks)
    // 2. Create a task under the label
    // 3. Retrieve the task to verify it was created
    // 4. Verify task has correct fields and links to label
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    // Create temporary database for this test
    const database_path = try getTemporaryDatabasePath(allocator, "create_task_flow");
    defer allocator.free(database_path);
    defer cleanupDatabaseFile(io, database_path);

    // Initialize storage and task manager
    var test_storage = try Storage.init(allocator, database_path);
    defer test_storage.deinit();

    var test_task_manager = TaskManager.init(allocator, &test_storage);
    defer test_task_manager.deinit();

    // Step 0: Create prerequisite label
    const plan_id = "payments";
    const label_title = "Payment Processing";
    const label_description = "Payment integration and processing";

    try test_task_manager.createPlan(plan_id, label_title, label_description);

    // Step 1: Create a task under the label
    const task_title = "Add Stripe integration";
    const task_description = "Integrate Stripe payment processing API";
    const empty_deps: []const u32 = &[_]u32{};

    const created_task_id: u32 = try test_task_manager.createTask(plan_id, task_title, task_description, empty_deps);

    // Step 2: Retrieve the task
    const retrieved_task = try test_task_manager.getTask(created_task_id);
    try std.testing.expect(retrieved_task != null);
    var task = retrieved_task.?;
    defer task.deinit(allocator);

    // Assertions: Verify task has correct fields
    try std.testing.expectEqual(created_task_id, task.id);
    try std.testing.expectEqualStrings(plan_id, task.plan_slug);
    try std.testing.expect(task.plan_id > 0); // INTEGER plan_id should be positive
    try std.testing.expectEqualStrings(task_title, task.title);
    try std.testing.expectEqualStrings(task_description, task.description);
    try std.testing.expectEqual(types.TaskStatus.open, task.status);
    try std.testing.expect(task.created_at > 0);
    try std.testing.expectEqual(task.created_at, task.updated_at);
    try std.testing.expect(task.completed_at == null);
}

// ============================================================================
// Integration Test: Label Listing
// ============================================================================

test "integration: list-labels flow" {
    // Rationale: This test covers label listing workflow:
    // 1. Create multiple labels
    // 2. Retrieve list of all labels
    // 3. Verify all created labels appear in the list
    // 4. Verify labels contain aggregated task counts
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    // Create temporary database for this test
    const database_path = try getTemporaryDatabasePath(allocator, "list_labels_flow");
    defer allocator.free(database_path);
    defer cleanupDatabaseFile(io, database_path);

    // Initialize storage and task manager
    var test_storage = try Storage.init(allocator, database_path);
    defer test_storage.deinit();

    var test_task_manager = TaskManager.init(allocator, &test_storage);
    defer test_task_manager.deinit();

    // Step 1: Create multiple labels
    const label1_id = "authentication";
    const label2_id = "payments";
    const label3_id = "notifications";

    try test_task_manager.createPlan(label1_id, "Authentication", "User auth system");
    try test_task_manager.createPlan(label2_id, "Payments", "Payment processing");
    try test_task_manager.createPlan(label3_id, "Notifications", "User notifications");

    // Step 2: Retrieve list of labels
    var label_summaries = try test_task_manager.listPlans();
    defer {
        for (label_summaries) |*summary| {
            summary.deinit(allocator);
        }
        allocator.free(label_summaries);
    }

    // Assertions: Verify all labels are in the list (at least 2)
    try std.testing.expect(label_summaries.len >= 2);

    // Verify each created label appears in the list
    var found_count: u32 = 0;
    for (label_summaries) |summary| {
        if (std.mem.eql(u8, summary.slug, label1_id) or
            std.mem.eql(u8, summary.slug, label2_id) or
            std.mem.eql(u8, summary.slug, label3_id))
        {
            found_count += 1;
        }
    }
    try std.testing.expectEqual(@as(u32, 3), found_count);
}

// ============================================================================
// Integration Test: Task Deletion
// ============================================================================

test "integration: delete-task flow" {
    // Rationale: This test covers task deletion workflow:
    // 1. Create a label and task
    // 2. Verify task exists
    // 3. Delete the task
    // 4. Verify task no longer exists
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    // Create temporary database for this test
    const database_path = try getTemporaryDatabasePath(allocator, "delete_task_flow");
    defer allocator.free(database_path);
    defer cleanupDatabaseFile(io, database_path);

    // Initialize storage and task manager
    var test_storage = try Storage.init(allocator, database_path);
    defer test_storage.deinit();

    var test_task_manager = TaskManager.init(allocator, &test_storage);
    defer test_task_manager.deinit();

    // Step 0: Create label and task
    const plan_id = "cleanup";
    try test_task_manager.createPlan(plan_id, "Cleanup", "Cleanup tasks");

    const empty_deps: []const u32 = &[_]u32{};
    const task_id: u32 = try test_task_manager.createTask(plan_id, "Remove old logs", "Delete old log files", empty_deps);

    // Step 1: Verify task exists
    var task = (try test_task_manager.getTask(task_id)).?;
    defer task.deinit(allocator);
    try std.testing.expectEqual(task_id, task.id);

    // Step 2: Delete the task
    try test_task_manager.deleteTask(task_id);

    // Step 3: Verify task no longer exists
    const deleted_task = try test_task_manager.getTask(task_id);
    try std.testing.expect(deleted_task == null);
}

// ============================================================================
// Integration Test: AUTOINCREMENT Sequential IDs
// ============================================================================

test "integration: AUTOINCREMENT sequential IDs" {
    // Methodology: Test that AUTOINCREMENT generates sequential integer IDs.
    // This validates that task IDs are predictable and monotonically increasing.
    //
    // Rationale: Sequential IDs make it easy to reference tasks by number and ensure
    // IDs are never reused, even after deletion (important for audit trails).
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    // Create temporary database for this test
    const database_path = try getTemporaryDatabasePath(allocator, "autoincrement_seq");
    defer allocator.free(database_path);
    defer cleanupDatabaseFile(io, database_path);

    // Initialize storage
    var test_storage = try Storage.init(allocator, database_path);
    defer test_storage.deinit();

    // Step 0: Create label first (required for tasks)
    try test_storage.createPlan("auth", "Auth", "Authentication", null);

    // Step 1: Create three tasks sequentially
    // They should receive IDs 1, 2, 3 in order
    const id1: u32 = try test_storage.createTask("auth", "Task 1", "First task");
    const id2: u32 = try test_storage.createTask("auth", "Task 2", "Second task");
    const id3: u32 = try test_storage.createTask("auth", "Task 3", "Third task");

    // Assertions: IDs should be sequential starting from 1
    try std.testing.expectEqual(@as(u32, 1), id1);
    try std.testing.expectEqual(@as(u32, 2), id2);
    try std.testing.expectEqual(@as(u32, 3), id3);

    // Step 2: Verify all tasks can be retrieved by their IDs
    var task1 = (try test_storage.getTask(id1)) orelse return error.TaskNotFound;
    defer task1.deinit(allocator);
    var task2 = (try test_storage.getTask(id2)) orelse return error.TaskNotFound;
    defer task2.deinit(allocator);
    var task3 = (try test_storage.getTask(id3)) orelse return error.TaskNotFound;
    defer task3.deinit(allocator);

    // Assertions: Each task should have the correct ID and title
    try std.testing.expectEqual(id1, task1.id);
    try std.testing.expectEqualStrings("Task 1", task1.title);
    try std.testing.expectEqual(id2, task2.id);
    try std.testing.expectEqualStrings("Task 2", task2.title);
    try std.testing.expectEqual(id3, task3.id);
    try std.testing.expectEqualStrings("Task 3", task3.title);
}
