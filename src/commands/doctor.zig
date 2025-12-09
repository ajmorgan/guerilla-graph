//! Doctor command handler for Guerilla Graph CLI.
//!
//! This module contains the doctor command handler which performs
//! comprehensive database health checks:
//! - handleDoctor: Run database integrity validation and display results
//!
//! The doctor command validates database integrity by running 11 health checks
//! including orphaned dependencies, cycles, invalid statuses, and schema validation.
//! Tiger Style: Full names, 2+ assertions per function, rationale comments.

const std = @import("std");
const builtin = @import("builtin");
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

// ============================================================================
// Doctor Command (Database Health Check)
// ============================================================================

/// Handle doctor command
/// Runs comprehensive health checks on the database and displays results.
///
/// Command: gg doctor
/// Options:
///   --json: Output in JSON format
///
/// Example: gg doctor
///
/// Rationale: Validates database integrity by running 11 health checks:
/// 1. Orphaned dependencies, 2. Cycles, 3. Orphaned tasks, 4. Empty plans,
/// 5. completed_at invariant, 6. Invalid status, 7. Title length,
/// 8. Schema version, 9. Missing indexes, 10. Large descriptions.
pub fn handleDoctor(
    allocator: std.mem.Allocator,
    arguments: []const []const u8,
    json_output: bool,
    storage: *Storage,
) !void {
    // Assertions: Validate inputs (Tiger Style: 2+ per function)
    // Rationale: Doctor command takes no arguments.
    // Reject any provided arguments to prevent user confusion.
    if (arguments.len > 0) {
        return CommandError.InvalidArgument;
    }

    // Rationale: Run comprehensive health checks on the database.
    // healthCheck returns a HealthReport with errors and warnings.
    var health_report = try storage.healthCheck();
    defer health_report.deinit(allocator);

    if (!builtin.is_test) {
        var stdout_buffer: [8192]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(stdout_buffer[0..]);
        const stdout = &stdout_writer.interface;

        if (json_output) {
            // JSON format
            try stdout.writeAll("{\n");
            try stdout.writeAll("  \"status\": ");
            if (health_report.errors.len == 0) {
                try stdout.writeAll("\"healthy\",\n");
            } else {
                try stdout.writeAll("\"unhealthy\",\n");
            }
            try stdout.print("  \"error_count\": {d},\n", .{health_report.errors.len});
            try stdout.print("  \"warning_count\": {d},\n", .{health_report.warnings.len});

            try stdout.writeAll("  \"errors\": [\n");
            for (health_report.errors, 0..) |err, index| {
                try stdout.print("    {{\"message\": \"{s}\"}}", .{err.message});
                if (index < health_report.errors.len - 1) {
                    try stdout.writeAll(",\n");
                } else {
                    try stdout.writeAll("\n");
                }
            }
            try stdout.writeAll("  ],\n");

            try stdout.writeAll("  \"warnings\": [\n");
            for (health_report.warnings, 0..) |warn, index| {
                try stdout.print("    {{\"message\": \"{s}\"}}", .{warn.message});
                if (index < health_report.warnings.len - 1) {
                    try stdout.writeAll(",\n");
                } else {
                    try stdout.writeAll("\n");
                }
            }
            try stdout.writeAll("  ]\n");
            try stdout.writeAll("}\n");
        } else {
            // Human-readable format
            try stdout.writeAll("Database Health Check\n");
            try stdout.writeAll("=====================\n\n");

            if (health_report.errors.len == 0) {
                try stdout.writeAll("Status: Healthy\n\n");
            } else {
                try stdout.print("Status: Unhealthy ({d} error(s) found)\n\n", .{health_report.errors.len});
            }

            if (health_report.errors.len > 0) {
                try stdout.writeAll("Errors:\n");
                for (health_report.errors) |err| {
                    try stdout.print("  - {s}\n", .{err.message});
                    if (err.details) |details| {
                        try stdout.print("    {s}\n", .{details});
                    }
                }
                try stdout.writeAll("\n");
            }

            if (health_report.warnings.len > 0) {
                try stdout.print("Warnings ({d}):\n", .{health_report.warnings.len});
                for (health_report.warnings) |warn| {
                    try stdout.print("  - {s}\n", .{warn.message});
                    if (warn.details) |details| {
                        try stdout.print("    {s}\n", .{details});
                    }
                }
                try stdout.writeAll("\n");
            }

            if (health_report.errors.len == 0 and health_report.warnings.len == 0) {
                try stdout.writeAll("No issues found. Database is in good health.\n");
            }
        }

        stdout.flush() catch {};
    }
}
