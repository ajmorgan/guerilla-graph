//! Task complete command handler for Guerilla Graph CLI.
//!
//! This module contains the task completion command handler that processes
//! parsed CLI arguments and interacts with Storage to mark tasks as completed.
//!
//! Supports both single task completion and bulk completion for efficiency.
//!
//! Tiger Style: Full names, 2+ assertions per function, rationale comments.

const std = @import("std");
const builtin = @import("builtin");
const types = @import("../types.zig");
const utils = @import("../utils.zig");
const format = @import("../format.zig");
const Storage = @import("../storage.zig").Storage;

/// Error types for command execution.
pub const CommandError = error{
    MissingArgument,
    InvalidArgument,
    TaskNotFound,
};

/// Handle complete command (renamed from handleComplete)
/// Marks one or more tasks as completed by changing their status to 'completed'.
/// Supports both single task completion and bulk completion for efficiency.
///
/// Command: gg complete <task-id> [<task-id2> ...]
/// Example: gg complete 1
/// Example: gg complete 1 2 3
///
/// Rationale: Agents mark tasks complete after finishing work. Bulk completion
/// is more efficient when multiple tasks finish together (uses single SQL UPDATE).
pub fn handleTaskComplete(
    allocator: std.mem.Allocator,
    arguments: []const []const u8,
    json_output: bool,
    storage: *Storage,
) !void {
    // Rationale: User must provide at least one task ID as positional argument.
    // Command format: gg complete <task-id1> [<task-id2> ...]
    if (arguments.len == 0) {
        return CommandError.MissingArgument;
    }

    // Rationale: Parse all task IDs upfront and store in array for bulk operations.
    // This validates all arguments before making any database changes.
    var task_ids_buffer: [types.MAX_BULK_TASK_IDS]u32 = undefined;
    if (arguments.len > task_ids_buffer.len) {
        return CommandError.InvalidArgument; // Too many task IDs
    }

    for (arguments, 0..) |task_id_str, index| {
        const parsed_input = utils.parseTaskInput(task_id_str) catch {
            return CommandError.InvalidArgument;
        };

        const task_id = switch (parsed_input) {
            .internal_id => |id| id,
            .plan_task => |pt| blk: {
                // Resolve plan:number to internal ID
                const resolved_id = try storage.tasks.getTaskByPlanAndNumber(pt.slug, pt.number);
                if (resolved_id == null) {
                    return CommandError.TaskNotFound;
                }
                break :blk resolved_id.?;
            },
        };

        if (task_id == 0) {
            return CommandError.InvalidArgument;
        }
        task_ids_buffer[index] = task_id;
    }
    const task_ids = task_ids_buffer[0..arguments.len];

    // Assertions: All task IDs are valid
    std.debug.assert(task_ids.len > 0);
    std.debug.assert(task_ids.len == arguments.len);

    // Rationale: Use bulk completion if multiple tasks, single completion if one task.
    // Bulk completion is more efficient (single SQL UPDATE vs multiple).
    if (task_ids.len == 1) {
        try storage.completeTask(task_ids[0]);
    } else {
        try storage.completeTasksBulk(task_ids);
    }

    // Rationale: After successful completion, retrieve all completed tasks for display.
    // This provides user feedback confirming the status changes.
    var completed_tasks: std.ArrayList(types.Task) = .empty;
    defer {
        for (completed_tasks.items) |*task| {
            task.deinit(allocator);
        }
        completed_tasks.deinit(allocator);
    }

    for (task_ids) |task_id| {
        const task = try storage.getTask(task_id) orelse {
            return CommandError.TaskNotFound;
        };
        try completed_tasks.append(allocator, task);
    }

    // Assertions: Retrieved all tasks successfully
    std.debug.assert(completed_tasks.items.len == task_ids.len);
    // Postcondition: All completed tasks should have completed status
    for (completed_tasks.items) |task| {
        std.debug.assert(task.status == .completed);
    }

    if (!builtin.is_test) {
        var stdout_buffer: [8192]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(stdout_buffer[0..]);
        const stdout = &stdout_writer.interface;

        if (json_output) {
            // Rationale: JSON output uses standard formatTaskListJson for consistency.
            // Callers can parse status field to confirm tasks are now 'completed'.
            try format.formatTaskListJson(allocator, stdout, completed_tasks.items);
        } else {
            // Rationale: Text output shows brief confirmation with task count and list using formatted IDs.
            // User sees how many tasks were completed and their details.
            if (task_ids.len == 1) {
                const formatted_id = try utils.formatTaskId(allocator, completed_tasks.items[0].plan_slug, completed_tasks.items[0].plan_task_number);
                defer allocator.free(formatted_id);
                try stdout.print("Completed task {s}: {s}\n", .{ formatted_id, completed_tasks.items[0].title });
                try stdout.print("Status: {s}\n", .{completed_tasks.items[0].status.toString()});
            } else {
                try stdout.print("Completed {d} tasks:\n", .{task_ids.len});
                try format.formatTaskList(allocator, stdout, completed_tasks.items, true);
            }
        }

        stdout.flush() catch {};
    }
}
