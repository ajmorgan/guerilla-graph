//! Dependency command handlers for Guerilla Graph CLI.
//!
//! This module contains all dependency-related command handler implementations
//! that process parsed CLI arguments and interact with Storage to manage
//! task dependencies.
//!
//! Each command handler follows the pattern:
//! 1. Parse and validate arguments
//! 2. Call Storage operation
//! 3. Format output (text or JSON)
//!
//! Tiger Style: Full names, 2+ assertions per function, rationale comments.

const std = @import("std");
const builtin = @import("builtin");
const types = @import("../types.zig");
const utils = @import("../utils.zig");
const format = @import("../format.zig");
const Storage = @import("../storage.zig").Storage;

/// Error types for dependency command execution.
pub const DepCommandError = error{
    /// A required positional argument was not provided.
    MissingArgument,

    /// An argument value is invalid or malformed.
    InvalidArgument,

    /// A required flag (--flag) was not provided.
    MissingRequiredFlag,
};

// ============================================================================
// Add Dependency Command
// ============================================================================

/// Parsed arguments for dep-add command
const DepAddArgs = struct {
    task_id: u32,
    blocks_on_id: u32,
};

/// Parse dep-add command arguments
/// Command format: gg dep-add <task-id> --blocks-on <blocks-on-id>
pub fn parseDepAddArgs(io: std.Io, arguments: []const []const u8, storage: *Storage) !DepAddArgs {
    // Rationale: First argument is the task ID (positional argument).
    // User provides this directly without a flag (e.g., "123").
    if (arguments.len == 0) {
        return DepCommandError.MissingArgument;
    }

    // Parse task ID from CLI argument (supports both numeric "19" and formatted "auth:019")
    // Rationale: parseTaskInput returns a union of either internal_id or plan_task format.
    // For backwards compatibility, internal_id is used directly.
    // For plan_task format, we resolve the slug:number to the internal AUTOINCREMENT ID.
    const parsed_task_id = utils.parseTaskInput(arguments[0]) catch {
        return DepCommandError.InvalidArgument;
    };
    const task_id = switch (parsed_task_id) {
        .internal_id => |id| id,
        .plan_task => |pt| blk: {
            const resolved_task = try storage.tasks.getTaskByPlanAndNumber(pt.slug, pt.number);
            if (resolved_task == null) {
                var stderr_buffer: [256]u8 = undefined;
                var stderr_writer = std.Io.File.stderr().writer(io, stderr_buffer[0..]);
                stderr_writer.interface.print("Error: Task {s}:{d} not found\n", .{ pt.slug, pt.number }) catch {};
                return DepCommandError.InvalidArgument;
            }
            break :blk resolved_task.?;
        },
    };

    // Parse --blocks-on flag
    var blocks_on_id: ?u32 = null;
    var index: usize = 1;

    // Rationale: Iterate through remaining arguments to find --blocks-on flag.
    while (index < arguments.len) {
        const argument = arguments[index];

        if (std.mem.eql(u8, argument, "--blocks-on")) {
            // Rationale: --blocks-on flag must be followed by a value
            if (index + 1 >= arguments.len) {
                return DepCommandError.MissingArgument;
            }
            // Parse blocks_on_id from CLI argument (supports both numeric "19" and formatted "auth:019")
            const parsed_blocks_on = utils.parseTaskInput(arguments[index + 1]) catch {
                return DepCommandError.InvalidArgument;
            };
            blocks_on_id = switch (parsed_blocks_on) {
                .internal_id => |id| id,
                .plan_task => |pt| blk: {
                    const resolved_task = try storage.tasks.getTaskByPlanAndNumber(pt.slug, pt.number);
                    if (resolved_task == null) {
                        var stderr_buffer: [256]u8 = undefined;
                        var stderr_writer = std.Io.File.stderr().writer(io, stderr_buffer[0..]);
                        stderr_writer.interface.print("Error: Task {s}:{d} not found\n", .{ pt.slug, pt.number }) catch {};
                        return DepCommandError.InvalidArgument;
                    }
                    break :blk resolved_task.?;
                },
            };
            index += 2;
        } else {
            // Unknown flag or extra argument
            return DepCommandError.InvalidArgument;
        }
    }

    // Rationale: --blocks-on is required, user must provide it explicitly
    if (blocks_on_id == null) {
        return DepCommandError.MissingRequiredFlag;
    }

    // Assertions: Postconditions - both IDs must be positive
    std.debug.assert(task_id > 0);
    std.debug.assert(blocks_on_id.? > 0);

    return DepAddArgs{
        .task_id = task_id,
        .blocks_on_id = blocks_on_id.?,
    };
}

