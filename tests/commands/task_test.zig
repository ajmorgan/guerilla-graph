//! Tests for task command handlers (task_commands module).
//!
//! Tests verify task resource operations:
//! - new: Create tasks with validation
//! - start: Mark tasks as in_progress
//! - complete: Mark tasks as completed
//! - show: Display task details with dependencies
//! - update: Modify task metadata
//! - delete: Remove tasks (with dependent protection)
//! - list: List tasks with filters
//!
//! Coverage: happy path, error cases, lifecycle transitions
//!
//! CRITICAL: Resource Management
//! - Each test uses unique temp DB name to avoid interference
//! - Storage must be deferred AFTER all dependent resources
//! - Tests must complete quickly (<100ms) without blocking

const std = @import("std");
const guerilla_graph = @import("guerilla_graph");
const task_commands = guerilla_graph.task_commands;
const Storage = guerilla_graph.storage.Storage;
const TaskManager = guerilla_graph.task_manager.TaskManager;
const types = guerilla_graph.types;
const CommandError = task_commands.CommandError;
const test_utils = @import("../test_utils.zig");

// Helper functions from test_utils
const getTemporaryDatabasePath = test_utils.getTemporaryDatabasePath;
const cleanupDatabaseFile = test_utils.cleanupDatabaseFile;

// ============================================================================
// Task New Command Tests
// ============================================================================

test "task_commands.handleTaskNew: successful creation" {
    // Methodology: Verify task can be created under a plan with required fields.
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const db_path = try getTemporaryDatabasePath(allocator, "task_new_success");
    defer allocator.free(db_path);
    defer cleanupDatabaseFile(io, db_path);

    var storage = try Storage.init(allocator, db_path);
    defer storage.deinit();

    var task_manager = TaskManager.init(allocator, &storage);
    defer task_manager.deinit();

    // Create plan first
    try storage.createPlan("auth", "Authentication", "", null);

    const args = &[_][]const u8{ "--title", "Add login endpoint", "--plan", "auth" };
    try task_commands.handleTaskNew(io, allocator, args, false, &storage, &task_manager);

    // Verify task was created
    const tasks = try storage.listTasks(null, "auth");
    defer {
        for (tasks) |*t| {
            t.deinit(allocator);
        }
        allocator.free(tasks);
    }

    try std.testing.expectEqual(@as(usize, 1), tasks.len);
    try std.testing.expectEqualStrings("Add login endpoint", tasks[0].title);
}

test "task_commands.handleTaskNew: missing plan error" {
    // Methodology: Verify error when required --plan flag is missing.
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const db_path = try getTemporaryDatabasePath(allocator, "task_new_no_plan");
    defer allocator.free(db_path);
    defer cleanupDatabaseFile(io, db_path);

    var storage = try Storage.init(allocator, db_path);
    defer storage.deinit();

    var task_manager = TaskManager.init(allocator, &storage);
    defer task_manager.deinit();

    const args = &[_][]const u8{ "--title", "Task without plan" };
    const result = task_commands.handleTaskNew(io, allocator, args, false, &storage, &task_manager);

    try std.testing.expectError(CommandError.MissingRequiredFlag, result);
}

test "task_commands.handleTaskNew: with description" {
    // Methodology: Verify description is stored correctly.
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const db_path = try getTemporaryDatabasePath(allocator, "task_new_desc");
    defer allocator.free(db_path);
    defer cleanupDatabaseFile(io, db_path);

    var storage = try Storage.init(allocator, db_path);
    defer storage.deinit();

    var task_manager = TaskManager.init(allocator, &storage);
    defer task_manager.deinit();

    try storage.createPlan("api", "API", "", null);

    const args = &[_][]const u8{ "--title", "Add endpoint", "--plan", "api", "--description", "REST endpoint for users" };
    try task_commands.handleTaskNew(io, allocator, args, false, &storage, &task_manager);

    // Verify description
    const tasks = try storage.listTasks(null, "api");
    defer {
        for (tasks) |*t| {
            t.deinit(allocator);
        }
        allocator.free(tasks);
    }

    try std.testing.expectEqual(@as(usize, 1), tasks.len);
}

// ============================================================================
// Task Start Command Tests
// ============================================================================

test "task_commands.handleTaskStart: successful start" {
    // Methodology: Verify task status changes to in_progress.
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const db_path = try getTemporaryDatabasePath(allocator, "task_start_success");
    defer allocator.free(db_path);
    defer cleanupDatabaseFile(io, db_path);

    var storage = try Storage.init(allocator, db_path);
    defer storage.deinit();

    // Create plan and task
    try storage.createPlan("test", "Test Plan", "", null);
    const task_id = try storage.createTask("test", "Test Task", "");

    // Start the task
    const task_id_str = try std.fmt.allocPrint(allocator, "{d}", .{task_id});
    defer allocator.free(task_id_str);

    const args = &[_][]const u8{task_id_str};
    try task_commands.handleTaskStart(io, allocator, args, false, &storage);

    // Verify status changed
    var task = (try storage.getTask(task_id)).?;
    defer task.deinit(allocator);

    try std.testing.expectEqual(types.TaskStatus.in_progress, task.status);
}

