//! Tests for flexible ID in task commands.
//!
//! Covers: new, show, start, complete, update, delete with both ID formats.

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
// Test 1: Task Command - New with Dependencies
// ============================================================================

test "integration: flexible ID parsing - task new with dependencies" {
    // Methodology: Test that task creation with dependencies via TaskManager API works with flexible ID formats.
    // This validates that dependencies can be specified programmatically using any ID format.
    //
    // Rationale: Dependencies are added via 'gg dep add' command, but programmatic API should support flexible formats.
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const database_path = try getTemporaryDatabasePath(allocator, "flexible_task_new_deps");
    defer allocator.free(database_path);
    defer cleanupDatabaseFile(io, database_path);

    var test_storage = try Storage.init(allocator, database_path);
    defer test_storage.deinit();

    var test_task_manager = TaskManager.init(allocator, &test_storage);
    defer test_task_manager.deinit();

    // Create plan and first task
    try test_task_manager.createPlan("backend", "Backend", "Backend services");
    const empty_deps: []const u32 = &[_]u32{};
    const task_1: u32 = try test_task_manager.createTask("backend", "Setup DB", "Initialize database", empty_deps);

    // Test: Create second task with dependency using numeric format
    const deps_numeric = [_]u32{task_1};
    const task_2: u32 = try test_task_manager.createTask("backend", "Add migrations", "DB migrations", &deps_numeric);

    // Verify: task_2 depends on task_1
    const blockers = try test_storage.getBlockers(task_2);
    defer {
        for (blockers) |*blocker| {
            blocker.deinit(allocator);
        }
        allocator.free(blockers);
    }
    try std.testing.expectEqual(@as(usize, 1), blockers.len);
    try std.testing.expectEqual(task_1, blockers[0].id);

    // Test: Create third task with dependency using formatted ID
    const utils = guerilla_graph.utils;
    const parsed_dep = try utils.parseTaskIdFlexible("backend:001");
    try std.testing.expectEqual(task_1, parsed_dep);

    const deps_formatted = [_]u32{parsed_dep};
    const task_3: u32 = try test_task_manager.createTask("backend", "Add seeds", "Seed data", &deps_formatted);

    // Verify: task_3 depends on task_1
    const blockers_3 = try test_storage.getBlockers(task_3);
    defer {
        for (blockers_3) |*blocker| {
            blocker.deinit(allocator);
        }
        allocator.free(blockers_3);
    }
    try std.testing.expectEqual(@as(usize, 1), blockers_3.len);
    try std.testing.expectEqual(task_1, blockers_3[0].id);
}

// ============================================================================
// Test 2: Task Command - Start
// ============================================================================

test "integration: flexible ID parsing - task start command" {
    // Methodology: Test that `gg task start <id>` accepts all ID formats.
    // This covers task.zig:358 which uses parseTaskIdFlexible.
    //
    // Rationale: Start command should work with any ID format for user convenience.
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const database_path = try getTemporaryDatabasePath(allocator, "flexible_task_start");
    defer allocator.free(database_path);
    defer cleanupDatabaseFile(io, database_path);

    var test_storage = try Storage.init(allocator, database_path);
    defer test_storage.deinit();

    var test_task_manager = TaskManager.init(allocator, &test_storage);
    defer test_task_manager.deinit();

    // Create plan and tasks
    try test_task_manager.createPlan("frontend", "Frontend", "Frontend app");
    const empty_deps: []const u32 = &[_]u32{};
    const task_1: u32 = try test_task_manager.createTask("frontend", "Setup React", "React boilerplate", empty_deps);
    const task_2: u32 = try test_task_manager.createTask("frontend", "Add routing", "React Router", empty_deps);

    // Test: Start task using numeric ID
    const utils = guerilla_graph.utils;
    const parsed_1 = try utils.parseTaskIdFlexible("1");
    try std.testing.expectEqual(task_1, parsed_1);
    try test_storage.startTask(parsed_1);

    const task_after_start = try test_task_manager.getTask(task_1);
    try std.testing.expect(task_after_start != null);
    var task = task_after_start.?;
    defer task.deinit(allocator);
    try std.testing.expectEqual(types.TaskStatus.in_progress, task.status);

    // Test: Start task using formatted ID
    const parsed_2 = try utils.parseTaskIdFlexible("frontend:002");
    try std.testing.expectEqual(task_2, parsed_2);
    try test_storage.startTask(parsed_2);

    const task_2_after_start = try test_task_manager.getTask(task_2);
    try std.testing.expect(task_2_after_start != null);
    var task_2_obj = task_2_after_start.?;
    defer task_2_obj.deinit(allocator);
    try std.testing.expectEqual(types.TaskStatus.in_progress, task_2_obj.status);
}

