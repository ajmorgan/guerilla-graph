//! Tests for SQL Executor integration with types.Task (sql_executor.zig).
//!
//! Covers: Real-world usage with Task struct, JOINs, complex queries

const std = @import("std");
const guerilla_graph = @import("guerilla_graph");
const sql_executor = guerilla_graph.sql_executor;
const Executor = sql_executor.Executor;
const types = guerilla_graph.types;
const TaskStatus = types.TaskStatus;
const utils = guerilla_graph.utils;

// Use re-exported C types from sql_executor for type compatibility
const c_sqlite3 = sql_executor.c_sqlite3;
const sqlite3_open = sql_executor.sqlite3_open;
const sqlite3_close = sql_executor.sqlite3_close;
const SQLITE_OK = sql_executor.SQLITE_OK;

// Section 5: Integration with Real Types (types.Task)
// ============================================================================

test "Integration: Task struct with queryOne" {
    const allocator = std.testing.allocator;
    var database: ?*c_sqlite3 = null;
    const open_result = sqlite3_open(":memory:", &database);
    try std.testing.expectEqual(SQLITE_OK, open_result);
    defer _ = sqlite3_close(database);

    var executor = Executor.init(database.?);

    // Create tasks table matching schema
    try executor.exec(
        \\CREATE TABLE tasks (
        \\  id INTEGER PRIMARY KEY,
        \\  plan TEXT,
        \\  title TEXT NOT NULL,
        \\  description TEXT NOT NULL,
        \\  status TEXT NOT NULL,
        \\  created_at INTEGER NOT NULL,
        \\  updated_at INTEGER NOT NULL,
        \\  started_at INTEGER,
        \\  completed_at INTEGER
        \\)
    ,
        .{},
    );

    // Insert task
    const now = utils.unixTimestamp();
    try executor.exec(
        "INSERT INTO tasks VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        .{
            @as(u32, 1),
            "auth",
            "Implement login",
            "Add JWT-based authentication",
            "open",
            now,
            now,
            @as(?i64, null),
            @as(?i64, null),
        },
    );

    // Query using Task-like struct
    const TaskLike = struct {
        id: u32,
        plan: ?[]const u8,
        title: []const u8,
        description: []const u8,
        status: []const u8,
        created_at: i64,
        updated_at: i64,
        started_at: ?i64,
        completed_at: ?i64,

        pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
            if (self.plan) |p| alloc.free(p);
            alloc.free(self.title);
            alloc.free(self.description);
            alloc.free(self.status);
        }
    };

    var result = try executor.queryOne(
        TaskLike,
        allocator,
        "SELECT id, plan, title, description, status, created_at, updated_at, started_at, completed_at FROM tasks WHERE id = ?",
        .{@as(u32, 1)},
    );

    try std.testing.expect(result != null);
    if (result) |*task| {
        defer task.deinit(allocator);

        try std.testing.expectEqual(@as(u32, 1), task.id);
        try std.testing.expect(task.plan != null);
        try std.testing.expectEqualStrings("auth", task.plan.?);
        try std.testing.expectEqualStrings("Implement login", task.title);
        try std.testing.expectEqualStrings("Add JWT-based authentication", task.description);
        try std.testing.expectEqualStrings("open", task.status);
        try std.testing.expectEqual(now, task.created_at);
        try std.testing.expectEqual(now, task.updated_at);
        try std.testing.expectEqual(@as(?i64, null), task.started_at);
        try std.testing.expectEqual(@as(?i64, null), task.completed_at);
    }
}

test "Integration: Task struct with queryAll" {
    const allocator = std.testing.allocator;
    var database: ?*c_sqlite3 = null;
    const open_result = sqlite3_open(":memory:", &database);
    try std.testing.expectEqual(SQLITE_OK, open_result);
    defer _ = sqlite3_close(database);

    var executor = Executor.init(database.?);

    // Create tasks table
    try executor.exec(
        \\CREATE TABLE tasks (
        \\  id INTEGER PRIMARY KEY,
        \\  plan TEXT,
        \\  title TEXT NOT NULL,
        \\  description TEXT NOT NULL,
        \\  status TEXT NOT NULL,
        \\  created_at INTEGER NOT NULL,
        \\  updated_at INTEGER NOT NULL,
        \\  started_at INTEGER,
        \\  completed_at INTEGER
        \\)
    ,
        .{},
    );

    // Insert multiple tasks
    const now = utils.unixTimestamp();
    try executor.exec(
        "INSERT INTO tasks VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        .{ @as(u32, 1), "auth", "Task 1", "Desc 1", "open", now, now, @as(?i64, null), @as(?i64, null) },
    );
    try executor.exec(
        "INSERT INTO tasks VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        .{ @as(u32, 2), "payments", "Task 2", "Desc 2", "in_progress", now, now, now, @as(?i64, null) },
    );
    try executor.exec(
        "INSERT INTO tasks VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        .{ @as(u32, 3), "auth", "Task 3", "Desc 3", "completed", now, now, now, now },
    );

    const TaskLike = struct {
        id: u32,
        plan: ?[]const u8,
        title: []const u8,
        status: []const u8,

        pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
            if (self.plan) |p| alloc.free(p);
            alloc.free(self.title);
            alloc.free(self.status);
        }
    };

    // Query all tasks for a plan
    const results = try executor.queryAll(
        TaskLike,
        allocator,
        "SELECT id, plan, title, status FROM tasks WHERE plan = ? ORDER BY id",
        .{"auth"},
    );
    defer {
        for (results) |*task| {
            task.deinit(allocator);
        }
        allocator.free(results);
    }

    try std.testing.expectEqual(@as(usize, 2), results.len);

    try std.testing.expectEqual(@as(u32, 1), results[0].id);
    try std.testing.expectEqualStrings("auth", results[0].plan.?);
    try std.testing.expectEqualStrings("Task 1", results[0].title);
    try std.testing.expectEqualStrings("open", results[0].status);

    try std.testing.expectEqual(@as(u32, 3), results[1].id);
    try std.testing.expectEqualStrings("auth", results[1].plan.?);
    try std.testing.expectEqualStrings("Task 3", results[1].title);
    try std.testing.expectEqualStrings("completed", results[1].status);
}

