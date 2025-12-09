//! Health check operations for Guerilla Graph.
//!
//! This module performs database integrity and consistency checks:
//! - Orphaned dependencies and tasks
//! - Cycle detection in dependency graph
//! - Data integrity constraints
//! - Schema validation
//! - Performance warnings

const std = @import("std");
const types = @import("types.zig");
const sql_executor = @import("sql_executor.zig");

/// Health checker for database integrity and consistency.
pub const HealthChecker = struct {
    executor: sql_executor.Executor,
    allocator: std.mem.Allocator,

    /// Initialize health checker with executor.
    /// Rationale: Store executor by VALUE to avoid dangling pointers.
    /// When Storage.init() returns by value, pointers to its fields become invalid.
    pub fn init(executor: sql_executor.Executor, allocator: std.mem.Allocator) HealthChecker {
        const checker = HealthChecker{
            .executor = executor,
            .allocator = allocator,
        };

        // Assertion: Executor must have valid database pointer (Tiger Style)
        std.debug.assert(@intFromPtr(checker.executor.database) != 0);

        return checker;
    }

    /// Run all health checks and return report with errors and warnings.
    /// Rationale: Orchestrator function that calls all 10 specialized checks.
    /// Collects issues into error_list and warning_list, then returns HealthReport with owned slices.
    pub fn healthCheck(self: *HealthChecker) !types.HealthReport {
        // Assertions: Executor must have valid database
        std.debug.assert(@intFromPtr(self.executor.database) != 0);
        std.debug.assert(@intFromPtr(self.allocator.ptr) != 0);

        var error_list = std.array_list.AlignedManaged(types.HealthIssue, null).init(self.allocator);
        var warning_list = std.array_list.AlignedManaged(types.HealthIssue, null).init(self.allocator);

        errdefer {
            for (error_list.items) |*item| item.deinit(self.allocator);
            error_list.deinit();
            for (warning_list.items) |*item| item.deinit(self.allocator);
            warning_list.deinit();
        }

        // Check 1: Orphaned dependencies
        try self.healthCheck_orphanedDependencies(&error_list);

        // Check 2: Cycles in dependency graph
        try self.healthCheck_cycles(&error_list);

        // Check 3: Tasks with invalid plan_id (orphaned tasks)
        try self.healthCheck_orphanedTasks(&error_list);

        // Check 4: Plans with no tasks (warning only)
        try self.healthCheck_emptyPlans(&warning_list);

        // Check 5: completed_at invariant violations
        try self.healthCheck_completedAtInvariant(&error_list);

        // Check 6: Invalid status values
        try self.healthCheck_invalidStatus(&error_list);

        // Check 7: Title length violations
        try self.healthCheck_titleLength(&error_list);

        // Check 8: Schema version check
        try self.healthCheck_schemaVersion(&error_list);

        // Check 9: Verify indexes exist
        try self.healthCheck_indexes(&warning_list);

        // Check 10: Large descriptions (warning only)
        try self.healthCheck_largeDescriptions(&warning_list);

        // Assertions: Verify results are valid
        std.debug.assert(error_list.items.len <= types.REASONABLE_MAX_PLANS);
        std.debug.assert(warning_list.items.len <= types.REASONABLE_MAX_PLANS);

        return types.HealthReport{
            .errors = try error_list.toOwnedSlice(),
            .warnings = try warning_list.toOwnedSlice(),
        };
    }

    /// Health Check 1: Orphaned dependencies (references to non-existent tasks)
    /// Internal health check helper. Not intended for external use.
    pub fn healthCheck_orphanedDependencies(self: *HealthChecker, error_list: *std.array_list.AlignedManaged(types.HealthIssue, null)) !void {
        // Assertions: Validate inputs (Tiger Style)
        std.debug.assert(@intFromPtr(self.allocator.ptr) != 0);
        std.debug.assert(@intFromPtr(self.executor.database) != 0);

        const sql =
            \\SELECT d.task_id, d.blocks_on_id
            \\FROM dependencies d
            \\WHERE NOT EXISTS (SELECT 1 FROM tasks WHERE id = d.task_id)
            \\   OR NOT EXISTS (SELECT 1 FROM tasks WHERE id = d.blocks_on_id)
        ;

        const OrphanRow = struct {
            task_id: u32,
            blocks_on_id: u32,

            pub fn deinit(_: *@This(), _: std.mem.Allocator) void {}
        };

        const rows = try self.executor.queryAll(OrphanRow, self.allocator, sql, .{});
        defer self.allocator.free(rows);

        for (rows) |row| {
            const details = try std.fmt.allocPrint(self.allocator, "{d} -> {d}", .{ row.task_id, row.blocks_on_id });

            try error_list.append(types.HealthIssue{
                .check_name = try self.allocator.dupe(u8, "orphaned_dependencies"),
                .message = try self.allocator.dupe(u8, "Dependency references non-existent task"),
                .details = details,
            });
        }
    }

    /// Health Check 2: Detect cycles in dependency graph
    /// Internal health check helper. Not intended for external use.
    pub fn healthCheck_cycles(self: *HealthChecker, error_list: *std.array_list.AlignedManaged(types.HealthIssue, null)) !void {
        // Assertions: Validate inputs (Tiger Style)
        std.debug.assert(@intFromPtr(self.allocator.ptr) != 0);
        std.debug.assert(@intFromPtr(self.executor.database) != 0);

        const sql =
            \\WITH RECURSIVE cycle_check(task_id, path, cycle) AS (
            \\    SELECT DISTINCT task_id, task_id, 0
            \\    FROM dependencies
            \\
            \\    UNION ALL
            \\
            \\    SELECT d.blocks_on_id,
            \\           cc.path || ' -> ' || d.blocks_on_id,
            \\           CASE WHEN
            \\               cc.path = d.blocks_on_id OR
            \\               cc.path LIKE d.blocks_on_id || ' -> %' OR
            \\               cc.path LIKE '% -> ' || d.blocks_on_id || ' -> %' OR
            \\               cc.path LIKE '% -> ' || d.blocks_on_id
            \\           THEN 1 ELSE 0 END
            \\    FROM cycle_check cc
            \\    JOIN dependencies d ON cc.task_id = d.task_id
            \\    WHERE cc.cycle = 0
            \\)
            \\SELECT path FROM cycle_check WHERE cycle = 1
        ;

        const CycleRow = struct {
            path: []const u8,

            pub fn deinit(row: *@This(), alloc: std.mem.Allocator) void {
                alloc.free(row.path);
            }
        };

        const rows = try self.executor.queryAll(CycleRow, self.allocator, sql, .{});
        defer {
            for (rows) |*row| row.deinit(self.allocator);
            self.allocator.free(rows);
        }

        for (rows) |row| {
            const details = try std.fmt.allocPrint(self.allocator, "Cycle path: {s}", .{row.path});
            try error_list.append(types.HealthIssue{
                .check_name = try self.allocator.dupe(u8, "cycle_detected"),
                .message = try self.allocator.dupe(u8, "Cycle detected in dependency graph"),
                .details = details,
            });
        }
    }

    /// Health Check 3: Tasks with invalid plan_id (orphaned tasks)
    /// Internal health check helper. Not intended for external use.
    pub fn healthCheck_orphanedTasks(self: *HealthChecker, error_list: *std.array_list.AlignedManaged(types.HealthIssue, null)) !void {
        // Assertions: Validate inputs (Tiger Style)
        std.debug.assert(@intFromPtr(self.allocator.ptr) != 0);
        std.debug.assert(@intFromPtr(self.executor.database) != 0);

        // Rationale: Find tasks with plan_id that references missing plans.
        // New schema: plan_id is NOT NULL, no orphan tasks allowed.
        const sql =
            \\SELECT t.id, t.title, t.plan_id
            \\FROM tasks t
            \\WHERE NOT EXISTS (
            \\    SELECT 1 FROM plans WHERE id = t.plan_id
            \\)
        ;

        const OrphanRow = struct {
            id: u32,
            title: []const u8,
            plan_id: u32,

            pub fn deinit(row: *@This(), alloc: std.mem.Allocator) void {
                alloc.free(row.title);
            }
        };

        const rows = try self.executor.queryAll(OrphanRow, self.allocator, sql, .{});
        defer {
            for (rows) |*row| row.deinit(self.allocator);
            self.allocator.free(rows);
        }

        for (rows) |row| {
            const details = try std.fmt.allocPrint(self.allocator, "Task {d} ('{s}') references missing plan ID {d}", .{ row.id, row.title, row.plan_id });

            try error_list.append(types.HealthIssue{
                .check_name = try self.allocator.dupe(u8, "orphaned_tasks"),
                .message = try self.allocator.dupe(u8, "Task references non-existent plan"),
                .details = details,
            });
        }
    }

    /// Health Check 4: Plans with no tasks (warning only)
    /// Internal health check helper. Not intended for external use.
    pub fn healthCheck_emptyPlans(self: *HealthChecker, warning_list: *std.array_list.AlignedManaged(types.HealthIssue, null)) !void {
        // Assertions: Validate inputs (Tiger Style)
        std.debug.assert(@intFromPtr(self.allocator.ptr) != 0);
        std.debug.assert(warning_list.items.len <= types.REASONABLE_MAX_PLANS);

        const sql =
            \\SELECT p.slug, p.title
            \\FROM plans p
            \\WHERE NOT EXISTS (SELECT 1 FROM tasks t WHERE t.plan_id = p.id)
        ;

        const EmptyPlanRow = struct {
            slug: []const u8,
            title: []const u8,
            pub fn deinit(row: *@This(), alloc: std.mem.Allocator) void {
                alloc.free(row.slug);
                alloc.free(row.title);
            }
        };

        const rows = try self.executor.queryAll(EmptyPlanRow, self.allocator, sql, .{});
        defer {
            for (rows) |*row| row.deinit(self.allocator);
            self.allocator.free(rows);
        }

        for (rows) |row| {
            const details = try std.fmt.allocPrint(self.allocator, "Plan {s} ('{s}') has no tasks", .{ row.slug, row.title });

            try warning_list.append(types.HealthIssue{
                .check_name = try self.allocator.dupe(u8, "empty_plans"),
                .message = try self.allocator.dupe(u8, "Plan has no tasks"),
                .details = details,
            });
        }
    }

    /// Health Check 5: completed_at invariant violations
    /// Internal health check helper. Not intended for external use.
    pub fn healthCheck_completedAtInvariant(self: *HealthChecker, error_list: *std.array_list.AlignedManaged(types.HealthIssue, null)) !void {
        // Assertions: Validate inputs (Tiger Style)
        std.debug.assert(@intFromPtr(self.allocator.ptr) != 0);
        std.debug.assert(error_list.items.len <= types.REASONABLE_MAX_PLANS);

        const sql =
            \\SELECT id, title, status
            \\FROM tasks
            \\WHERE (status = 'completed' AND completed_at IS NULL)
            \\   OR (status != 'completed' AND completed_at IS NOT NULL)
        ;

        const InvariantRow = struct {
            id: u32,
            title: []const u8,
            status: []const u8,
            pub fn deinit(row: *@This(), alloc: std.mem.Allocator) void {
                alloc.free(row.title);
                alloc.free(row.status);
            }
        };

        const rows = try self.executor.queryAll(InvariantRow, self.allocator, sql, .{});
        defer {
            for (rows) |*row| row.deinit(self.allocator);
            self.allocator.free(rows);
        }

        for (rows) |row| {
            const details = try std.fmt.allocPrint(self.allocator, "Task {d} ('{s}') has status={s} with invalid completed_at", .{ row.id, row.title, row.status });

            try error_list.append(types.HealthIssue{
                .check_name = try self.allocator.dupe(u8, "completed_at_invariant"),
                .message = try self.allocator.dupe(u8, "Status and completed_at are inconsistent"),
                .details = details,
            });
        }
    }

    /// Health Check 6: Invalid status values
    /// Internal health check helper. Not intended for external use.
    pub fn healthCheck_invalidStatus(self: *HealthChecker, error_list: *std.array_list.AlignedManaged(types.HealthIssue, null)) !void {
        // Assertions: Validate inputs (Tiger Style)
        std.debug.assert(@intFromPtr(self.allocator.ptr) != 0);
        std.debug.assert(error_list.items.len <= types.REASONABLE_MAX_PLANS);

        const sql =
            \\SELECT id, title, status
            \\FROM tasks
            \\WHERE status NOT IN ('open', 'in_progress', 'completed')
        ;

        const InvalidStatusRow = struct {
            id: u32,
            title: []const u8,
            status: []const u8,
            pub fn deinit(row: *@This(), alloc: std.mem.Allocator) void {
                alloc.free(row.title);
                alloc.free(row.status);
            }
        };

        const rows = try self.executor.queryAll(InvalidStatusRow, self.allocator, sql, .{});
        defer {
            for (rows) |*row| row.deinit(self.allocator);
            self.allocator.free(rows);
        }

        for (rows) |row| {
            const details = try std.fmt.allocPrint(self.allocator, "Task {d} ('{s}') has invalid status '{s}'", .{ row.id, row.title, row.status });

            try error_list.append(types.HealthIssue{
                .check_name = try self.allocator.dupe(u8, "invalid_status"),
                .message = try self.allocator.dupe(u8, "Task has invalid status value"),
                .details = details,
            });
        }
    }

    /// Health Check 7: Title length violations
    /// Internal health check helper. Not intended for external use.
    pub fn healthCheck_titleLength(self: *HealthChecker, error_list: *std.array_list.AlignedManaged(types.HealthIssue, null)) !void {
        // Assertions: Validate inputs (Tiger Style)
        std.debug.assert(@intFromPtr(self.allocator.ptr) != 0);
        std.debug.assert(error_list.items.len <= types.REASONABLE_MAX_PLANS);

        const sql =
            \\SELECT id, length(title) as title_length
            \\FROM tasks
            \\WHERE length(title) > 500 OR length(title) = 0
        ;

        const TitleLengthRow = struct {
            id: u32,
            title_length: i64,
            pub fn deinit(_: *@This(), _: std.mem.Allocator) void {}
        };

        const rows = try self.executor.queryAll(TitleLengthRow, self.allocator, sql, .{});
        defer {
            for (rows) |*row| row.deinit(self.allocator);
            self.allocator.free(rows);
        }

        for (rows) |row| {
            const details = try std.fmt.allocPrint(self.allocator, "Task {d} has title length {d} (must be 1-500)", .{ row.id, row.title_length });

            try error_list.append(types.HealthIssue{
                .check_name = try self.allocator.dupe(u8, "title_length"),
                .message = try self.allocator.dupe(u8, "Task title violates length constraint"),
                .details = details,
            });
        }
    }

    /// Health Check 8: Schema version check
    /// Internal health check helper. Not intended for external use.
    pub fn healthCheck_schemaVersion(self: *HealthChecker, error_list: *std.array_list.AlignedManaged(types.HealthIssue, null)) !void {
        // Assertions: Validate inputs (Tiger Style)
        std.debug.assert(@intFromPtr(self.allocator.ptr) != 0);
        std.debug.assert(error_list.items.len <= types.REASONABLE_MAX_PLANS);

        const sql = "SELECT version FROM schema_version ORDER BY version DESC LIMIT 1";

        const VersionRow = struct {
            version: i64,
            pub fn deinit(_: *@This(), _: std.mem.Allocator) void {}
        };

        // Try to query schema version
        const maybe_row = self.executor.queryOne(VersionRow, self.allocator, sql, .{}) catch |err| {
            // If query fails, schema_version table is missing or corrupted
            try error_list.append(types.HealthIssue{
                .check_name = try self.allocator.dupe(u8, "schema_version"),
                .message = try std.fmt.allocPrint(self.allocator, "Schema version table error: {s}", .{@errorName(err)}),
                .details = null,
            });
            return;
        };

        // If no rows returned, table is empty
        const row = maybe_row orelse {
            try error_list.append(types.HealthIssue{
                .check_name = try self.allocator.dupe(u8, "schema_version"),
                .message = try self.allocator.dupe(u8, "Schema version table is missing or empty"),
                .details = null,
            });
            return;
        };

        // Check if version matches expected
        if (row.version != 1) {
            const details = try std.fmt.allocPrint(self.allocator, "Found version {d}, expected 1", .{row.version});
            try error_list.append(types.HealthIssue{
                .check_name = try self.allocator.dupe(u8, "schema_version"),
                .message = try self.allocator.dupe(u8, "Unexpected schema version"),
                .details = details,
            });
        }
    }

    /// Health Check 9: Verify indexes exist
    /// Internal health check helper. Not intended for external use.
    pub fn healthCheck_indexes(self: *HealthChecker, warning_list: *std.array_list.AlignedManaged(types.HealthIssue, null)) !void {
        // Assertions: Validate inputs (Tiger Style)
        std.debug.assert(@intFromPtr(self.allocator.ptr) != 0);
        std.debug.assert(warning_list.items.len <= types.REASONABLE_MAX_PLANS);

        const expected_indexes = [_][]const u8{
            "idx_tasks_status",
            "idx_tasks_plan_id",
            "idx_tasks_status_plan",
            "idx_tasks_plan_created",
            "idx_dependencies_task",
            "idx_dependencies_blocks",
        };

        const sql = "SELECT name FROM sqlite_master WHERE type = 'index' AND name = ?";

        const IndexRow = struct {
            name: []const u8,
            pub fn deinit(row: *@This(), alloc: std.mem.Allocator) void {
                alloc.free(row.name);
            }
        };

        // Check each expected index
        for (expected_indexes) |index_name| {
            var maybe_row = self.executor.queryOne(IndexRow, self.allocator, sql, .{index_name}) catch |err| {
                const details = try std.fmt.allocPrint(self.allocator, "Error checking index '{s}': {s}", .{ index_name, @errorName(err) });
                try warning_list.append(types.HealthIssue{
                    .check_name = try self.allocator.dupe(u8, "missing_indexes"),
                    .message = try self.allocator.dupe(u8, "Error checking index"),
                    .details = details,
                });
                continue;
            };

            // If index not found, add warning
            if (maybe_row) |*row| {
                row.deinit(self.allocator);
            } else {
                const details = try std.fmt.allocPrint(self.allocator, "Index '{s}' is missing", .{index_name});
                try warning_list.append(types.HealthIssue{
                    .check_name = try self.allocator.dupe(u8, "missing_indexes"),
                    .message = try self.allocator.dupe(u8, "Expected index not found"),
                    .details = details,
                });
            }
        }
    }

    /// Health Check 10: Large descriptions (>1MB warning)
    /// Internal health check helper. Not intended for external use.
    pub fn healthCheck_largeDescriptions(self: *HealthChecker, warning_list: *std.array_list.AlignedManaged(types.HealthIssue, null)) !void {
        // Assertions: Validate inputs (Tiger Style)
        std.debug.assert(@intFromPtr(self.allocator.ptr) != 0);
        std.debug.assert(warning_list.items.len <= types.REASONABLE_MAX_PLANS);

        const sql =
            \\SELECT id, title, length(description) as desc_size
            \\FROM tasks
            \\WHERE length(description) > 1048576
        ;

        const LargeDescRow = struct {
            id: u32,
            title: []const u8,
            desc_size: i64,
            pub fn deinit(row: *@This(), alloc: std.mem.Allocator) void {
                alloc.free(row.title);
            }
        };

        const rows = try self.executor.queryAll(LargeDescRow, self.allocator, sql, .{});
        defer {
            for (rows) |*row| row.deinit(self.allocator);
            self.allocator.free(rows);
        }

        for (rows) |row| {
            const size_mb = @as(f64, @floatFromInt(row.desc_size)) / 1048576.0;
            const details = try std.fmt.allocPrint(self.allocator, "Task {d} ('{s}') has large description ({d:.2} MB)", .{ row.id, row.title, size_mb });

            try warning_list.append(types.HealthIssue{
                .check_name = try self.allocator.dupe(u8, "large_description"),
                .message = try self.allocator.dupe(u8, "Task description exceeds 1MB"),
                .details = details,
            });
        }
    }
};
