//! Tests for plan storage operations with new INTEGER PRIMARY KEY + slug schema.
//!
//! Covers:
//! - createPlan with slug (INTEGER id auto-generated)
//! - getPlanSummary (returns id + slug)
//! - getPlanIdFromSlug (slug→id resolution)
//! - updatePlan with slug lookup
//! - deletePlan with slug lookup and CASCADE behavior
//! - Duplicate slug detection
//! - listPlans with task counts
//!
//! Tiger Style: Each test documents methodology, uses assertions,
//! and cleans up resources properly.

const std = @import("std");
const guerilla_graph = @import("guerilla_graph");
const Storage = guerilla_graph.storage.Storage;
const SqliteError = guerilla_graph.storage.SqliteError;
const types = guerilla_graph.types;
const TaskStatus = types.TaskStatus;
// Use re-exported C types from storage to ensure type compatibility
const c = guerilla_graph.storage.c_funcs;
const test_utils = @import("test_utils.zig");

// ============================================================================
// Plan Creation Tests (INTEGER PK + slug)
// ============================================================================

test "createPlan: successful creation with auto-generated INTEGER id" {
    // Methodology: Create plan with slug, verify INTEGER id is auto-generated
    // and slug is stored correctly. Validates new schema works.
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const temp_path = "/tmp/test_create_plan_slug.db";
    std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    // Create plan with slug
    try storage.createPlan("auth", "Authentication", "User auth system", null);

    // Verify plan was created with auto-generated INTEGER id
    const database = storage.database;
    const check_sql = "SELECT id, slug, title, description FROM plans WHERE slug = ?";
    var statement: ?*c.sqlite3_stmt = null;
    const result = c.sqlite3_prepare_v2(database, check_sql, -1, &statement, null);
    try std.testing.expectEqual(c.SQLITE_OK, result);
    defer _ = c.sqlite3_finalize(statement);

    try test_utils.bindText(statement.?, 1, "auth");
    const step_result = c.sqlite3_step(statement.?);
    try std.testing.expectEqual(c.SQLITE_ROW, step_result);

    const id = c.sqlite3_column_int64(statement.?, 0);
    const slug = std.mem.span(c.sqlite3_column_text(statement.?, 1));
    const title = std.mem.span(c.sqlite3_column_text(statement.?, 2));
    const description = std.mem.span(c.sqlite3_column_text(statement.?, 3));

    // Assertions: INTEGER id is positive, slug and fields match
    try std.testing.expect(id > 0);
    try std.testing.expectEqualStrings("auth", slug);
    try std.testing.expectEqualStrings("Authentication", title);
    try std.testing.expectEqualStrings("User auth system", description);
}

test "createPlan: duplicate slug detection" {
    // Methodology: Create two plans with same slug, verify second fails.
    // Tests UNIQUE constraint on slug column.
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const temp_path = "/tmp/test_create_plan_duplicate_slug.db";
    std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    // Create first plan
    try storage.createPlan("payments", "Payment System", "Handles payments", null);

    // Attempt to create plan with duplicate slug - should fail
    const result = storage.createPlan("payments", "Duplicate Payments", "Should fail", null);
    try std.testing.expectError(SqliteError.StepFailed, result);
}