/// Handle dep-add command (formerly add-dep)
/// Creates a dependency between two tasks: task_id blocks on blocks_on_id.
///
/// Command: gg dep-add <task-id> --blocks-on <blocks-on-id>
/// Example: gg dep-add 3 --blocks-on 1
/// Example: gg dep-add 3 --blocks-on 2  # Task 3 waits for both task 1 and task 2
///
/// Rationale: This command establishes that task_id cannot start until blocks_on_id
/// is completed. The storage layer validates both tasks exist and checks for cycles
/// before inserting the dependency. If a cycle would be created, the command fails
/// with a clear error message showing the cycle path.
pub fn handleDepAdd(
    io: std.Io,
    allocator: std.mem.Allocator,
    arguments: []const []const u8,
    json_output: bool,
    storage: *Storage,
) !void {
    // Parse command arguments
    const args = try parseDepAddArgs(io, arguments, storage);

    // Assertions: Postcondition - both IDs are valid
    std.debug.assert(args.task_id > 0);
    std.debug.assert(args.blocks_on_id > 0);

    // Rationale: addDependency() validates both tasks exist, checks for cycles,
    // and inserts the dependency atomically within a transaction.
    // Rationale: Propagate errors to caller (main.zig handles user-friendly messaging).
    try storage.addDependency(args.task_id, args.blocks_on_id);

    // Rationale: Display success message confirming the dependency was added.
    // Use consistent formatting with other commands.
    if (!builtin.is_test) {
        var stdout_buffer: [8192]u8 = undefined;
        var stdout_writer = std.Io.File.stdout().writer(io, stdout_buffer[0..]);
        const stdout = &stdout_writer.interface;

        if (json_output) {
            try stdout.writeAll("{\n");
            try stdout.writeAll("  \"status\": \"success\",\n");
            try stdout.writeAll("  \"message\": \"Dependency added successfully\",\n");
            try stdout.print("  \"task_id\": {d},\n", .{args.task_id});
            try stdout.print("  \"blocks_on_id\": {d}\n", .{args.blocks_on_id});
            try stdout.writeAll("}\n");
        } else {
            try stdout.print("Added dependency: task {d} blocks on task {d}\n", .{
                args.task_id,
                args.blocks_on_id,
            });
        }

        stdout.flush() catch {};
    }

    _ = allocator;
}

// ============================================================================
// Remove Dependency Command
// ============================================================================

/// Parsed arguments for dep-remove command
const DepRemoveArgs = struct {
    task_id: u32,
    blocks_on_id: u32,
};

