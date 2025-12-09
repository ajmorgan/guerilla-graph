//! Tests for flexible ID in dependency commands.
//!
//! Covers: dep add, dep remove, blockers, dependents with both ID formats.

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
// Test 1: Dependency Command - Add
// ============================================================================

test "integration: flexible ID parsing - dep add command" {
    // Methodology: Test that `gg dep add <id> --blocks-on <id>` accepts all ID formats.
    // This covers dep.zig:55 and dep.zig:73 which use parseTaskIdFlexible.
    //
    // Rationale: Both task_id and blocks_on_id should accept flexible formats.
    const allocator = std.testing.allocator;

    const database_path = try getTemporaryDatabasePath(allocator, "flexible_dep_add");
    defer allocator.free(database_path);
    defer cleanupDatabaseFile(database_path);

    var test_storage = try Storage.init(allocator, database_path);
    defer test_storage.deinit();

    var test_task_manager = TaskManager.init(allocator, &test_storage);
    defer test_task_manager.deinit();

    // Create plan and tasks
    try test_task_manager.createPlan("pipeline", "Pipeline", "CI/CD pipeline");
    const empty_deps: []const u32 = &[_]u32{};
    const task_1: u32 = try test_task_manager.createTask("pipeline", "Build", "Build app", empty_deps);
    const task_2: u32 = try test_task_manager.createTask("pipeline", "Test", "Run tests", empty_deps);
    const task_3: u32 = try test_task_manager.createTask("pipeline", "Deploy", "Deploy app", empty_deps);

    const utils = guerilla_graph.utils;

    // Test: Add dependency using numeric IDs (task_2 blocks_on task_1)
    const parsed_2 = try utils.parseTaskIdFlexible("2");
    const parsed_1 = try utils.parseTaskIdFlexible("1");
    try std.testing.expectEqual(task_2, parsed_2);
    try std.testing.expectEqual(task_1, parsed_1);
    try test_storage.addDependency(parsed_2, parsed_1);

    // Verify: task_2 depends on task_1
    var blockers_2 = try test_storage.getBlockers(task_2);
    defer {
        for (blockers_2) |*blocker| {
            blocker.deinit(allocator);
        }
        allocator.free(blockers_2);
    }
    try std.testing.expectEqual(@as(usize, 1), blockers_2.len);
    try std.testing.expectEqual(task_1, blockers_2[0].id);

    // Test: Add dependency using formatted IDs (task_3 blocks_on task_2)
    const parsed_3 = try utils.parseTaskIdFlexible("pipeline:003");
    const parsed_2_formatted = try utils.parseTaskIdFlexible("pipeline:002");
    try std.testing.expectEqual(task_3, parsed_3);
    try std.testing.expectEqual(task_2, parsed_2_formatted);
    try test_storage.addDependency(parsed_3, parsed_2_formatted);

    // Verify: task_3 depends on task_2
    var blockers_3 = try test_storage.getBlockers(task_3);
    defer {
        for (blockers_3) |*blocker| {
            blocker.deinit(allocator);
        }
        allocator.free(blockers_3);
    }
    try std.testing.expectEqual(@as(usize, 2), blockers_3.len); // task_3 depends on task_2 and task_1 (transitive)
}

// ============================================================================
// Test 2: Dependency Command - Remove
// ============================================================================

test "integration: flexible ID parsing - dep remove command" {
    // Methodology: Test that `gg dep remove <id> --blocks-on <id>` accepts all ID formats.
    // This covers dep.zig:180 and dep.zig:198 which use parseTaskIdFlexible.
    //
    // Rationale: Remove command should accept same formats as add command.
    const allocator = std.testing.allocator;

    const database_path = try getTemporaryDatabasePath(allocator, "flexible_dep_remove");
    defer allocator.free(database_path);
    defer cleanupDatabaseFile(database_path);

    var test_storage = try Storage.init(allocator, database_path);
    defer test_storage.deinit();

    var test_task_manager = TaskManager.init(allocator, &test_storage);
    defer test_task_manager.deinit();

    // Create plan and tasks with dependencies
    try test_task_manager.createPlan("workflow", "Workflow", "Task workflow");
    const empty_deps: []const u32 = &[_]u32{};
    const task_1: u32 = try test_task_manager.createTask("workflow", "Step 1", "First step", empty_deps);
    const task_2: u32 = try test_task_manager.createTask("workflow", "Step 2", "Second step", empty_deps);

    // Add dependency
    try test_storage.addDependency(task_2, task_1);

    const utils = guerilla_graph.utils;

    // Test: Remove dependency using numeric IDs
    const parsed_2 = try utils.parseTaskIdFlexible("2");
    const parsed_1 = try utils.parseTaskIdFlexible("1");
    try std.testing.expectEqual(task_2, parsed_2);
    try std.testing.expectEqual(task_1, parsed_1);
    try test_storage.removeDependency(parsed_2, parsed_1);

    // Verify: task_2 no longer depends on task_1
    var blockers = try test_storage.getBlockers(task_2);
    defer allocator.free(blockers);
    try std.testing.expectEqual(@as(usize, 0), blockers.len);

    // Test: Add and remove using formatted IDs
    const parsed_2_formatted = try utils.parseTaskIdFlexible("workflow:002");
    const parsed_1_formatted = try utils.parseTaskIdFlexible("workflow:001");
    try std.testing.expectEqual(task_2, parsed_2_formatted);
    try std.testing.expectEqual(task_1, parsed_1_formatted);
    try test_storage.addDependency(parsed_2_formatted, parsed_1_formatted);

    var blockers_after_add = try test_storage.getBlockers(task_2);
    defer {
        for (blockers_after_add) |*blocker| {
            blocker.deinit(allocator);
        }
        allocator.free(blockers_after_add);
    }
    try std.testing.expectEqual(@as(usize, 1), blockers_after_add.len);

    try test_storage.removeDependency(parsed_2_formatted, parsed_1_formatted);
    var blockers_after_remove = try test_storage.getBlockers(task_2);
    defer allocator.free(blockers_after_remove);
    try std.testing.expectEqual(@as(usize, 0), blockers_after_remove.len);
}