test "createPlan: multiple plans have unique INTEGER ids" {
    // Methodology: Create multiple plans, verify each gets unique INTEGER id.
    // Validates AUTOINCREMENT works correctly.
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const temp_path = "/tmp/test_create_plan_unique_ids.db";
    std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    // Create three plans
    try storage.createPlan("auth", "Authentication", "", null);
    try storage.createPlan("payments", "Payments", "", null);
    try storage.createPlan("notifications", "Notifications", "", null);

    // Query all plan ids
    const database = storage.database;
    const check_sql = "SELECT id, slug FROM plans ORDER BY id ASC";
    var statement: ?*c.sqlite3_stmt = null;
    const result = c.sqlite3_prepare_v2(database, check_sql, -1, &statement, null);
    try std.testing.expectEqual(c.SQLITE_OK, result);
    defer _ = c.sqlite3_finalize(statement);

    // First plan
    var step_result = c.sqlite3_step(statement.?);
    try std.testing.expectEqual(c.SQLITE_ROW, step_result);
    const id1 = c.sqlite3_column_int64(statement.?, 0);
    const slug1 = std.mem.span(c.sqlite3_column_text(statement.?, 1));
    try std.testing.expect(id1 > 0);
    try std.testing.expectEqualStrings("auth", slug1);

    // Second plan
    step_result = c.sqlite3_step(statement.?);
    try std.testing.expectEqual(c.SQLITE_ROW, step_result);
    const id2 = c.sqlite3_column_int64(statement.?, 0);
    const slug2 = std.mem.span(c.sqlite3_column_text(statement.?, 1));
    try std.testing.expect(id2 > id1); // IDs are sequential
    try std.testing.expectEqualStrings("payments", slug2);

    // Third plan
    step_result = c.sqlite3_step(statement.?);
    try std.testing.expectEqual(c.SQLITE_ROW, step_result);
    const id3 = c.sqlite3_column_int64(statement.?, 0);
    const slug3 = std.mem.span(c.sqlite3_column_text(statement.?, 1));
    try std.testing.expect(id3 > id2); // IDs are sequential
    try std.testing.expectEqualStrings("notifications", slug3);
}

// ============================================================================
// Plan Summary Tests (returns id + slug)
// ============================================================================

test "getPlanSummary: returns INTEGER id and slug" {
    // Methodology: Create plan, retrieve summary, verify both id and slug are present.
    // Validates new PlanSummary structure with both fields.
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const temp_path = "/tmp/test_get_plan_summary_id_slug.db";
    std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    // Create plan
    try storage.createPlan("tech-debt", "Technical Debt", "Cleanup tasks", null);

    // Get summary
    const summary_opt = try storage.getPlanSummary("tech-debt");
    try std.testing.expect(summary_opt != null);

    var summary = summary_opt.?;
    defer summary.deinit(allocator);

    // Assertions: id is positive INTEGER, slug matches
    try std.testing.expect(summary.id > 0);
    try std.testing.expectEqualStrings("tech-debt", summary.slug);
    try std.testing.expectEqualStrings("Technical Debt", summary.title);
    try std.testing.expectEqualStrings("Cleanup tasks", summary.description);
    try std.testing.expectEqual(TaskStatus.open, summary.status);
    try std.testing.expectEqual(@as(u32, 0), summary.total_tasks);
}

test "getPlanSummary: returns null for non-existent slug" {
    // Methodology: Query non-existent plan, verify null returned.
    // Tests error handling for missing plans.
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const temp_path = "/tmp/test_get_plan_summary_notfound.db";
    std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    // Query non-existent plan
    const summary = try storage.getPlanSummary("nonexistent");
    try std.testing.expectEqual(@as(?types.PlanSummary, null), summary);
}

test "getPlanSummary: includes task counts" {
    // Methodology: Create plan with tasks in various states, verify counts.
    // Tests aggregation logic in getPlanSummary.
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const temp_path = "/tmp/test_get_plan_summary_counts.db";
    std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    // Create plan and tasks
    try storage.createPlan("feature", "Feature X", "", null);
    const task1 = try storage.createTask("feature", "Task 1", "");
    const task2 = try storage.createTask("feature", "Task 2", "");
    _ = try storage.createTask("feature", "Task 3", "");

    // Update task statuses
    try storage.startTask(task1);
    try storage.startTask(task2);
    try storage.completeTask(task2);
    // task1 stays in_progress, task3 stays open

    // Get summary with task counts
    const summary_opt = try storage.getPlanSummary("feature");
    try std.testing.expect(summary_opt != null);

    var summary = summary_opt.?;
    defer summary.deinit(allocator);

    // Assertions: Counts match expected state
    try std.testing.expectEqual(@as(u32, 3), summary.total_tasks);
    try std.testing.expectEqual(@as(u32, 1), summary.open_tasks);
    try std.testing.expectEqual(@as(u32, 1), summary.in_progress_tasks);
    try std.testing.expectEqual(@as(u32, 1), summary.completed_tasks);
}

