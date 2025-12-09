//! Tests for getSystemStats query operations.
//!
//! Covers: system-wide statistics (task counts, progress).
//!
//! Tiger Style: Each test documents methodology, uses assertions,
//! and cleans up resources properly.

const std = @import("std");
const guerilla_graph = @import("guerilla_graph");
const Storage = guerilla_graph.storage.Storage;

test "getSystemStats: accurate counts with per-plan tasks" {
    // Methodology: Create tasks under multiple plans with various statuses,
    // verify system stats are accurate.
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_get_system_stats.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Create plans
    try storage.createPlan("auth", "Authentication", "", null);
    try storage.createPlan("payments", "Payments", "", null);

    // Create tasks
    _ = try storage.createTask("auth", "Task 1", ""); // open
    const task2 = try storage.createTask("auth", "Task 2", ""); // in_progress
    const task3 = try storage.createTask("auth", "Task 3", ""); // completed
    const task4 = try storage.createTask("payments", "Task 4", ""); // blocked
    const task5 = try storage.createTask("payments", "Task 5", ""); // blocker for task4

    // Set statuses
    try storage.startTask(task2);
    try storage.startTask(task3);
    try storage.completeTask(task3);

    // Add dependency
    try storage.addDependency(task4, task5);

    // Get stats
    const stats = try storage.getSystemStats();

    // Verify counts
    try std.testing.expectEqual(@as(u32, 2), stats.total_plans);
    try std.testing.expectEqual(@as(u32, 5), stats.total_tasks);
    try std.testing.expectEqual(@as(u32, 3), stats.open_tasks); // task1, task4, task5
    try std.testing.expectEqual(@as(u32, 1), stats.in_progress_tasks); // task2
    try std.testing.expectEqual(@as(u32, 1), stats.completed_tasks); // task3
    try std.testing.expectEqual(@as(u32, 2), stats.ready_tasks); // task1, task5
    try std.testing.expectEqual(@as(u32, 1), stats.blocked_tasks); // task4

    // Verify validation passes
    try std.testing.expect(stats.validate());
}

test "getSystemStats: completed plan count" {
    // Methodology: Complete all tasks in a plan, verify completed_plans count increases.
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_get_system_stats_completed_plans.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Create plans
    try storage.createPlan("auth", "Authentication", "", null);
    try storage.createPlan("payments", "Payments", "", null);

    // Create and complete all auth tasks
    const task1 = try storage.createTask("auth", "Task 1", "");
    const task2 = try storage.createTask("auth", "Task 2", "");

    try storage.startTask(task1);
    try storage.completeTask(task1);
    try storage.startTask(task2);
    try storage.completeTask(task2);

    // Create incomplete payments task
    _ = try storage.createTask("payments", "Task 3", "");

    // Get stats
    const stats = try storage.getSystemStats();

    // Auth plan should be completed, payments plan should not
    try std.testing.expectEqual(@as(u32, 2), stats.total_plans);
    try std.testing.expectEqual(@as(u32, 1), stats.completed_plans); // Only auth completed
}
