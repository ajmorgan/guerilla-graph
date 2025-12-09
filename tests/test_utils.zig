//! Shared test utilities for command tests.
//!
//! This module provides common helpers used across all command test files:
//! - Temporary database creation
//! - Test workspace setup
//! - Cleanup utilities

const std = @import("std");

/// Generate a temporary database path for testing.
/// Caller must free the returned path.
/// Uses random number to ensure uniqueness across parallel test runs.
pub fn getTemporaryDatabasePath(allocator: std.mem.Allocator, test_name: []const u8) ![]u8 {
    // Generate a random number for uniqueness (tests run in parallel)
    // Use address of stack variable as seed for PRNG (varies per test invocation)
    var stack_var: u8 = 0;
    const seed: usize = @intFromPtr(&stack_var);
    var prng = std.Random.DefaultPrng.init(@truncate(seed));
    const random_id = prng.random().int(u64);

    var path_buffer: [256]u8 = undefined;
    const temp_path = try std.fmt.bufPrint(&path_buffer, "/tmp/guerilla_graph_commands_{s}_{d}.db", .{ test_name, random_id });
    return try allocator.dupe(u8, temp_path);
}

/// Clean up a database file created for testing.
/// Silently ignores errors if file doesn't exist.
pub fn cleanupDatabaseFile(database_path: []const u8) void {
    std.fs.cwd().deleteFile(database_path) catch {};
}

// SQLite helper functions for test assertions
// Note: c_funcs is re-exported from storage.zig (line 23) for test compatibility
const guerilla_graph = @import("guerilla_graph");
const c = guerilla_graph.storage.c_funcs;
const SqliteError = guerilla_graph.storage.SqliteError;

/// Bind text parameter to prepared statement.
/// Note: Simple wrapper for C API - assertions omitted as C API validates internally.
/// Tiger Style: Test-only utility, 4 lines (well under 70-line limit).
pub fn bindText(statement: *c.sqlite3_stmt, index: c_int, text: []const u8) !void {
    const result = c.sqlite3_bind_text(statement, index, text.ptr, @intCast(text.len), null);
    if (result != c.SQLITE_OK) return SqliteError.BindFailed;
}

/// Bind 64-bit integer parameter to prepared statement.
/// Note: Simple wrapper for C API - assertions omitted as C API validates internally.
/// Tiger Style: Test-only utility, 4 lines (well under 70-line limit).
pub fn bindInt64(statement: *c.sqlite3_stmt, index: c_int, value: i64) !void {
    const result = c.sqlite3_bind_int64(statement, index, value);
    if (result != c.SQLITE_OK) return SqliteError.BindFailed;
}

/// Percentile statistics for performance analysis.
/// p50 = median (typical case), p90 = 90th percentile (good case boundary),
/// p99 = 99th percentile (tail latency - worst 1%).
pub const PercentileResult = struct {
    p50: i64, // Median - typical case
    p90: i64, // 90th percentile - good case boundary
    p99: i64, // 99th percentile - tail latency (worst 1%)
};

/// Calculate percentiles from timing samples.
/// Requires at least 100 samples for meaningful p99 calculation.
/// Sorts samples in-place (modifies input array).
///
/// Rationale: Percentiles reveal tail latency (p99) that avg/max can miss.
/// Tiger Style: 2+ assertions for validation.
pub fn calculatePercentiles(samples: []i64) PercentileResult {
    // Assertions: Validate input (Tiger Style: 2+ per function)
    std.debug.assert(samples.len >= 100); // Need enough samples for p99
    std.debug.assert(samples.len > 0);

    // Sort samples for percentile calculation
    // Rationale: Percentiles require ordered data
    std.mem.sort(i64, samples, {}, std.sort.asc(i64));

    // Calculate indices for percentiles
    const p50_idx = samples.len / 2;
    const p90_idx = (samples.len * 90) / 100;
    const p99_idx = (samples.len * 99) / 100;

    // Assertions: Indices are valid
    std.debug.assert(p50_idx < samples.len);
    std.debug.assert(p90_idx < samples.len);
    std.debug.assert(p99_idx < samples.len);

    return PercentileResult{
        .p50 = samples[p50_idx],
        .p90 = samples[p90_idx],
        .p99 = samples[p99_idx],
    };
}
