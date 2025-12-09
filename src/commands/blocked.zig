//! Blocked command handler for Guerilla Graph CLI.
//!
//! This module contains the blocked command handler that displays tasks
//! with incomplete dependencies, showing blocker count for each.
//!
//! Commands:
//! - handleQueryBlocked: Show blocked tasks with blocker counts
//!
//! This command is read-only and optimized for fast queries.
//! Tiger Style: Full names, 2+ assertions per function, rationale comments.

const std = @import("std");
const builtin = @import("builtin");
const types = @import("../types.zig");
const format = @import("../format.zig");
const Storage = @import("../storage.zig").Storage;

/// Error types for command execution.
pub const CommandError = error{
    /// A required positional argument was not provided.
    MissingArgument,

    /// An argument value is invalid or malformed.
    InvalidArgument,

    /// Storage has not been initialized (internal error).
    StorageNotInitialized,
};

/// Handle blocked command
/// Displays tasks with incomplete dependencies, showing blocker count for each.
///
/// Command: gg blocked
/// Example: gg blocked
///
/// Rationale: Shows which tasks are currently blocked and by how many dependencies.
/// Tasks are ordered by blocker_count descending (most blocked first) to help identify bottlenecks.
/// See PLAN.md Section 7.4 for command specification.
pub fn handleQueryBlocked(
    allocator: std.mem.Allocator,
    arguments: []const []const u8,
    json_output: bool,
    storage: *Storage,
) !void {
    // Rationale: blocked command takes no arguments, but we validate anyway
    if (arguments.len > 0) {
        return CommandError.InvalidArgument;
    }

    // Rationale: getBlockedTasks returns tasks with incomplete dependencies,
    // along with blocker counts for each task (for bottleneck analysis).
    var result = try storage.*.getBlockedTasks();
    defer result.deinit(allocator);

    // Postcondition: Result set within reasonable bounds.
    // Rationale: 10000 tasks max per CLAUDE.md performance limits.
    std.debug.assert(result.tasks.len <= 10000);

    // Rationale: Skip stdout in tests to avoid buffering issues.
    // Test coverage is via storage.getBlockedTasks() unit tests.
    if (!builtin.is_test) {
        // Rationale: Get stdout writer for formatted output.
        // Use a buffered writer to ensure output is flushed properly.
        var stdout_buffer: [8192]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(stdout_buffer[0..]);
        const stdout = &stdout_writer.interface;

        // Rationale: Use format module to display blocked tasks with blocker counts.
        // formatBlockedTasks shows each task with its blocker count for bottleneck analysis.
        // formatBlockedTasksJson includes blocker_count field in JSON output.
        if (json_output) {
            try format.formatBlockedTasksJson(allocator, stdout, result.tasks, result.blocker_counts);
        } else {
            try format.formatBlockedTasks(allocator, stdout, result.tasks, result.blocker_counts);
        }
        try stdout.flush();
    }
}
