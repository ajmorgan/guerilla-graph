//! Task list command handler for Guerilla Graph CLI.
//! Lists all tasks with optional status and plan filters.
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
};

/// Parsed arguments for list command
const ListArgs = struct {
    status_filter: ?types.TaskStatus,
    plan_filter: ?[]const u8,
};

/// Parse list command arguments
/// Command format: gg list [--status <status>] [--plan <id>]
pub fn parseListArgs(arguments: []const []const u8) !ListArgs {
    var status_filter: ?types.TaskStatus = null;
    var plan_filter: ?[]const u8 = null;
    var index: usize = 0;

    // Rationale: Iterate through flags - each followed by its value
    while (index < arguments.len) {
        const argument = arguments[index];

        if (std.mem.eql(u8, argument, "--status")) {
            // Rationale: --status flag must be followed by a value
            if (index + 1 >= arguments.len) {
                return CommandError.MissingArgument;
            }
            const status_string = arguments[index + 1];
            status_filter = try types.TaskStatus.fromString(status_string);
            index += 2;
        } else if (std.mem.eql(u8, argument, "--plan")) {
            // Rationale: --plan flag must be followed by a value
            if (index + 1 >= arguments.len) {
                return CommandError.MissingArgument;
            }
            plan_filter = arguments[index + 1];
            index += 2;
        } else {
            // Unknown flag or extra argument
            return CommandError.InvalidArgument;
        }
    }

    // Assertions: Postconditions
    if (plan_filter) |plan| {
        std.debug.assert(plan.len > 0);
    }

    return ListArgs{
        .status_filter = status_filter,
        .plan_filter = plan_filter,
    };
}

/// Handle list command - lists tasks with optional status and plan filters.
/// Command: gg list [--status <status>] [--plan <id>]
/// Rationale: Provides filtered view of all tasks (unlike `gg ready` which shows
/// only unblocked tasks). Excludes descriptions for performance.
pub fn handleTaskList(
    io: std.Io,
    allocator: std.mem.Allocator,
    arguments: []const []const u8,
    json_output: bool,
    storage: *Storage,
) !void {
    const args = try parseListArgs(arguments);
    if (args.plan_filter) |plan| {
        try utils.validateKebabCase(plan); // Rationale: Validate kebab-case format
        std.debug.assert(plan.len > 0);
    }

    // Rationale: List tasks sorted by creation time, descriptions excluded for performance
    const tasks = try storage.*.listTasks(args.status_filter, args.plan_filter);
    defer {
        for (tasks) |*task| {
            task.deinit(allocator);
        }
        allocator.free(tasks);
    }

    // Rationale: Format output (show_plan=true for cross-plan context)
    if (!builtin.is_test) {
        var stdout_buffer: [8192]u8 = undefined;
        var stdout_writer = std.Io.File.stdout().writer(io, stdout_buffer[0..]);
        const stdout = &stdout_writer.interface;
        if (json_output) {
            try format.formatTaskListJson(allocator, stdout, tasks);
        } else {
            try format.formatTaskList(allocator, stdout, tasks, true);
        }
        stdout.flush() catch {};
    }
}