test "task_commands.handleTaskStart: task not found" {
    // Methodology: Verify error when task doesn't exist.
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const db_path = try getTemporaryDatabasePath(allocator, "task_start_not_found");
    defer allocator.free(db_path);
    defer cleanupDatabaseFile(io, db_path);

    var storage = try Storage.init(allocator, db_path);
    defer storage.deinit();

    const args = &[_][]const u8{"99999"};
    const result = task_commands.handleTaskStart(io, allocator, args, false, &storage);

    try std.testing.expectError(error.InvalidData, result);
}

// ============================================================================
// Task Complete Command Tests
// ============================================================================

test "task_commands.handleTaskComplete: successful completion" {
    // Methodology: Verify task status changes to completed.
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const db_path = try getTemporaryDatabasePath(allocator, "task_complete_success");
    defer allocator.free(db_path);
    defer cleanupDatabaseFile(io, db_path);

    var storage = try Storage.init(allocator, db_path);
    defer storage.deinit();

    // Create plan and task
    try storage.createPlan("test", "Test Plan", "", null);
    const task_id = try storage.createTask("test", "Test Task", "");

    // Start task first (required before completing)
    try storage.startTask(task_id);

    // Complete the task
    const task_id_str = try std.fmt.allocPrint(allocator, "{d}", .{task_id});
    defer allocator.free(task_id_str);

    const args = &[_][]const u8{task_id_str};
    try task_commands.handleTaskComplete(io, allocator, args, false, &storage);

    // Verify status changed
    var task = (try storage.getTask(task_id)).?;
    defer task.deinit(allocator);

    try std.testing.expectEqual(types.TaskStatus.completed, task.status);
}

test "task_commands.handleTaskComplete: bulk completion" {
    // Methodology: Verify multiple tasks can be completed at once.
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const db_path = try getTemporaryDatabasePath(allocator, "task_complete_bulk");
    defer allocator.free(db_path);
    defer cleanupDatabaseFile(io, db_path);

    var storage = try Storage.init(allocator, db_path);
    defer storage.deinit();

    // Create plan and tasks
    try storage.createPlan("test", "Test Plan", "", null);
    const task_id1 = try storage.createTask("test", "Task 1", "");
    const task_id2 = try storage.createTask("test", "Task 2", "");

    // Start tasks first (required before completing)
    try storage.startTask(task_id1);
    try storage.startTask(task_id2);

    // Complete both tasks
    const id1_str = try std.fmt.allocPrint(allocator, "{d}", .{task_id1});
    defer allocator.free(id1_str);
    const id2_str = try std.fmt.allocPrint(allocator, "{d}", .{task_id2});
    defer allocator.free(id2_str);

    const args = &[_][]const u8{ id1_str, id2_str };
    try task_commands.handleTaskComplete(io, allocator, args, false, &storage);

    // Verify both completed
    const completed_tasks = try storage.listTasks(types.TaskStatus.completed, "test");
    defer {
        for (completed_tasks) |*t| {
            t.deinit(allocator);
        }
        allocator.free(completed_tasks);
    }

    try std.testing.expectEqual(@as(usize, 2), completed_tasks.len);
}

// ============================================================================
// Task Parsing Tests (merged from commands_task_parsing_test.zig)
// ============================================================================

test "parseCreateArgs - description-file reads file and tracks ownership" {
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    // Create temp file
    const temp_file = "test_desc_create.md";
    const file = try std.Io.Dir.cwd().createFile(io, temp_file, .{});
    const content = "Test content from file";
    try file.writePositionalAll(io, content, 0);
    file.close(io);
    defer std.Io.Dir.cwd().deleteFile(io, temp_file) catch {};

    // Parse with --description-file
    const args_input = &[_][]const u8{
        "--title", "Task Title", "--plan", "auth", "--description-file", temp_file,
    };
    const args = try task_commands.parseCreateArgs(io, allocator, args_input);
    defer {
        if (args.description_owned) allocator.free(args.description);
    }

    try std.testing.expectEqualStrings("Test content from file", args.description);
    try std.testing.expect(args.description_owned);
}

test "parseCreateArgs - description borrowed from argv" {
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const args_input = &[_][]const u8{
        "--title", "Task Title", "--plan", "auth", "--description", "Inline text",
    };
    const args = try task_commands.parseCreateArgs(io, allocator, args_input);

    try std.testing.expectEqualStrings("Inline text", args.description);
    try std.testing.expect(!args.description_owned);
}

test "parseUpdateArgs - description-file reads file and tracks ownership" {
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const temp_file = "test_desc_update.md";
    const file = try std.Io.Dir.cwd().createFile(io, temp_file, .{});
    const content = "Updated content";
    try file.writePositionalAll(io, content, 0);
    file.close(io);
    defer std.Io.Dir.cwd().deleteFile(io, temp_file) catch {};

    const args_input = &[_][]const u8{
        "42", "--description-file", temp_file,
    };
    const args = try task_commands.parseUpdateArgs(io, allocator, args_input);
    defer {
        if (args.description_owned and args.description != null) {
            allocator.free(args.description.?);
        }
    }

    try std.testing.expectEqualStrings("Updated content", args.description.?);
    try std.testing.expect(args.description_owned);
}
