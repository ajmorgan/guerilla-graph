//! SQL Executor: Clean abstraction over SQLite C API
//!
//! Eliminates prepare/bind/step/finalize boilerplate with type-safe API.
//! Uses Zig comptime reflection for parameter binding and result extraction.

const std = @import("std");
const c_imports = @import("c_imports.zig");
const c = c_imports.c;

// Re-export C types and functions for external use (especially tests)
pub const c_sqlite3 = c.sqlite3;
pub const c_sqlite3_stmt = c.sqlite3_stmt;
pub const sqlite3_open = c.sqlite3_open;
pub const sqlite3_close = c.sqlite3_close;
pub const SQLITE_OK = c.SQLITE_OK;

/// Expected result from sqlite3_step().
const StepExpectation = enum { expect_done, expect_row, expect_row_or_done };

/// Executor wraps SQLite database handle for clean query execution.
/// Does not own the database handle - lifetime managed by Storage.
pub const Executor = struct {
    database: *c.sqlite3,

    /// Initialize executor with database handle.
    /// Database must remain valid for Executor lifetime.
    pub fn init(database: *c.sqlite3) Executor {
        // Assertions: Validate inputs
        const executor = Executor{ .database = database };
        std.debug.assert(@intFromPtr(executor.database) != 0); // Database pointer must be valid

        return executor;
    }

    /// Prepare SQL statement for execution.
    /// Caller must finalize statement when done (use defer).
    fn prepare(self: *Executor, sql: []const u8) !*c.sqlite3_stmt {
        // Assertions: Validate inputs
        std.debug.assert(sql.len > 0);
        std.debug.assert(sql.len < 10000); // Reasonable SQL length limit

        var statement: ?*c.sqlite3_stmt = null;
        const result = c.sqlite3_prepare_v2(
            self.database,
            sql.ptr,
            @intCast(sql.len),
            &statement,
            null,
        );

        if (result != c.SQLITE_OK) {
            return error.PrepareStatementFailed;
        }

        // Assertion: Success means we have valid statement
        std.debug.assert(statement != null);

        return statement.?;
    }

    /// Finalize prepared statement and free resources.
    fn finalize(self: *Executor, statement: *c.sqlite3_stmt) void {
        // Rationale: Finalize cannot fail per SQLite docs, but returns status code.
        // We ignore the return value as cleanup must always proceed.
        _ = self;
        _ = c.sqlite3_finalize(statement);
    }

    /// Execute prepared statement step.
    /// Returns true if row available (SQLITE_ROW), false if done (SQLITE_DONE).
    fn step(self: *Executor, statement: *c.sqlite3_stmt, expectation: StepExpectation) !bool {
        _ = self;
        const result = c.sqlite3_step(statement);

        return switch (expectation) {
            .expect_done => blk: {
                if (result != c.SQLITE_DONE) return error.StepFailed;
                break :blk false;
            },
            .expect_row => blk: {
                if (result != c.SQLITE_ROW) return error.StepFailed;
                break :blk true;
            },
            .expect_row_or_done => blk: {
                if (result != c.SQLITE_ROW and result != c.SQLITE_DONE) {
                    return error.StepFailed;
                }
                break :blk result == c.SQLITE_ROW;
            },
        };
    }

    /// Bind parameters to prepared statement using compile-time reflection.
    /// Accepts anytype tuple and binds each field sequentially (1-indexed).
    /// Rationale: Compile-time type safety with zero runtime overhead.
    pub fn bindParams(self: *Executor, statement: *c.sqlite3_stmt, params: anytype) !void {
        _ = self;
        // Assertions: Validate inputs
        std.debug.assert(@intFromPtr(statement) != 0); // Statement pointer must be valid

        const ParamsType = @TypeOf(params);
        const params_info = @typeInfo(ParamsType);

        // Compile-time check: params must be a tuple or struct
        const fields = switch (params_info) {
            .@"struct" => |struct_info| struct_info.fields,
            else => @compileError("bindParams expects a tuple or struct, got: " ++ @typeName(ParamsType)),
        };

        // Assertion: Validate field count is reasonable
        std.debug.assert(fields.len < 100); // Reasonable parameter limit

        // Rationale: Verify bound parameter count matches SQL placeholders.
        // Catches mismatch between params tuple and SQL at runtime.
        const expected_params = c.sqlite3_bind_parameter_count(statement);
        std.debug.assert(fields.len == @as(usize, @intCast(expected_params)));

        // Bind each field sequentially using 1-based indexing
        inline for (fields, 0..) |field, i| {
            const index: c_int = @intCast(i + 1);
            try bindParam(statement, index, @field(params, field.name));
        }
    }

    /// Bind a single parameter value to prepared statement.
    /// Supports: u32, i64, []const u8, and optional versions of these types.
    /// Rationale: Centralized type dispatch for parameter binding.
    fn bindParam(statement: *c.sqlite3_stmt, index: c_int, value: anytype) !void {
        // Assertions: Validate inputs
        std.debug.assert(index > 0); // SQLite uses 1-based indexing
        std.debug.assert(@intFromPtr(statement) != 0); // Statement pointer must be valid

        const ValueType = @TypeOf(value);
        const value_info = @typeInfo(ValueType);

        switch (value_info) {
            .int => {
                if (ValueType == u32) {
                    const result = c.sqlite3_bind_int(statement, index, @intCast(value));
                    if (result != c.SQLITE_OK) return error.BindFailed;
                } else if (ValueType == i64) {
                    const result = c.sqlite3_bind_int64(statement, index, value);
                    if (result != c.SQLITE_OK) return error.BindFailed;
                } else {
                    @compileError("Unsupported integer type: " ++ @typeName(ValueType));
                }
            },
            .pointer => |ptr_info| {
                // Handle both []const u8 slices and *const [N:0]u8 string literals
                switch (ptr_info.size) {
                    .slice => {
                        if (ptr_info.child == u8) {
                            const result = c.sqlite3_bind_text(
                                statement,
                                index,
                                value.ptr,
                                @intCast(value.len),
                                null,
                            );
                            if (result != c.SQLITE_OK) return error.BindFailed;
                        } else {
                            @compileError("Unsupported slice type: " ++ @typeName(ValueType));
                        }
                    },
                    .one => {
                        // String literal like "test" is *const [N:0]u8
                        const Child = ptr_info.child;
                        const child_info = @typeInfo(Child);
                        if (child_info == .array and child_info.array.child == u8) {
                            const str_slice: []const u8 = value;
                            const result = c.sqlite3_bind_text(
                                statement,
                                index,
                                str_slice.ptr,
                                @intCast(str_slice.len),
                                null,
                            );
                            if (result != c.SQLITE_OK) return error.BindFailed;
                        } else {
                            @compileError("Unsupported pointer type: " ++ @typeName(ValueType));
                        }
                    },
                    else => @compileError("Unsupported pointer size: " ++ @typeName(ValueType)),
                }
            },
            .optional => {
                if (value) |v| {
                    try bindParam(statement, index, v);
                } else {
                    const result = c.sqlite3_bind_null(statement, index);
                    if (result != c.SQLITE_OK) return error.BindFailed;
                }
            },
            else => @compileError("Unsupported parameter type: " ++ @typeName(ValueType)),
        }
    }

    /// Extract a single row from query result into struct using reflection.
    /// Maps SQLite columns to struct fields by position (0-indexed columns).
    /// Allocator is used for string fields - caller must deinit result.
    /// Rationale: Automatic mapping eliminates manual column extraction boilerplate.
    pub fn extractRow(
        self: *Executor,
        comptime T: type,
        allocator: std.mem.Allocator,
        statement: *c.sqlite3_stmt,
    ) !T {
        _ = self;
        // Assertions: Validate inputs
        std.debug.assert(@intFromPtr(statement) != 0); // Statement pointer must be valid

        const type_info = @typeInfo(T);
        const fields = switch (type_info) {
            .@"struct" => |struct_info| struct_info.fields,
            else => @compileError("extractRow expects struct type, got: " ++ @typeName(T)),
        };
        std.debug.assert(fields.len > 0); // Must have at least one field

        var result: T = undefined;
        var allocated_strings: std.ArrayList([]const u8) = .empty;
        defer {
            // Clean up on error (successful path transfers ownership to caller)
            for (allocated_strings.items) |str| {
                allocator.free(str);
            }
            allocated_strings.deinit(allocator);
        }

        inline for (fields, 0..) |field, i| {
            const column_index: c_int = @intCast(i);
            @field(result, field.name) = try extractColumn(
                field.type,
                allocator,
                statement,
                column_index,
                &allocated_strings,
            );
        }

        // Success: Transfer ownership, prevent cleanup
        allocated_strings.clearRetainingCapacity();
        return result;
    }

    /// Extract a single column value from current row.
    /// Supports: u32, i64, []const u8, and optional versions of these types.
    /// Rationale: Centralized type dispatch for column extraction.
    fn extractColumn(
        comptime T: type,
        allocator: std.mem.Allocator,
        statement: *c.sqlite3_stmt,
        column_index: c_int,
        allocated_strings: *std.ArrayList([]const u8),
    ) !T {
        // Assertions: Validate inputs
        std.debug.assert(column_index >= 0);
        std.debug.assert(@intFromPtr(statement) != 0); // Statement pointer must be valid

        const type_info = @typeInfo(T);

        switch (type_info) {
            .int => {
                if (T == u32) {
                    const value = c.sqlite3_column_int(statement, column_index);
                    return @intCast(value);
                } else if (T == i64) {
                    return c.sqlite3_column_int64(statement, column_index);
                } else {
                    @compileError("Unsupported integer type: " ++ @typeName(T));
                }
            },
            .pointer => |ptr_info| {
                if (ptr_info.size == .slice and ptr_info.child == u8) {
                    const text_ptr = c.sqlite3_column_text(statement, column_index);
                    const text_span = std.mem.span(text_ptr);
                    const text_copy = try allocator.dupe(u8, text_span);
                    try allocated_strings.append(allocator, text_copy);
                    return text_copy;
                } else {
                    @compileError("Unsupported pointer type: " ++ @typeName(T));
                }
            },
            .optional => |opt_info| {
                const column_type = c.sqlite3_column_type(statement, column_index);
                if (column_type == c.SQLITE_NULL) {
                    return null;
                }
                return try extractColumn(
                    opt_info.child,
                    allocator,
                    statement,
                    column_index,
                    allocated_strings,
                );
            },
            else => @compileError("Unsupported column type: " ++ @typeName(T)),
        }
    }

    // ========================================================================
    // Public API Methods (Phase 3)
    // ========================================================================

    /// Execute SQL statement with no result rows (INSERT, UPDATE, DELETE).
    /// Rationale: Simplest use case, foundation for queryOne/queryAll.
    /// Asserts >= 0 changes (may be 0 for no-op updates).
    pub fn exec(self: *Executor, sql: []const u8, params: anytype) !void {
        std.debug.assert(sql.len > 0);

        const statement = try self.prepare(sql);
        defer self.finalize(statement);

        try self.bindParams(statement, params);
        _ = try self.step(statement, .expect_done);

        std.debug.assert(c.sqlite3_changes(self.database) >= 0);
    }

    /// Query single row, return null if not found.
    /// Returns ?T (null for no rows). Matches pattern from storage.zig for optional results.
    pub fn queryOne(
        self: *Executor,
        comptime T: type,
        allocator: std.mem.Allocator,
        sql: []const u8,
        params: anytype,
    ) !?T {
        std.debug.assert(sql.len > 0);

        const statement = try self.prepare(sql);
        defer self.finalize(statement);

        try self.bindParams(statement, params);

        const has_row = try self.step(statement, .expect_row_or_done);
        if (!has_row) return null;

        return try self.extractRow(T, allocator, statement);
    }

    /// Query multiple rows, return owned slice.
    /// Accumulates results in ArrayList, returns owned slice.
    /// Matches ArrayList pattern from storage.zig:863-952.
    pub fn queryAll(
        self: *Executor,
        comptime T: type,
        allocator: std.mem.Allocator,
        sql: []const u8,
        params: anytype,
    ) ![]T {
        std.debug.assert(sql.len > 0);

        const statement = try self.prepare(sql);
        defer self.finalize(statement);

        try self.bindParams(statement, params);

        var results: std.ArrayList(T) = .empty;
        errdefer {
            for (results.items) |*item| {
                item.deinit(allocator);
            }
            results.deinit(allocator);
        }

        while (true) {
            const has_row = try self.step(statement, .expect_row_or_done);
            if (!has_row) break;

            const row = try self.extractRow(T, allocator, statement);
            try results.append(allocator, row);
        }

        return try results.toOwnedSlice(allocator);
    }

    /// Begin a transaction for atomic multi-operation changes.
    pub fn beginTransaction(self: *Executor) !void {
        std.debug.assert(@intFromPtr(self.database) != 0);

        const result = c.sqlite3_exec(self.database, "BEGIN TRANSACTION", null, null, null);
        if (result != c.SQLITE_OK) {
            return error.ExecFailed;
        }

        std.debug.assert(result == c.SQLITE_OK);
    }

    /// Commit the current transaction, making changes permanent.
    pub fn commit(self: *Executor) !void {
        std.debug.assert(@intFromPtr(self.database) != 0);

        const result = c.sqlite3_exec(self.database, "COMMIT", null, null, null);
        if (result != c.SQLITE_OK) {
            return error.ExecFailed;
        }

        std.debug.assert(result == c.SQLITE_OK);
    }

    /// Rollback the current transaction, discarding all changes.
    /// Safe to call even if no transaction is active (no-op).
    pub fn rollback(self: *Executor) void {
        _ = c.sqlite3_exec(self.database, "ROLLBACK", null, null, null);
    }
};
