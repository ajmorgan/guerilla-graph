//! Tests for utility functions (utils.zig).
//!
//! Covers: validateKebabCase, formatTaskId, parseTaskId, unixTimestamp, findWorkspace.

const std = @import("std");
const guerilla_graph = @import("guerilla_graph");
const utils = guerilla_graph.utils;
const validateKebabCase = utils.validateKebabCase;
const formatTaskId = utils.formatTaskId;
const parseTaskId = utils.parseTaskId;
const parseTaskIdFlexible = utils.parseTaskIdFlexible;
const parseTaskInput = utils.parseTaskInput;
const unixTimestamp = utils.unixTimestamp;
// Note: findWorkspace and findWorkspace_checkPath tests are commented out
// as these functions are not yet implemented in utils.zig
// const findWorkspace = utils.findWorkspace;
// const findWorkspace_checkPath = utils.findWorkspace_checkPath;

test "validateKebabCase: valid inputs" {
    // Methodology: Test all valid kebab-case patterns including edge cases.
    // Valid patterns: single words, hyphenated phrases, single letters.

    try validateKebabCase("auth");
    try validateKebabCase("tech-debt");
    try validateKebabCase("my-feature");
    try validateKebabCase("a");
    try validateKebabCase("a-b");
    try validateKebabCase("my-long-feature-name");
}

test "validateKebabCase: invalid inputs" {
    // Methodology: Verify all invalid patterns are rejected.
    // Invalid patterns: uppercase, underscores, spaces, leading/trailing hyphens, empty.

    try std.testing.expectError(error.EmptyId, validateKebabCase(""));
    try std.testing.expectError(error.InvalidKebabCase, validateKebabCase("-auth"));
    try std.testing.expectError(error.InvalidKebabCase, validateKebabCase("auth-"));
    try std.testing.expectError(error.InvalidKebabCase, validateKebabCase("Auth"));
    try std.testing.expectError(error.InvalidKebabCase, validateKebabCase("tech_debt"));
    try std.testing.expectError(error.InvalidKebabCase, validateKebabCase("my feature"));
    try std.testing.expectError(error.InvalidKebabCase, validateKebabCase("123feature"));
    try std.testing.expectError(error.InvalidKebabCase, validateKebabCase("feature!"));
}

test "formatTaskId: valid formatting" {
    // Methodology: Verify task ID formatting with zero-padding and correct separator.
    // Tests single-digit, double-digit, and triple-digit task numbers.

    const allocator = std.testing.allocator;

    const task_id_1 = try formatTaskId(allocator, "auth", 1);
    defer allocator.free(task_id_1);
    try std.testing.expectEqualStrings("auth:001", task_id_1);

    const task_id_42 = try formatTaskId(allocator, "tech-debt", 42);
    defer allocator.free(task_id_42);
    try std.testing.expectEqualStrings("tech-debt:042", task_id_42);

    const task_id_999 = try formatTaskId(allocator, "feature", 999);
    defer allocator.free(task_id_999);
    try std.testing.expectEqualStrings("feature:999", task_id_999);
}

test "parseTaskId: valid parsing" {
    // Methodology: Verify parsing extracts label and number correctly.
    // Tests various label lengths and number formats.

    const result_1 = try parseTaskId("auth:001");
    try std.testing.expectEqualStrings("auth", result_1.plan_id);
    try std.testing.expectEqual(@as(u32, 1), result_1.number);

    const result_2 = try parseTaskId("tech-debt:042");
    try std.testing.expectEqualStrings("tech-debt", result_2.plan_id);
    try std.testing.expectEqual(@as(u32, 42), result_2.number);

    const result_3 = try parseTaskId("feature:999");
    try std.testing.expectEqualStrings("feature", result_3.plan_id);
    try std.testing.expectEqual(@as(u32, 999), result_3.number);
}

test "parseTaskId: invalid inputs" {
    // Methodology: Verify all malformed task IDs are rejected.
    // Invalid patterns: missing colon, empty segments, non-numeric number.

    try std.testing.expectError(error.InvalidTaskId, parseTaskId("auth"));
    try std.testing.expectError(error.InvalidTaskId, parseTaskId(":001"));
    try std.testing.expectError(error.InvalidTaskId, parseTaskId("auth:"));
    try std.testing.expectError(error.InvalidCharacter, parseTaskId("auth:abc"));
}

test "parseTaskId: roundtrip with formatTaskId" {
    // Methodology: Verify format and parse are inverse operations.
    // Format a task ID, then parse it back to verify data integrity.

    const allocator = std.testing.allocator;

    const original_label = "my-feature";
    const original_number: u32 = 123;

    const formatted = try formatTaskId(allocator, original_label, original_number);
    defer allocator.free(formatted);

    const parsed = try parseTaskId(formatted);

    try std.testing.expectEqualStrings(original_label, parsed.plan_id);
    try std.testing.expectEqual(original_number, parsed.number);
}