// ============================================================================
// Test 3: Dependency Command - Blockers and Dependents
// ============================================================================

test "integration: flexible ID parsing - dep blockers and dependents commands" {
    // Methodology: Test that `gg dep blockers <id>` and `gg dep dependents <id>`
    // accept all ID formats. This covers dep.zig:313 and dep.zig:384.
    //
    // Rationale: Query commands should accept flexible ID formats for consistency.
    const allocator = std.testing.allocator;

    const database_path = try getTemporaryDatabasePath(allocator, "flexible_dep_queries");
    defer allocator.free(database_path);
    defer cleanupDatabaseFile(database_path);

    var test_storage = try Storage.init(allocator, database_path);
    defer test_storage.deinit();

    var test_task_manager = TaskManager.init(allocator, &test_storage);
    defer test_task_manager.deinit();

    // Create plan and tasks with dependencies (A -> B -> C chain)
    try test_task_manager.createPlan("chain", "Chain", "Dependency chain");
    const empty_deps: []const u32 = &[_]u32{};
    const task_a: u32 = try test_task_manager.createTask("chain", "Task A", "Foundation", empty_deps);
    const task_b: u32 = try test_task_manager.createTask("chain", "Task B", "Middle", empty_deps);
    const task_c: u32 = try test_task_manager.createTask("chain", "Task C", "Final", empty_deps);

    // Create chain: C blocks_on B, B blocks_on A
    try test_storage.addDependency(task_b, task_a);
    try test_storage.addDependency(task_c, task_b);

    const utils = guerilla_graph.utils;

    // Test: Query blockers using numeric ID
    const parsed_c_numeric = try utils.parseTaskIdFlexible("3");
    try std.testing.expectEqual(task_c, parsed_c_numeric);
    var blockers_c = try test_storage.getBlockers(parsed_c_numeric);
    defer {
        for (blockers_c) |*blocker| {
            blocker.deinit(allocator);
        }
        allocator.free(blockers_c);
    }
    try std.testing.expectEqual(@as(usize, 2), blockers_c.len); // B and A

    // Test: Query blockers using formatted ID
    const parsed_c_formatted = try utils.parseTaskIdFlexible("chain:003");
    try std.testing.expectEqual(task_c, parsed_c_formatted);
    var blockers_c_formatted = try test_storage.getBlockers(parsed_c_formatted);
    defer {
        for (blockers_c_formatted) |*blocker| {
            blocker.deinit(allocator);
        }
        allocator.free(blockers_c_formatted);
    }
    try std.testing.expectEqual(@as(usize, 2), blockers_c_formatted.len);

    // Test: Query dependents using numeric ID
    const parsed_a_numeric = try utils.parseTaskIdFlexible("1");
    try std.testing.expectEqual(task_a, parsed_a_numeric);
    var dependents_a = try test_storage.getDependents(parsed_a_numeric);
    defer {
        for (dependents_a) |*dependent| {
            dependent.deinit(allocator);
        }
        allocator.free(dependents_a);
    }
    try std.testing.expectEqual(@as(usize, 2), dependents_a.len); // B and C

    // Test: Query dependents using formatted ID
    const parsed_a_formatted = try utils.parseTaskIdFlexible("chain:001");
    try std.testing.expectEqual(task_a, parsed_a_formatted);
    var dependents_a_formatted = try test_storage.getDependents(parsed_a_formatted);
    defer {
        for (dependents_a_formatted) |*dependent| {
            dependent.deinit(allocator);
        }
        allocator.free(dependents_a_formatted);
    }
    try std.testing.expectEqual(@as(usize, 2), dependents_a_formatted.len);
}