/// Parse dep-remove command arguments
/// Command format: gg dep-remove <task-id> --blocks-on <blocks-on-id>
pub fn parseDepRemoveArgs(io: std.Io, arguments: []const []const u8, storage: *Storage) !DepRemoveArgs {
    // Rationale: First argument is the task ID (positional argument).
    // User provides this directly without a flag (e.g., "123").
    if (arguments.len == 0) {
        return DepCommandError.MissingArgument;
    }

    // Parse task ID from CLI argument (supports both numeric "19" and formatted "auth:019")
    // Rationale: parseTaskInput returns a union of either internal_id or plan_task format.
    // For backwards compatibility, internal_id is used directly.
    // For plan_task format, we resolve the slug:number to the internal AUTOINCREMENT ID.
    const parsed_task_id = utils.parseTaskInput(arguments[0]) catch {
        return DepCommandError.InvalidArgument;
    };
    const task_id = switch (parsed_task_id) {
        .internal_id => |id| id,
        .plan_task => |pt| blk: {
            const resolved_task = try storage.tasks.getTaskByPlanAndNumber(pt.slug, pt.number);
            if (resolved_task == null) {
                var stderr_buffer: [256]u8 = undefined;
                var stderr_writer = std.Io.File.stderr().writer(io, stderr_buffer[0..]);
                stderr_writer.interface.print("Error: Task {s}:{d} not found\n", .{ pt.slug, pt.number }) catch {};
                return DepCommandError.InvalidArgument;
            }
            break :blk resolved_task.?;
        },
    };

    // Parse --blocks-on flag
    var blocks_on_id: ?u32 = null;
    var index: usize = 1;

    // Rationale: Iterate through remaining arguments to find --blocks-on flag.
    while (index < arguments.len) {
        const argument = arguments[index];

        if (std.mem.eql(u8, argument, "--blocks-on")) {
            // Rationale: --blocks-on flag must be followed by a value
            if (index + 1 >= arguments.len) {
                return DepCommandError.MissingArgument;
            }
            // Parse blocks_on_id from CLI argument (supports both numeric "19" and formatted "auth:019")
            const parsed_blocks_on = utils.parseTaskInput(arguments[index + 1]) catch {
                return DepCommandError.InvalidArgument;
            };
            blocks_on_id = switch (parsed_blocks_on) {
                .internal_id => |id| id,
                .plan_task => |pt| blk: {
                    const resolved_task = try storage.tasks.getTaskByPlanAndNumber(pt.slug, pt.number);
                    if (resolved_task == null) {
                        var stderr_buffer: [256]u8 = undefined;
                        var stderr_writer = std.Io.File.stderr().writer(io, stderr_buffer[0..]);
                        stderr_writer.interface.print("Error: Task {s}:{d} not found\n", .{ pt.slug, pt.number }) catch {};
                        return DepCommandError.InvalidArgument;
                    }
                    break :blk resolved_task.?;
                },
            };
            index += 2;
        } else {
            // Unknown flag or extra argument
            return DepCommandError.InvalidArgument;
        }
    }

    // Rationale: --blocks-on is required, user must provide it explicitly
    if (blocks_on_id == null) {
        return DepCommandError.MissingRequiredFlag;
    }

    // Assertions: Postconditions - both IDs must be positive
    std.debug.assert(task_id > 0);
    std.debug.assert(blocks_on_id.? > 0);

    return DepRemoveArgs{
        .task_id = task_id,
        .blocks_on_id = blocks_on_id.?,
    };
}