test "unixTimestamp: returns valid timestamp" {
    // Methodology: Verify timestamp is reasonable (between 2020 and 2100).
    // Also verify consistency across multiple calls (monotonically increasing or equal).

    const timestamp_1 = unixTimestamp();
    const timestamp_2 = unixTimestamp();

    // Both timestamps should be in valid range
    try std.testing.expect(timestamp_1 > 1577836800); // After 2020-01-01
    try std.testing.expect(timestamp_1 < 4102444800); // Before 2100-01-01
    try std.testing.expect(timestamp_2 > 1577836800);
    try std.testing.expect(timestamp_2 < 4102444800);

    // Second timestamp should be >= first (time moves forward)
    try std.testing.expect(timestamp_2 >= timestamp_1);
}

// TODO: Re-enable when findWorkspace is implemented
// test "findWorkspace: error when not in workspace" {
//     // Methodology: Test that findWorkspace returns NotAWorkspace error
//     // when called from a directory without .gg/tasks.db.
//     // We test this by verifying the function returns an error in /tmp,
//     // which is unlikely to contain a .gg workspace.
//
//     // Note: This test would ideally change directories, but std.process.changeCwd
//     // is not available in Zig 0.16. Instead, we rely on the current environment
//     // not having a .gg workspace above it. This is a limitation of the test,
//     // but the implementation is correct.
//
//     // Skip this test if we're actually in a .gg workspace
//     // (which would happen if running tests from within a gg project)
//     const allocator = std.testing.allocator;
//     const result = findWorkspace(allocator);
//
//     // If we get a result, free it and skip test (we're in a workspace)
//     if (result) |path| {
//         allocator.free(path);
//         return; // Skip test - we're in a workspace
//     } else |err| {
//         // We should get NotAWorkspace error
//         try std.testing.expectEqual(error.NotAWorkspace, err);
//     }
// }

// TODO: Re-enable when findWorkspace_checkPath is implemented
// test "findWorkspace_checkPath: returns null for non-existent workspace" {
//     // Methodology: Verify checkPath returns null when .gg/tasks.db doesn't exist.
//     // Use /tmp as test directory (unlikely to have .gg workspace).
//
//     const allocator = std.testing.allocator;
//
//     const result = try findWorkspace_checkPath(allocator, "/tmp");
//     try std.testing.expect(result == null);
// }

// TODO: Re-enable when findWorkspace is implemented
// test "findWorkspace: finds workspace from nested directory" {
//     // Methodology: Create a temporary .gg workspace and verify discovery works
//     // from both the root and nested directories.
//
//     const allocator = std.testing.allocator;
//
//     // Create temporary test workspace
//     const test_dir = "/tmp/gg_test_workspace_12345";
//     const test_nested_dir = test_dir ++ "/src/deep/nested";
//
//     // Clean up any previous test runs
//     std.fs.deleteTreeAbsolute(test_dir) catch {};
//
//     // Create directory structure (recursively)
//     var tmp_dir = try std.fs.openDirAbsolute("/tmp", .{});
//     defer tmp_dir.close();
//     try tmp_dir.makePath("gg_test_workspace_12345/src/deep/nested");
//     defer std.fs.deleteTreeAbsolute(test_dir) catch {};
//
//     // Create .gg/tasks.db
//     try tmp_dir.makePath("gg_test_workspace_12345/.gg");
//     const db_path = test_dir ++ "/.gg/tasks.db";
//     const db_file = try std.fs.createFileAbsolute(db_path, .{});
//     db_file.close();
//
//     // Save original working directory
//     var original_cwd_buffer: [std.fs.max_path_bytes]u8 = undefined;
//     const original_cwd = try std.process.getCwd(&original_cwd_buffer);
//     const original_cwd_owned = try allocator.dupe(u8, original_cwd);
//     defer allocator.free(original_cwd_owned);
//
//     // Test 1: Find workspace from nested directory
//     {
//         var test_cwd_dir = try std.fs.openDirAbsolute(test_nested_dir, .{});
//         defer test_cwd_dir.close();
//         try test_cwd_dir.setAsCwd();
//
//         const found_path = try findWorkspace(allocator);
//         defer allocator.free(found_path);
//
//         // Verify it found the correct database
//         try std.testing.expect(std.mem.endsWith(u8, found_path, "/.gg/tasks.db"));
//         try std.testing.expect(std.mem.indexOf(u8, found_path, "gg_test_workspace_12345") != null);
//     }
//
//     // Test 2: Find workspace from workspace root
//     {
//         var test_root_dir = try std.fs.openDirAbsolute(test_dir, .{});
//         defer test_root_dir.close();
//         try test_root_dir.setAsCwd();
//
//         const found_path = try findWorkspace(allocator);
//         defer allocator.free(found_path);
//
//         // Verify it found the correct database
//         try std.testing.expect(std.mem.endsWith(u8, found_path, "/.gg/tasks.db"));
//         try std.testing.expect(std.mem.indexOf(u8, found_path, "gg_test_workspace_12345") != null);
//     }
//
//     // Restore original working directory
//     var restore_dir = try std.fs.openDirAbsolute(original_cwd_owned, .{});
//     defer restore_dir.close();
//     try restore_dir.setAsCwd();
// }