// ============================================================================
// Test 3: Task Command - Complete
// ============================================================================

test "integration: flexible ID parsing - task complete command" {
    // Methodology: Test that `gg task complete <id> [<id>...]` accepts mixed ID formats.
    // This covers task.zig:452 which parses IDs in a loop using parseTaskIdFlexible.
    //
    // Rationale: Bulk complete should accept mixed formats (e.g., "1 auth:002 3").
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const database_path = try getTemporaryDatabasePath(allocator, "flexible_task_complete");
    defer allocator.free(database_path);
    defer cleanupDatabaseFile(io, database_path);

    var test_storage = try Storage.init(allocator, database_path);
    defer test_storage.deinit();

    var test_task_manager = TaskManager.init(allocator, &test_storage);
    defer test_task_manager.deinit();

    // Create plan and tasks
    try test_task_manager.createPlan("api", "API", "REST API");
    const empty_deps: []const u32 = &[_]u32{};
    const task_1: u32 = try test_task_manager.createTask("api", "Add auth endpoint", "POST /auth", empty_deps);
    const task_2: u32 = try test_task_manager.createTask("api", "Add users endpoint", "GET /users", empty_deps);
    const task_3: u32 = try test_task_manager.createTask("api", "Add posts endpoint", "GET /posts", empty_deps);

    // Start all tasks
    try test_storage.startTask(task_1);
    try test_storage.startTask(task_2);
    try test_storage.startTask(task_3);

    // Test: Complete tasks using mixed ID formats
    const utils = guerilla_graph.utils;

    // Parse numeric ID
    const parsed_1 = try utils.parseTaskIdFlexible("1");
    try std.testing.expectEqual(task_1, parsed_1);
    try test_storage.completeTask(parsed_1);

    // Parse formatted ID with padding
    const parsed_2 = try utils.parseTaskIdFlexible("api:002");
    try std.testing.expectEqual(task_2, parsed_2);
    try test_storage.completeTask(parsed_2);

    // Parse zero-padded numeric
    const parsed_3 = try utils.parseTaskIdFlexible("003");
    try std.testing.expectEqual(task_3, parsed_3);
    try test_storage.completeTask(parsed_3);

    // Verify: All tasks are completed
    var t1 = (try test_task_manager.getTask(task_1)).?;
    defer t1.deinit(allocator);
    try std.testing.expectEqual(types.TaskStatus.completed, t1.status);

    var t2 = (try test_task_manager.getTask(task_2)).?;
    defer t2.deinit(allocator);
    try std.testing.expectEqual(types.TaskStatus.completed, t2.status);

    var t3 = (try test_task_manager.getTask(task_3)).?;
    defer t3.deinit(allocator);
    try std.testing.expectEqual(types.TaskStatus.completed, t3.status);
}

// ============================================================================
// Test 4: Task Command - Show
// ============================================================================

test "integration: flexible ID parsing - task show command" {
    // Methodology: Test that `gg task show <id>` accepts all ID formats.
    // This covers task.zig:550 which uses parseTaskIdFlexible.
    //
    // Rationale: Show command should accept same formats as smart routing show.
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const database_path = try getTemporaryDatabasePath(allocator, "flexible_task_show");
    defer allocator.free(database_path);
    defer cleanupDatabaseFile(io, database_path);

    var test_storage = try Storage.init(allocator, database_path);
    defer test_storage.deinit();

    var test_task_manager = TaskManager.init(allocator, &test_storage);
    defer test_task_manager.deinit();

    // Create plan and task
    try test_task_manager.createPlan("docs", "Documentation", "User docs");
    const empty_deps: []const u32 = &[_]u32{};
    const task_id: u32 = try test_task_manager.createTask("docs", "Write API guide", "API documentation", empty_deps);

    const utils = guerilla_graph.utils;

    // Test: Parse and retrieve using numeric ID
    const parsed_numeric = try utils.parseTaskIdFlexible("1");
    try std.testing.expectEqual(task_id, parsed_numeric);
    var task_n = (try test_task_manager.getTask(parsed_numeric)).?;
    defer task_n.deinit(allocator);
    try std.testing.expectEqualStrings("Write API guide", task_n.title);

    // Test: Parse and retrieve using formatted ID
    const parsed_formatted = try utils.parseTaskIdFlexible("docs:001");
    try std.testing.expectEqual(task_id, parsed_formatted);
    var task_f = (try test_task_manager.getTask(parsed_formatted)).?;
    defer task_f.deinit(allocator);
    try std.testing.expectEqualStrings("Write API guide", task_f.title);
}