/// Handle dep-remove command (formerly remove-dep)
/// Removes a dependency between two tasks: task_id no longer blocks on blocks_on_id.
///
/// Command: gg dep-remove <task-id> --blocks-on <blocks-on-id>
/// Example: gg dep-remove 3 --blocks-on 1
///
/// Rationale: This command removes an existing dependency relationship between tasks.
/// The storage layer validates both tasks exist and checks that the dependency exists
/// before attempting deletion. If the dependency doesn't exist, the command fails
/// with a clear error message.
pub fn handleDepRemove(
    io: std.Io,
    allocator: std.mem.Allocator,
    arguments: []const []const u8,
    json_output: bool,
    storage: *Storage,
) !void {
    // Parse command arguments
    const args = try parseDepRemoveArgs(io, arguments, storage);

    // Assertions: Postcondition - both IDs are valid
    std.debug.assert(args.task_id > 0);
    std.debug.assert(args.blocks_on_id > 0);

    // Rationale: removeDependency() validates dependency exists and deletes it atomically
    // within a transaction. Propagate errors to caller for user-friendly messaging.
    try storage.removeDependency(args.task_id, args.blocks_on_id);

    // Rationale: Display success message confirming the dependency was removed.
    // Use consistent formatting with other commands.
    if (!builtin.is_test) {
        var stdout_buffer: [8192]u8 = undefined;
        var stdout_writer = std.Io.File.stdout().writer(io, stdout_buffer[0..]);
        const stdout = &stdout_writer.interface;

        if (json_output) {
            try stdout.writeAll("{\n");
            try stdout.writeAll("  \"status\": \"success\",\n");
            try stdout.writeAll("  \"message\": \"Dependency removed successfully\",\n");
            try stdout.print("  \"task_id\": {d},\n", .{args.task_id});
            try stdout.print("  \"blocks_on_id\": {d}\n", .{args.blocks_on_id});
            try stdout.writeAll("}\n");
        } else {
            try stdout.print("Removed dependency: task {d} no longer blocks on task {d}\n", .{
                args.task_id,
                args.blocks_on_id,
            });
        }

        stdout.flush() catch {};
    }

    _ = allocator;
}

// ============================================================================
// Blockers Command (Dependency Tree Query)
// ============================================================================

/// Handle dep-blockers command (formerly blockers)
/// Shows transitive dependency tree - what tasks block this task from starting.
///
/// Command: gg dep-blockers <task-id>
/// Example: gg dep-blockers 3
///
/// Rationale: This command uses getBlockers() from storage to retrieve the full
/// transitive dependency chain. Each blocker is displayed with its depth (how many
/// hops away) and status. This helps users understand what needs to be completed
/// before they can start working on a task. See PLAN.md Section 7.3.
pub fn handleDepBlockers(
    io: std.Io,
    allocator: std.mem.Allocator,
    arguments: []const []const u8,
    json_output: bool,
    storage: *Storage,
) !void {
    // Rationale: User must provide task ID as first positional argument.
    // Command format: gg dep-blockers <task-id>
    if (arguments.len == 0) {
        return DepCommandError.MissingArgument;
    }

    // Assertion: After check, we know arguments exist
    std.debug.assert(arguments.len >= 1);

    // Parse task ID from CLI argument (supports both numeric "19" and formatted "auth:019")
    // Rationale: parseTaskInput returns a union of either internal_id or plan_task format.
    // For backwards compatibility, internal_id is used directly.
    // For plan_task format, we resolve the slug:number to the internal AUTOINCREMENT ID.
    const parsed_task_id = utils.parseTaskInput(arguments[0]) catch {
        return DepCommandError.InvalidArgument;
    };
    const task_id = switch (parsed_task_id) {
        .internal_id => |id| id,
        .plan_task => |pt| blk: {
            const resolved_task = try storage.tasks.getTaskByPlanAndNumber(pt.slug, pt.number);
            if (resolved_task == null) {
                var stderr_buffer: [256]u8 = undefined;
                var stderr_writer = std.Io.File.stderr().writer(io, stderr_buffer[0..]);
                stderr_writer.interface.print("Error: Task {s}:{d} not found\n", .{ pt.slug, pt.number }) catch {};
                return DepCommandError.InvalidArgument;
            }
            break :blk resolved_task.?;
        },
    };

    // Assertions: Task ID must be positive
    std.debug.assert(task_id > 0);

    // Rationale: getBlockers() returns transitive dependency chain with depth information.
    // Empty result means task has no blockers and is ready to work on.
    const blockers = try storage.getBlockers(task_id);
    defer {
        for (blockers) |*blocker| {
            blocker.deinit(allocator);
        }
        allocator.free(blockers);
    }

    // Rationale: Use format module to display blockers with tree structure.
    // formatBlockerInfo uses depth for indentation and shows status indicators.
    if (!builtin.is_test) {
        var stdout_buffer: [8192]u8 = undefined;
        var stdout_writer = std.Io.File.stdout().writer(io, stdout_buffer[0..]);
        const stdout = &stdout_writer.interface;

        if (json_output) {
            // Rationale: JSON output includes structured blocker data with depth field.
            // This allows programmatic parsing of the dependency tree.
            try format.formatBlockerInfoJson(stdout, blockers, true);
        } else {
            // Rationale: Human-readable output with tree formatting.
            // Shows depth indicators (e.g., "[depth 1]", "[depth 2]") and status.
            try stdout.print("Blockers for {d}:\n", .{task_id});
            try format.formatBlockerInfo(stdout, blockers, true);
        }

        stdout.flush() catch {};
    }
}