// ============================================================================
// Tests migrated from inline tests in utils.zig
// ============================================================================

test "parseTaskIdFlexible - numeric input" {
    // Test fast path: plain numeric input
    try std.testing.expectEqual(@as(u32, 1), try parseTaskIdFlexible("1"));
    try std.testing.expectEqual(@as(u32, 42), try parseTaskIdFlexible("42"));
    try std.testing.expectEqual(@as(u32, 999), try parseTaskIdFlexible("999"));
}

test "parseTaskIdFlexible - formatted input" {
    // Test fallback path: plan:number format
    try std.testing.expectEqual(@as(u32, 1), try parseTaskIdFlexible("auth:001"));
    try std.testing.expectEqual(@as(u32, 42), try parseTaskIdFlexible("tech-debt:042"));
    try std.testing.expectEqual(@as(u32, 123), try parseTaskIdFlexible("feature:123"));
}

test "parseTaskIdFlexible - invalid input" {
    // Test error cases
    try std.testing.expectError(error.InvalidTaskId, parseTaskIdFlexible("invalid"));
    try std.testing.expectError(error.InvalidTaskId, parseTaskIdFlexible(":123"));
    try std.testing.expectError(error.InvalidTaskId, parseTaskIdFlexible("plan:"));
}

test "parseTaskInput - numeric input" {
    // Test backwards compatibility: plain numeric input
    const result1 = try parseTaskInput("1");
    try std.testing.expectEqual(@as(u32, 1), result1.internal_id);

    const result42 = try parseTaskInput("42");
    try std.testing.expectEqual(@as(u32, 42), result42.internal_id);

    const result999 = try parseTaskInput("999");
    try std.testing.expectEqual(@as(u32, 999), result999.internal_id);
}

test "parseTaskInput - formatted input" {
    // Test new format: plan:number
    const result_auth = try parseTaskInput("auth:001");
    try std.testing.expectEqualStrings("auth", result_auth.plan_task.slug);
    try std.testing.expectEqual(@as(u32, 1), result_auth.plan_task.number);

    const result_tech = try parseTaskInput("tech-debt:042");
    try std.testing.expectEqualStrings("tech-debt", result_tech.plan_task.slug);
    try std.testing.expectEqual(@as(u32, 42), result_tech.plan_task.number);

    const result_feature = try parseTaskInput("feature:123");
    try std.testing.expectEqualStrings("feature", result_feature.plan_task.slug);
    try std.testing.expectEqual(@as(u32, 123), result_feature.plan_task.number);
}

test "parseTaskInput - invalid input" {
    // Test error cases
    try std.testing.expectError(error.InvalidTaskId, parseTaskInput("invalid"));
    try std.testing.expectError(error.InvalidTaskId, parseTaskInput(":123"));
    try std.testing.expectError(error.InvalidTaskId, parseTaskInput("plan:"));
}

// ============================================================================
// File I/O Tests (merged from description_file_test.zig)
// ============================================================================

test "description-file respects size limit" {
    const allocator = std.testing.allocator;

    // Create file larger than limit
    const temp_file = "test_large.md";
    var file = try std.fs.cwd().createFile(temp_file, .{});
    defer std.fs.cwd().deleteFile(temp_file) catch {};

    // Write 11MB of data (exceeds 10MB limit)
    var buffer: [1024]u8 = undefined;
    @memset(&buffer, 'A');
    var i: usize = 0;
    while (i < 11 * 1024) : (i += 1) {
        try file.writeAll(&buffer);
    }
    file.close();

    // Attempt to read (should fail)
    const cwd = std.fs.cwd();
    const max_size = std.Io.Limit.limited(10 * 1024 * 1024);
    const result = cwd.readFileAlloc(temp_file, allocator, max_size);

    try std.testing.expectError(error.StreamTooLong, result);
}

test "description-file handles missing file" {
    const allocator = std.testing.allocator;

    const max_size = std.Io.Limit.limited(10 * 1024 * 1024);
    const result = std.fs.cwd().readFileAlloc("nonexistent.md", allocator, max_size);
    try std.testing.expectError(error.FileNotFound, result);
}
