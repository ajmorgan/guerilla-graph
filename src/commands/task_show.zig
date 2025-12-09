//! Task show command handler for Guerilla Graph CLI.
//!
//! This module contains the handleTaskShow command handler that displays
//! full task details including description and dependency tree (blockers/dependents).
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

// ============================================================================
// Show Task Command
// ============================================================================

/// Handle show command (renamed from handleShow)
/// Displays full task details including description and dependency tree.
///
/// Command: gg show <task-id>
/// Example: gg show 1
///
/// Rationale: This command combines getTask (full details) + getBlockers + getDependents
/// to provide a complete view of a task with its dependency context.
pub fn handleTaskShow(
    allocator: std.mem.Allocator,
    arguments: []const []const u8,
    json_output: bool,
    storage: *Storage,
) !void {
    // Rationale: User must provide task ID as first positional argument.
    // Command format: gg show <task-id>
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

    // Rationale: getTask returns null if task doesn't exist, which we handle as an error.
    // The task contains full description field (unlike list queries which exclude it).
    var task = try storage.getTask(task_id) orelse {
        return error.TaskNotFound;
    };
    defer task.deinit(allocator);

    // Rationale: Get transitive blockers and dependents for dependency tree display.
    // These show what the task is waiting on and what's waiting on this task.
    const blockers = try storage.getBlockers(task_id);
    defer {
        for (blockers) |*blocker| {
            blocker.deinit(allocator);
        }
        allocator.free(blockers);
    }

    const dependents = try storage.getDependents(task_id);
    defer {
        for (dependents) |*dependent| {
            dependent.deinit(allocator);
        }
        allocator.free(dependents);
    }

    // Rationale: Fetch plan title for richer display using plan_slug from task
    var plan_summary = try storage.getPlanSummary(task.plan_slug);
    defer if (plan_summary) |*summary| summary.deinit(allocator);

    const plan_title: ?[]const u8 = if (plan_summary) |summary| summary.title else null;

    if (!builtin.is_test) {
        var stdout_buffer: [8192]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(stdout_buffer[0..]);
        const stdout = &stdout_writer.interface;

        // Rationale: Use format module functions to display task with dependencies.
        // format.formatTask displays full description + blocker/dependent trees.
        if (json_output) {
            try format.formatTaskJson(allocator, stdout, task, plan_title, blockers, dependents);
        } else {
            try format.formatTask(allocator, stdout, task, plan_title, blockers, dependents);
        }
        stdout.flush() catch {};
    }
}
