//! Workflow command handler for Guerilla Graph CLI.
//!
//! This module contains the handleWorkflow command which displays workflow context
//! for agents working with the task tracker. It shows core workflow steps,
//! essential commands, task description format, and multi-agent coordination tips.
//!
//! Tiger Style: Full names, 2+ assertions per function, rationale comments.

const std = @import("std");
const system_help = @import("../help/content/system.zig");

/// Handle workflow command
/// Displays workflow context by delegating to centralized help system.
/// Content maintained in src/help/content/system.zig for single source of truth.
///
/// Command: gg workflow
/// Example: gg workflow
pub fn handleWorkflow(allocator: std.mem.Allocator, json_output: bool) !void {
    // Rationale: Workflow command delegates to centralized help content.
    // This eliminates duplication and provides single source of truth.
    // Parameters kept for API consistency with other command handlers.
    // Future: json_output could enable structured workflow output.
    _ = allocator;
    _ = json_output;

    // Rationale: Get the stdout writer for formatted output.
    // We use a buffered writer to ensure output is flushed properly.
    var stdout_buffer: [8192]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(stdout_buffer[0..]);
    const stdout = &stdout_writer.interface;

    // Rationale: Delegate to centralized help content from help system.
    // Content is maintained in src/help/content/system.zig.
    try stdout.writeAll(system_help.workflow_help);

    // Flush output to ensure everything is displayed
    try stdout.flush();
}
