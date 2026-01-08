//! Help command handler for Guerilla Graph CLI.
//!
//! Provides comprehensive help documentation for all commands, examples, and workflows.

const std = @import("std");
const help_system = @import("../help/help.zig");

/// Handle help command by displaying comprehensive help text.
/// Command: gg help
/// Rationale: Delegates to centralized help system for maintainability.
pub fn handleHelp(io: std.Io, allocator: std.mem.Allocator, json_output: bool) !void {
    // Rationale: Delegate to help system with .general context for top-level help
    try help_system.displayHelp(io, .general, allocator, json_output);
}