// ============================================================================
// Dependents Command
// ============================================================================

/// Handle dep-dependents command (formerly dependents)
/// Displays transitive dependent tree showing what tasks depend on the given task.
///
/// Command: gg dep-dependents <task-id>
/// Example: gg dep-dependents 1
///
/// Rationale: Shows the full transitive dependent chain (what depends on this task).
/// This helps users understand the impact of changes to a task and what might be
/// unblocked when this task completes. See PLAN.md Section 7.3 for command specification.
pub fn handleDepDependents(
    io: std.Io,
    allocator: std.mem.Allocator,
    arguments: []const []const u8,
    json_output: bool,
    storage: *Storage,
) !void {
    // Rationale: User must provide task ID as first positional argument.
    // Command format: gg dep-dependents <task-id>
    if (arguments.len == 0) {
        return DepCommandError.MissingArgument;
    }

    // Assertion: After check, we know arguments exist
    std.debug.assert(arguments.len >= 1);

    // Parse task ID from CLI argument (supports both numeric "19" and formatted "auth:019")
    // Rationale: parseTaskInput returns a union of either internal_id or plan_task format.
    // For backwards compatibility, internal_id is used directly.
    // For plan_task format, we resolve the slug:number to the internal AUTOINCREMENT ID.
    const parsed_task_id = utils.parseTaskInput(arguments[0]) catch {
        return DepCommandError.InvalidArgument;
    };
    const task_id = switch (parsed_task_id) {
        .internal_id => |id| id,
        .plan_task => |pt| blk: {
            const resolved_task = try storage.tasks.getTaskByPlanAndNumber(pt.slug, pt.number);
            if (resolved_task == null) {
                var stderr_buffer: [256]u8 = undefined;
                var stderr_writer = std.Io.File.stderr().writer(io, stderr_buffer[0..]);
                stderr_writer.interface.print("Error: Task {s}:{d} not found\n", .{ pt.slug, pt.number }) catch {};
                return DepCommandError.InvalidArgument;
            }
            break :blk resolved_task.?;
        },
    };

    // Assertions: Task ID must be positive
    std.debug.assert(task_id > 0);

    // Rationale: getDependents returns transitive dependent chain with depth indicators.
    // Depth shows how many levels away each dependent is (1 = direct, 2+ = indirect).
    const dependents = try storage.getDependents(task_id);
    defer {
        for (dependents) |*dependent| {
            dependent.deinit(allocator);
        }
        allocator.free(dependents);
    }

    if (!builtin.is_test) {
        var stdout_buffer: [8192]u8 = undefined;
        var stdout_writer = std.Io.File.stdout().writer(io, stdout_buffer[0..]);
        const stdout = &stdout_writer.interface;

        // Rationale: Use formatBlockerInfo with is_blocker=false to display dependent tree.
        // This function formats with depth indicators and status icons.
        if (json_output) {
            try format.formatBlockerInfoJson(stdout, dependents, false);
        } else {
            try format.formatBlockerInfo(stdout, dependents, false);
        }

        stdout.flush() catch {};
    }
}