// ============================================================================
// Slug Resolution Tests
// ============================================================================

test "getPlanIdFromSlug: successful resolution" {
    // Methodology: Create plan, resolve slug to INTEGER id.
    // Validates slug→id lookup functionality.
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const temp_path = "/tmp/test_get_plan_id_from_slug.db";
    std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    // Create plan
    try storage.createPlan("billing", "Billing System", "", null);

    // Resolve slug to id
    const plan_id = try storage.plans.getPlanIdFromSlug("billing");

    // Verify id is positive and valid
    try std.testing.expect(plan_id > 0);

    // Verify id matches database
    const database = storage.database;
    const check_sql = "SELECT id FROM plans WHERE slug = ?";
    var statement: ?*c.sqlite3_stmt = null;
    const result = c.sqlite3_prepare_v2(database, check_sql, -1, &statement, null);
    try std.testing.expectEqual(c.SQLITE_OK, result);
    defer _ = c.sqlite3_finalize(statement);

    try test_utils.bindText(statement.?, 1, "billing");
    const step_result = c.sqlite3_step(statement.?);
    try std.testing.expectEqual(c.SQLITE_ROW, step_result);

    const db_id = c.sqlite3_column_int64(statement.?, 0);
    try std.testing.expectEqual(@as(u32, @intCast(db_id)), plan_id);
}

test "getPlanIdFromSlug: fails for non-existent slug" {
    // Methodology: Attempt to resolve non-existent slug, verify error.
    // Tests error handling for invalid slugs.
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const temp_path = "/tmp/test_get_plan_id_notfound.db";
    std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    // Attempt to resolve non-existent slug
    const result = storage.plans.getPlanIdFromSlug("nonexistent");
    try std.testing.expectError(SqliteError.InvalidData, result);
}

// ============================================================================
// Update Plan Tests (slug lookup)
// ============================================================================

test "updatePlan: update title by slug" {
    // Methodology: Create plan, update title using slug, verify change.
    // Tests slug-based update functionality.
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const temp_path = "/tmp/test_update_plan_title_slug.db";
    std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    // Create plan
    try storage.createPlan("analytics", "Analytics", "Old description", null);

    // Update title using slug
    try storage.updatePlan("analytics", "Advanced Analytics", null);

    // Verify update
    const summary_opt = try storage.getPlanSummary("analytics");
    try std.testing.expect(summary_opt != null);

    var summary = summary_opt.?;
    defer summary.deinit(allocator);

    try std.testing.expectEqualStrings("Advanced Analytics", summary.title);
    try std.testing.expectEqualStrings("Old description", summary.description);
}

test "updatePlan: update description by slug" {
    // Methodology: Create plan, update description using slug, verify change.
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const temp_path = "/tmp/test_update_plan_desc_slug.db";
    std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    // Create plan
    try storage.createPlan("reporting", "Reporting", "Old description", null);

    // Update description using slug
    try storage.updatePlan("reporting", null, "New detailed description");

    // Verify update
    const summary_opt = try storage.getPlanSummary("reporting");
    try std.testing.expect(summary_opt != null);

    var summary = summary_opt.?;
    defer summary.deinit(allocator);

    try std.testing.expectEqualStrings("Reporting", summary.title);
    try std.testing.expectEqualStrings("New detailed description", summary.description);
}