// ============================================================================
// Test 5: Task Command - Update
// ============================================================================

test "integration: flexible ID parsing - task update command" {
    // Methodology: Test that `gg task update <id>` accepts all ID formats.
    // This covers task.zig:636 which uses parseTaskIdFlexible.
    //
    // Rationale: Update command should accept same formats as smart routing update.
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const database_path = try getTemporaryDatabasePath(allocator, "flexible_task_update");
    defer allocator.free(database_path);
    defer cleanupDatabaseFile(io, database_path);

    var test_storage = try Storage.init(allocator, database_path);
    defer test_storage.deinit();

    var test_task_manager = TaskManager.init(allocator, &test_storage);
    defer test_task_manager.deinit();

    // Create plan and tasks
    try test_task_manager.createPlan("infra", "Infrastructure", "Cloud infra");
    const empty_deps: []const u32 = &[_]u32{};
    const task_1: u32 = try test_task_manager.createTask("infra", "Setup VPC", "Configure VPC", empty_deps);
    const task_2: u32 = try test_task_manager.createTask("infra", "Setup ECS", "Configure ECS", empty_deps);

    const utils = guerilla_graph.utils;

    // Test: Update using numeric ID
    const parsed_1 = try utils.parseTaskIdFlexible("1");
    try std.testing.expectEqual(task_1, parsed_1);
    try test_storage.updateTask(parsed_1, "Updated VPC config", null, null);
    var t1 = (try test_task_manager.getTask(task_1)).?;
    defer t1.deinit(allocator);
    try std.testing.expectEqualStrings("Updated VPC config", t1.title);

    // Test: Update using formatted ID
    const parsed_2 = try utils.parseTaskIdFlexible("infra:002");
    try std.testing.expectEqual(task_2, parsed_2);
    try test_storage.updateTask(parsed_2, "Updated ECS config", null, null);
    var t2 = (try test_task_manager.getTask(task_2)).?;
    defer t2.deinit(allocator);
    try std.testing.expectEqualStrings("Updated ECS config", t2.title);
}

// ============================================================================
// Test 6: Task Command - Delete
// ============================================================================

test "integration: flexible ID parsing - task delete command" {
    // Methodology: Test that `gg task delete <id>` accepts all ID formats.
    // This covers task.zig:808 which uses parseTaskIdFlexible.
    //
    // Rationale: Delete command should accept all ID formats for consistency.
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const database_path = try getTemporaryDatabasePath(allocator, "flexible_task_delete");
    defer allocator.free(database_path);
    defer cleanupDatabaseFile(io, database_path);

    var test_storage = try Storage.init(allocator, database_path);
    defer test_storage.deinit();

    var test_task_manager = TaskManager.init(allocator, &test_storage);
    defer test_task_manager.deinit();

    // Create plan and tasks
    try test_task_manager.createPlan("test", "Testing", "Test tasks");
    const empty_deps: []const u32 = &[_]u32{};
    const task_1: u32 = try test_task_manager.createTask("test", "Task to delete 1", "Will be deleted", empty_deps);
    const task_2: u32 = try test_task_manager.createTask("test", "Task to delete 2", "Will be deleted", empty_deps);

    const utils = guerilla_graph.utils;

    // Test: Delete using numeric ID
    const parsed_1 = try utils.parseTaskIdFlexible("1");
    try std.testing.expectEqual(task_1, parsed_1);
    try test_storage.deleteTask(parsed_1);
    const deleted_1 = try test_task_manager.getTask(task_1);
    try std.testing.expect(deleted_1 == null);

    // Test: Delete using formatted ID
    const parsed_2 = try utils.parseTaskIdFlexible("test:002");
    try std.testing.expectEqual(task_2, parsed_2);
    try test_storage.deleteTask(parsed_2);
    const deleted_2 = try test_task_manager.getTask(task_2);
    try std.testing.expect(deleted_2 == null);
}
