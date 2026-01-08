//! Task delete command handler for Guerilla Graph CLI.
//!
//! This module contains the handleTaskDelete function for deleting tasks
//! with protection against deleting tasks that have dependents.
//!
//! Tiger Style: Full names, 2+ assertions per function, rationale comments.

const std = @import("std");
const builtin = @import("builtin");
const utils = @import("../utils.zig");
const Storage = @import("../storage.zig").Storage;

/// Error types for command execution.
pub const CommandError = error{
    MissingArgument,
    InvalidArgument,
    TaskNotFound,
};

/// Handles the `task delete` command by deleting a task.
///
/// Deletion is protected: tasks with dependents cannot be deleted (storage layer enforces this).
///
/// Accepts task ID in two formats:
/// - Internal numeric ID: "19"
/// - Plan:Number format: "auth:019"
///
/// Success confirmation displays the formatted ID (e.g., "auth:019").
///
/// Arguments:
/// - io: I/O interface for stdout/stderr access
/// - allocator: Memory allocator for temporary allocations
/// - arguments: CLI arguments (expects task ID as first argument)
/// - json_output: If true, output JSON; otherwise output human-readable text
/// - storage: Storage instance for database operations
///
/// Returns: void on success, error on failure
/// Errors: CommandError.MissingArgument, CommandError.InvalidArgument, CommandError.TaskNotFound,
///         StorageError.TaskHasDependents (propagated from storage layer)
pub fn handleTaskDelete(
    io: std.Io,
    allocator: std.mem.Allocator,
    arguments: []const []const u8,
    json_output: bool,
    storage: *Storage,
) !void {
    // Rationale: User must provide task ID as first positional argument.
    // Command format: gg delete <task-id>
    if (arguments.len == 0) {
        return CommandError.MissingArgument;
    }

    // Parse task ID from CLI argument (accepts both numeric "19" and formatted "auth:019")
    const parsed_input = utils.parseTaskInput(arguments[0]) catch {
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

    // Assertions: Task ID must be positive
    std.debug.assert(task_id > 0);

    // Rationale: Fetch task before deletion to get plan/number for formatted ID display
    var task = try storage.getTask(task_id) orelse {
        return CommandError.TaskNotFound;
    };
    defer task.deinit(allocator);

    const formatted_id = try utils.formatTaskId(allocator, task.plan_slug, task.plan_task_number);
    defer allocator.free(formatted_id);

    // Rationale: deleteTask() checks for dependents and fails if any exist.
    // Propagate errors to caller (main.zig) for user-friendly messaging.
    try storage.deleteTask(task_id);

    // Rationale: After successful deletion, confirm to user with formatted ID.
    if (!builtin.is_test) {
        var stdout_buffer: [8192]u8 = undefined;
        var stdout_writer = std.Io.File.stdout().writer(io, stdout_buffer[0..]);
        const stdout = &stdout_writer.interface;

        if (json_output) {
            try stdout.writeAll("{\n");
            try stdout.writeAll("  \"status\": \"success\",\n");
            try stdout.writeAll("  \"task_id\": ");
            try std.json.Stringify.value(formatted_id, .{}, stdout);
            try stdout.writeAll(",\n");
            try stdout.writeAll("  \"message\": \"Task deleted successfully\"\n");
            try stdout.writeAll("}\n");
        } else {
            try stdout.print("Deleted task {s}\n", .{formatted_id});
        }

        stdout.flush() catch {};
    }
}