test "updatePlan: update both title and description by slug" {
    // Methodology: Create plan, update both fields using slug, verify changes.
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const temp_path = "/tmp/test_update_plan_both_slug.db";
    std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    // Create plan
    try storage.createPlan("search", "Search", "Old description", null);

    // Update both fields using slug
    try storage.updatePlan("search", "Advanced Search", "New search engine");

    // Verify updates
    const summary_opt = try storage.getPlanSummary("search");
    try std.testing.expect(summary_opt != null);

    var summary = summary_opt.?;
    defer summary.deinit(allocator);

    try std.testing.expectEqualStrings("Advanced Search", summary.title);
    try std.testing.expectEqualStrings("New search engine", summary.description);
}

test "updatePlan: fails for non-existent slug" {
    // Methodology: Attempt to update non-existent plan, verify error.
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const temp_path = "/tmp/test_update_plan_notfound.db";
    std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    // Attempt to update non-existent plan
    const result = storage.updatePlan("nonexistent", "New Title", null);
    try std.testing.expectError(SqliteError.InvalidData, result);
}

// ============================================================================
// Delete Plan Tests (slug lookup + CASCADE)
// ============================================================================

test "deletePlan: successful deletion by slug with no tasks" {
    // Methodology: Create plan with no tasks, delete by slug, verify deletion.
    // Tests basic slug-based deletion.
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const temp_path = "/tmp/test_delete_plan_slug_empty.db";
    std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    // Create plan
    try storage.createPlan("cleanup", "Cleanup Tasks", "", null);

    // Delete plan by slug
    const task_count = try storage.deletePlan("cleanup");
    try std.testing.expectEqual(@as(u64, 0), task_count);

    // Verify plan is deleted
    const summary = try storage.getPlanSummary("cleanup");
    try std.testing.expectEqual(@as(?types.PlanSummary, null), summary);
}

test "deletePlan: CASCADE deletes all tasks by slug" {
    // Methodology: Create plan with tasks, delete plan by slug,
    // verify all tasks are CASCADE deleted (not orphaned).
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const temp_path = "/tmp/test_delete_plan_slug_cascade.db";
    std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    // Create plan and tasks
    try storage.createPlan("migration", "Database Migration", "", null);
    const task1 = try storage.createTask("migration", "Schema update", "");
    const task2 = try storage.createTask("migration", "Data migration", "");
    const task3 = try storage.createTask("migration", "Validation", "");

    // Delete plan by slug (should CASCADE delete all tasks)
    const task_count = try storage.deletePlan("migration");
    try std.testing.expectEqual(@as(u64, 3), task_count);

    // Verify plan deleted
    const summary = try storage.getPlanSummary("migration");
    try std.testing.expectEqual(@as(?types.PlanSummary, null), summary);

    // Verify all tasks CASCADE deleted (no orphans)
    const database = storage.database;
    const check_tasks_sql = "SELECT COUNT(*) FROM tasks";
    var statement: ?*c.sqlite3_stmt = null;
    const result = c.sqlite3_prepare_v2(database, check_tasks_sql, -1, &statement, null);
    try std.testing.expectEqual(c.SQLITE_OK, result);
    defer _ = c.sqlite3_finalize(statement);

    const step_result = c.sqlite3_step(statement.?);
    try std.testing.expectEqual(c.SQLITE_ROW, step_result);
    const total_task_count = c.sqlite3_column_int64(statement.?, 0);
    try std.testing.expectEqual(@as(i64, 0), total_task_count); // All tasks deleted

    _ = task1;
    _ = task2;
    _ = task3;
}