test "Integration: Orphan tasks (plan = NULL)" {
    const allocator = std.testing.allocator;
    var database: ?*c_sqlite3 = null;
    const open_result = sqlite3_open(":memory:", &database);
    try std.testing.expectEqual(SQLITE_OK, open_result);
    defer _ = sqlite3_close(database);

    var executor = Executor.init(database.?);

    // Create tasks table
    try executor.exec(
        \\CREATE TABLE tasks (
        \\  id INTEGER PRIMARY KEY,
        \\  plan TEXT,
        \\  title TEXT NOT NULL,
        \\  description TEXT NOT NULL,
        \\  status TEXT NOT NULL
        \\)
    ,
        .{},
    );

    // Insert orphan task (plan = NULL)
    try executor.exec(
        "INSERT INTO tasks VALUES (?, ?, ?, ?, ?)",
        .{ @as(u32, 1), @as(?[]const u8, null), "Orphan task", "No plan assigned", "open" },
    );

    const TaskLike = struct {
        id: u32,
        plan: ?[]const u8,
        title: []const u8,

        pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
            if (self.plan) |p| alloc.free(p);
            alloc.free(self.title);
        }
    };

    var result = try executor.queryOne(
        TaskLike,
        allocator,
        "SELECT id, plan, title FROM tasks WHERE id = ?",
        .{@as(u32, 1)},
    );

    try std.testing.expect(result != null);
    if (result) |*task| {
        defer task.deinit(allocator);

        try std.testing.expectEqual(@as(u32, 1), task.id);
        try std.testing.expectEqual(@as(?[]const u8, null), task.plan);
        try std.testing.expectEqualStrings("Orphan task", task.title);
    }
}

test "Integration: Complex query with JOIN" {
    const allocator = std.testing.allocator;
    var database: ?*c_sqlite3 = null;
    const open_result = sqlite3_open(":memory:", &database);
    try std.testing.expectEqual(SQLITE_OK, open_result);
    defer _ = sqlite3_close(database);

    var executor = Executor.init(database.?);

    // Create tables
    try executor.exec(
        "CREATE TABLE tasks (id INTEGER PRIMARY KEY, plan TEXT, title TEXT)",
        .{},
    );
    try executor.exec(
        "CREATE TABLE dependencies (task_id INTEGER, blocks_on_id INTEGER)",
        .{},
    );

    // Insert data
    try executor.exec("INSERT INTO tasks VALUES (?, ?, ?)", .{ @as(u32, 1), "auth", "Task 1" });
    try executor.exec("INSERT INTO tasks VALUES (?, ?, ?)", .{ @as(u32, 2), "auth", "Task 2" });
    try executor.exec("INSERT INTO dependencies VALUES (?, ?)", .{ @as(u32, 2), @as(u32, 1) });

    const JoinResult = struct {
        task_id: u32,
        task_title: []const u8,
        blocker_id: u32,
        blocker_title: []const u8,

        pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
            alloc.free(self.task_title);
            alloc.free(self.blocker_title);
        }
    };

    var result = try executor.queryOne(
        JoinResult,
        allocator,
        \\SELECT
        \\  t.id as task_id,
        \\  t.title as task_title,
        \\  b.id as blocker_id,
        \\  b.title as blocker_title
        \\FROM dependencies d
        \\JOIN tasks t ON d.task_id = t.id
        \\JOIN tasks b ON d.blocks_on_id = b.id
        \\WHERE t.id = ?
    ,
        .{@as(u32, 2)},
    );

    try std.testing.expect(result != null);
    if (result) |*row| {
        defer row.deinit(allocator);

        try std.testing.expectEqual(@as(u32, 2), row.task_id);
        try std.testing.expectEqualStrings("Task 2", row.task_title);
        try std.testing.expectEqual(@as(u32, 1), row.blocker_id);
        try std.testing.expectEqualStrings("Task 1", row.blocker_title);
    }
}
