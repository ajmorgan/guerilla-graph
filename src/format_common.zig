const std = @import("std");

/// Format elapsed time as precise hours and minutes (e.g., "2h 15m")
///
/// This function converts a duration in seconds to a human-readable string.
/// Used for displaying task durations and execution times.
///
/// Inputs:
///   - allocator: Allocator for string formatting
///   - seconds: Duration in seconds (must be non-negative)
///
/// Returns:
///   - Formatted string like "2h 15m" or "45m"
///   - Caller owns returned memory and must free it
///
/// Example:
///   const elapsed = try formatElapsedTime(gpa, 7500); // "2h 5m"
///   defer allocator.free(elapsed);
pub fn formatElapsedTime(allocator: std.mem.Allocator, seconds: i64) ![]const u8 {
    std.debug.assert(seconds >= 0);

    const total_minutes = @divFloor(seconds, 60);
    const hours = @divFloor(total_minutes, 60);
    const minutes = @mod(total_minutes, 60);

    if (hours > 0) {
        return try std.fmt.allocPrint(allocator, "{d}h {d}m", .{ hours, minutes });
    } else {
        return try std.fmt.allocPrint(allocator, "{d}m", .{minutes});
    }
}

/// Format a timestamp in human-readable format
///
/// This function formats a Unix timestamp with a field name for display.
/// Currently displays raw Unix timestamp - future enhancement will convert
/// to YYYY-MM-DD HH:MM:SS format.
///
/// Inputs:
///   - writer: Output writer for formatted text
///   - field_name: Label for the timestamp (e.g., "Created", "Updated")
///   - timestamp: Unix timestamp (seconds since epoch)
///
/// Returns:
///   - Error if write fails
///
/// Example:
///   try formatTimestamp(stdout, "Created", 1734567890);
///   // Output: "Created: 1734567890"
pub fn formatTimestamp(writer: anytype, field_name: []const u8, timestamp: i64) !void {
    std.debug.assert(field_name.len > 0); // Field name must not be empty
    std.debug.assert(timestamp >= 0); // Unix timestamps must be non-negative

    // For now, just print the Unix timestamp
    // Future enhancement: Convert to human-readable format (YYYY-MM-DD HH:MM:SS)
    try writer.print("{s}: {d}\n", .{ field_name, timestamp });
}