test "deletePlan: CASCADE deletes tasks and dependencies by slug" {
    // Methodology: Create plan with tasks that have dependencies,
    // delete plan by slug, verify tasks AND dependencies are CASCADE deleted.
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const temp_path = "/tmp/test_delete_plan_slug_deps.db";
    std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    // Create plan with tasks and dependencies
    try storage.createPlan("refactor", "Code Refactor", "", null);
    const task1 = try storage.createTask("refactor", "Extract interface", "");
    const task2 = try storage.createTask("refactor", "Update callers", "");
    const task3 = try storage.createTask("refactor", "Remove old code", "");

    // Add dependencies: task2 → task1, task3 → task2
    try storage.addDependency(task2, task1);
    try storage.addDependency(task3, task2);

    // Verify dependencies exist
    const database = storage.database;
    const check_deps_before_sql = "SELECT COUNT(*) FROM dependencies";
    var deps_before_statement: ?*c.sqlite3_stmt = null;
    var result = c.sqlite3_prepare_v2(database, check_deps_before_sql, -1, &deps_before_statement, null);
    try std.testing.expectEqual(c.SQLITE_OK, result);
    defer _ = c.sqlite3_finalize(deps_before_statement);

    var step_result = c.sqlite3_step(deps_before_statement.?);
    try std.testing.expectEqual(c.SQLITE_ROW, step_result);
    const deps_before = c.sqlite3_column_int64(deps_before_statement.?, 0);
    try std.testing.expectEqual(@as(i64, 2), deps_before);

    // Delete plan by slug (CASCADE deletes tasks AND dependencies)
    const task_count = try storage.deletePlan("refactor");
    try std.testing.expectEqual(@as(u64, 3), task_count);

    // Verify all dependencies CASCADE deleted
    const check_deps_after_sql = "SELECT COUNT(*) FROM dependencies";
    var deps_after_statement: ?*c.sqlite3_stmt = null;
    result = c.sqlite3_prepare_v2(database, check_deps_after_sql, -1, &deps_after_statement, null);
    try std.testing.expectEqual(c.SQLITE_OK, result);
    defer _ = c.sqlite3_finalize(deps_after_statement);

    step_result = c.sqlite3_step(deps_after_statement.?);
    try std.testing.expectEqual(c.SQLITE_ROW, step_result);
    const deps_after = c.sqlite3_column_int64(deps_after_statement.?, 0);
    try std.testing.expectEqual(@as(i64, 0), deps_after); // All dependencies deleted
}

test "deletePlan: fails for non-existent slug" {
    // Methodology: Attempt to delete non-existent plan by slug, verify error.
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const temp_path = "/tmp/test_delete_plan_slug_notfound.db";
    std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    // Attempt to delete non-existent plan
    const result = storage.deletePlan("nonexistent");
    try std.testing.expectError(SqliteError.InvalidData, result);
}

// ============================================================================
// List Plans Tests
// ============================================================================

test "listPlans: returns plans with INTEGER ids and slugs" {
    // Methodology: Create multiple plans, list them, verify all have ids and slugs.
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const temp_path = "/tmp/test_list_plans_ids_slugs.db";
    std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    // Create plans
    try storage.createPlan("auth", "Authentication", "", null);
    try storage.createPlan("payments", "Payments", "", null);
    try storage.createPlan("notifications", "Notifications", "", null);

    // List all plans
    const plans = try storage.listPlans(null);
    defer {
        for (plans) |*plan| plan.deinit(allocator);
        allocator.free(plans);
    }

    // Verify all plans have positive INTEGER ids and correct slugs
    try std.testing.expectEqual(@as(usize, 3), plans.len);

    try std.testing.expect(plans[0].id > 0);
    try std.testing.expectEqualStrings("auth", plans[0].slug);

    try std.testing.expect(plans[1].id > 0);
    try std.testing.expectEqualStrings("payments", plans[1].slug);

    try std.testing.expect(plans[2].id > 0);
    try std.testing.expectEqualStrings("notifications", plans[2].slug);
}

test "listPlans: empty database returns empty array" {
    // Methodology: List plans in empty database, verify empty array.
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const temp_path = "/tmp/test_list_plans_empty.db";
    std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    // List plans in empty database
    const plans = try storage.listPlans(null);
    defer allocator.free(plans);

    try std.testing.expectEqual(@as(usize, 0), plans.len);
}
