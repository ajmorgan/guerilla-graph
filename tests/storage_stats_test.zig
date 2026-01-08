//! Tests for SQLite storage layer statistics (getSystemStats).
//!
//! Covers: System statistics queries, label/task counting, ready/blocked task detection.

const std = @import("std");
const guerilla_graph = @import("guerilla_graph");
const Storage = guerilla_graph.storage.Storage;

test "getSystemStats: comprehensive statistics" {
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const temp_path = "/tmp/test_get_system_stats.db";
    std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    // Create two labels
    try storage.createPlan("auth", "Authentication", "Auth system", null);
    try storage.createPlan("payments", "Payments", "Payment processing", null);

    // Create tasks in auth label
    const auth_task1: u32 = try storage.createTask("auth", "Login", "Add login");
    const auth_task2: u32 = try storage.createTask("auth", "Logout", "Add logout");
    _ = try storage.createTask("auth", "Session", "Add session");

    // Create tasks in payments label
    const pay_task1: u32 = try storage.createTask("payments", "Stripe", "Integrate Stripe");
    const pay_task2: u32 = try storage.createTask("payments", "Checkout", "Add checkout");

    // Set various statuses
    try storage.startTask(auth_task1); // in_progress
    try storage.startTask(auth_task2);
    try storage.completeTask(auth_task2); // completed
    // auth_task3 remains open
    try storage.startTask(pay_task1);
    try storage.completeTask(pay_task1); // completed
    // pay_task2 remains open

    // Add dependency: pay_task2 blocks on pay_task1 (completed, so pay_task2 is ready)
    try storage.addDependency(pay_task2, pay_task1);

    // Get statistics
    const stats = try storage.getSystemStats();

    // Assertions: Verify all counts
    try std.testing.expectEqual(@as(u32, 2), stats.total_plans); // auth, payments
    try std.testing.expectEqual(@as(u32, 0), stats.completed_plans); // None fully completed
    try std.testing.expectEqual(@as(u32, 5), stats.total_tasks);
    try std.testing.expectEqual(@as(u32, 2), stats.open_tasks); // auth_task3, pay_task2
    try std.testing.expectEqual(@as(u32, 1), stats.in_progress_tasks); // auth_task1
    try std.testing.expectEqual(@as(u32, 2), stats.completed_tasks); // auth_task2, pay_task1
    try std.testing.expectEqual(@as(u32, 2), stats.ready_tasks); // auth_task3, pay_task2 (unblocked)
    try std.testing.expectEqual(@as(u32, 0), stats.blocked_tasks); // None blocked

    // Verify stats validation passes
    try std.testing.expect(stats.validate());
}

test "getSystemStats: empty database" {
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const temp_path = "/tmp/test_get_system_stats_empty.db";
    std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    // Get statistics from empty database
    const stats = try storage.getSystemStats();

    // Assertions: Empty database has no labels
    try std.testing.expectEqual(@as(u32, 0), stats.total_plans);
    try std.testing.expectEqual(@as(u32, 0), stats.completed_plans);
    try std.testing.expectEqual(@as(u32, 0), stats.total_tasks);
    try std.testing.expectEqual(@as(u32, 0), stats.open_tasks);
    try std.testing.expectEqual(@as(u32, 0), stats.in_progress_tasks);
    try std.testing.expectEqual(@as(u32, 0), stats.completed_tasks);
    try std.testing.expectEqual(@as(u32, 0), stats.ready_tasks);
    try std.testing.expectEqual(@as(u32, 0), stats.blocked_tasks);

    // Verify stats validation passes
    try std.testing.expect(stats.validate());
}

test "getSystemStats: blocked tasks count" {
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const temp_path = "/tmp/test_get_system_stats_blocked.db";
    std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    try storage.createPlan("test", "Test", "Test label", null);

    // Create three tasks: A blocks on B, B is open
    const task_a: u32 = try storage.createTask("test", "Task A", "First");
    const task_b: u32 = try storage.createTask("test", "Task B", "Second");
    _ = try storage.createTask("test", "Task C", "Third");

    // Add dependency: task_a blocks on task_b (task_b is open, so task_a is blocked)
    try storage.addDependency(task_a, task_b);

    // Get statistics
    const stats = try storage.getSystemStats();

    // Assertions: Verify blocked/ready counts
    try std.testing.expectEqual(@as(u32, 3), stats.total_tasks);
    try std.testing.expectEqual(@as(u32, 3), stats.open_tasks);
    try std.testing.expectEqual(@as(u32, 2), stats.ready_tasks); // task_b, task_c (unblocked)
    try std.testing.expectEqual(@as(u32, 1), stats.blocked_tasks); // task_a (blocked by task_b)

    // Verify stats validation passes
    try std.testing.expect(stats.validate());
}
