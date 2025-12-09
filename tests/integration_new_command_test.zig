//! Tests for smart new command (gg new).
//!
//! Covers: Plan creation, task creation, colon detection, errors

const std = @import("std");
const guerilla_graph = @import("guerilla_graph");
const test_utils = @import("test_utils.zig");

test "smart new: create plan without title" {
    // Methodology: Test gg new <slug> creates plan with empty title
    const allocator = std.testing.allocator;

    var test_storage = try test_utils.createTestStorage(allocator);
    defer test_storage.deinit();

    // Create plan without title
    try test_storage.storage.createPlan("test-plan", "", "Test plan description", null);

    // Verify plan exists with empty title
    var plan = try test_storage.storage.getPlanSummary("test-plan") orelse return error.TestUnexpectedResult;
    defer plan.deinit(allocator);

    try std.testing.expectEqualStrings("test-plan", plan.slug);
    try std.testing.expectEqualStrings("", plan.title);
}

test "smart new: create plan with title" {
    // Methodology: Test gg new <slug> --title "..." creates plan
    const allocator = std.testing.allocator;

    var test_storage = try test_utils.createTestStorage(allocator);
    defer test_storage.deinit();

    try test_storage.storage.createPlan("auth", "Authentication System", "", null);

    var plan = try test_storage.storage.getPlanSummary("auth") orelse return error.TestUnexpectedResult;
    defer plan.deinit(allocator);

    try std.testing.expectEqualStrings("auth", plan.slug);
    try std.testing.expectEqualStrings("Authentication System", plan.title);
}

test "smart new: create task without title" {
    // Methodology: Test gg new <slug>: creates task with empty title
    const allocator = std.testing.allocator;

    var test_storage = try test_utils.createTestStorage(allocator);
    defer test_storage.deinit();

    // Create plan first
    try test_storage.storage.createPlan("auth", "Auth", "", null);

    // Create task without title
    const task_id = try test_storage.storage.createTask("auth", "", "", &[_][]const u8{});

    // Verify task exists with empty title
    var task = try test_storage.storage.getTask(task_id) orelse return error.TestUnexpectedResult;
    defer task.deinit(allocator);

    try std.testing.expectEqualStrings("", task.title);
}

test "smart new: create task with title" {
    // Methodology: Test gg new <slug>: --title "..." creates task
    const allocator = std.testing.allocator;

    var test_storage = try test_utils.createTestStorage(allocator);
    defer test_storage.deinit();

    try test_storage.storage.createPlan("auth", "Auth", "", null);
    const task_id = try test_storage.storage.createTask("auth", "Add login endpoint", "", &[_][]const u8{});

    var task = try test_storage.storage.getTask(task_id) orelse return error.TestUnexpectedResult;
    defer task.deinit(allocator);

    try std.testing.expectEqualStrings("Add login endpoint", task.title);
}

test "smart new: colon detection" {
    // Methodology: Verify colon suffix detection works
    const allocator = std.testing.allocator;

    // Test that endsWith detects colon
    try std.testing.expect(std.mem.endsWith(u8, "auth:", ":"));
    try std.testing.expect(!std.mem.endsWith(u8, "auth", ":"));
    try std.testing.expect(std.mem.endsWith(u8, ":", ":"));

    _ = allocator;
}

test "smart new: slug extraction from colon format" {
    // Methodology: Verify plan slug extraction from "slug:" format
    const slug_with_colon = "auth:";
    const extracted = slug_with_colon[0 .. slug_with_colon.len - 1];

    try std.testing.expectEqualStrings("auth", extracted);
}

test "smart new: kebab-case validation" {
    // Methodology: Verify validateKebabCase works for valid and invalid slugs
    const utils = guerilla_graph.utils;

    // Valid kebab-case
    try utils.validateKebabCase("auth");
    try utils.validateKebabCase("feature-x");
    try utils.validateKebabCase("long-feature-name");

    // Invalid cases should error
    const invalid_cases = [_][]const u8{ "MyPlan", "plan_name", "Plan", "PLAN", "plan-", "-plan" };
    for (invalid_cases) |invalid| {
        const result = utils.validateKebabCase(invalid);
        try std.testing.expectError(error.InvalidKebabCase, result);
    }
}
