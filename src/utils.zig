const std = @import("std");
const types = @import("types.zig");

// Timestamp validation constants (Unix epoch seconds).
// Rationale: Sanity checks to catch obviously wrong timestamps.
const MIN_VALID_TIMESTAMP: i64 = 1577836800; // 2020-01-01 00:00:00 UTC
const MAX_VALID_TIMESTAMP: i64 = 4102444800; // 2100-01-01 00:00:00 UTC

/// Validates that an ID conforms to kebab-case format.
/// Kebab-case allows only lowercase letters and hyphens (no leading/trailing hyphens).
/// Examples: "auth", "tech-debt", "my-feature"
///
/// Returns error.EmptyId if the ID string is empty.
/// Returns error.InvalidKebabCase if the ID contains invalid characters,
/// starts/ends with a hyphen, or uses uppercase letters, numbers, or special characters.
pub fn validateKebabCase(id: []const u8) !void {
    // Rationale: Check for empty first before asserting, since empty is a user error
    // not a programmer error. The assertion catches programmer bugs (passing empty
    // without checking), but the error return handles user input gracefully.
    if (id.len == 0) return error.EmptyId;

    // Assertions: Preconditions (after validation)
    std.debug.assert(id.len > 0);

    // Rationale: Leading or trailing hyphens are invalid to prevent ambiguity
    // with command-line flags and maintain clean visual appearance.
    if (id[0] == '-') return error.InvalidKebabCase;
    if (id[id.len - 1] == '-') return error.InvalidKebabCase;

    // Rationale: Kebab-case allows only lowercase letters and hyphens.
    // This ensures consistent, readable plan IDs (auth, tech-debt).
    // Leading/trailing hyphens are invalid to prevent ambiguity with command-line flags
    // and to maintain clean visual appearance in task IDs.
    for (id) |character| {
        if (!std.ascii.isLower(character) and character != '-') {
            return error.InvalidKebabCase;
        }
    }

    // Assertions: Postconditions (validated)
    std.debug.assert(id[0] != '-');
    std.debug.assert(id[id.len - 1] != '-');
}

/// Formats a task ID from a plan ID and task number.
/// Format: "{plan_id}:{number}" (e.g., "auth:001", "tech-debt:042")
/// Number is zero-padded to 3 digits.
pub fn formatTaskId(allocator: std.mem.Allocator, plan_id: []const u8, number: u32) ![]u8 {
    // Assertions: Preconditions
    std.debug.assert(plan_id.len > 0);
    std.debug.assert(plan_id.len <= types.MAX_PLAN_ID_LENGTH);
    std.debug.assert(number > 0);
    std.debug.assert(number <= 999);

    // Rationale: Using allocPrint for clean string formatting with zero-padding.
    // The format string "{s}:{d:0>3}" produces plan:NNN format where N is zero-padded.
    // This ensures consistent visual alignment and sortability of task IDs.
    const task_id = try std.fmt.allocPrint(allocator, "{s}:{d:0>3}", .{ plan_id, number });

    // Assertion: Format correct (must contain colon separator)
    std.debug.assert(std.mem.indexOf(u8, task_id, ":") != null);
    std.debug.assert(task_id.len >= 5); // Minimum: "a:001"

    return task_id;
}

/// Parses a task ID into its plan ID and task number components.
/// Input format: "{plan_id}:{number}" (e.g., "auth:001")
/// Returns a struct with plan_id slice and number as u32.
///
/// Returns error.InvalidTaskId if the task ID is missing a colon separator,
/// has empty plan or number segments, or is otherwise malformed.
/// Returns error.InvalidCharacter if the number portion contains non-numeric characters.
pub fn parseTaskId(task_id: []const u8) !struct { plan_id: []const u8, number: u32 } {
    // Assertions: Preconditions
    std.debug.assert(task_id.len > 0);

    const colon_index = std.mem.indexOf(u8, task_id, ":") orelse return error.InvalidTaskId;

    // Rationale: Task IDs must have content on both sides of the colon.
    // Empty plan or number segments are invalid.
    if (colon_index == 0) return error.InvalidTaskId;
    if (colon_index == task_id.len - 1) return error.InvalidTaskId;

    const plan_id = task_id[0..colon_index];
    const number_string = task_id[colon_index + 1 ..];
    const number = try std.fmt.parseInt(u32, number_string, 10);

    // Assertions: Postconditions
    std.debug.assert(plan_id.len > 0);
    std.debug.assert(number > 0);
    std.debug.assert(number <= 999);

    return .{ .plan_id = plan_id, .number = number };
}

/// Parses a task ID flexibly, accepting either numeric or formatted input.
/// Tries numeric parse first (fast path for CLI convenience: "1", "42").
/// Falls back to formatted parse if numeric fails (handles "plan:001" format).
/// Returns just the task number as u32.
///
/// Examples:
///   "42" -> 42
///   "auth:001" -> 1
///   "tech-debt:123" -> 123
///
/// Returns error.InvalidTaskId if input cannot be parsed as either format.
/// Returns error.InvalidCharacter if the number portion is malformed.
pub fn parseTaskIdFlexible(task_id: []const u8) !u32 {
    // Assertions: Preconditions
    std.debug.assert(task_id.len > 0);

    // Rationale: Try numeric parse first (fast path) for CLI convenience.
    // Users can type "gg start 1" instead of "gg start auth:001".
    if (std.fmt.parseInt(u32, task_id, 10)) |number| {
        // Assertions: Postconditions (numeric path)
        std.debug.assert(number > 0);
        return number;
    } else |_| {
        // Rationale: Numeric parse failed, try formatted parse (plan:number).
        // This handles the full task ID format like "auth:001" or "tech-debt:042".
        const parsed = try parseTaskId(task_id);

        // Assertions: Postconditions (formatted path)
        std.debug.assert(parsed.number > 0);
        return parsed.number;
    }
}

/// Parses a task ID into a TaskIdInput union, accepting either numeric or formatted input.
/// Tries numeric parse first (fast path for backwards compatibility: "1", "42").
/// Falls back to formatted parse if numeric fails (handles "plan:001" format).
/// Returns a TaskIdInput union that preserves the full parsed information.
///
/// Examples:
///   "42" -> .{ .internal_id = 42 }
///   "auth:001" -> .{ .plan_task = .{ .slug = "auth", .number = 1 } }
///   "tech-debt:123" -> .{ .plan_task = .{ .slug = "tech-debt", .number = 123 } }
///
/// Returns error.InvalidTaskId if input cannot be parsed as either format.
/// Returns error.InvalidCharacter if the number portion is malformed.
pub fn parseTaskInput(input: []const u8) !types.TaskIdInput {
    // Assertions: Preconditions
    std.debug.assert(input.len > 0);

    // Rationale: Try numeric parse first (backwards compatibility path).
    // Users can type "gg start 1" to reference internal task ID 1.
    if (std.fmt.parseInt(u32, input, 10)) |id| {
        // Assertions: Postconditions (numeric path)
        std.debug.assert(id > 0);
        return .{ .internal_id = id };
    } else |_| {
        // Rationale: Numeric parse failed, try formatted parse (slug:number).
        // This handles the full task ID format like "auth:001" or "tech-debt:042".
        const parsed = try parseTaskId(input);

        // Assertions: Postconditions (formatted path)
        std.debug.assert(parsed.plan_id.len > 0);
        std.debug.assert(parsed.number > 0);

        return .{ .plan_task = .{ .slug = parsed.plan_id, .number = parsed.number } };
    }
}

/// Returns the current Unix timestamp in seconds.
/// Uses i64 to match SQLite's INTEGER type for timestamp columns.
pub fn unixTimestamp() i64 {
    // Rationale: Using std.posix.clock_gettime with CLOCK.REALTIME to get wall-clock time.
    // REALTIME clock returns time since Unix epoch (1970-01-01 00:00:00 UTC).
    // This matches SQLite's unixepoch() function and ensures consistency
    // across database and application timestamps.
    const timespec = std.posix.clock_gettime(std.posix.CLOCK.REALTIME) catch |err| {
        // Rationale: clock_gettime with CLOCK.REALTIME should never fail on modern systems.
        // If it does, this indicates a catastrophic system error (corrupted kernel state).
        // We panic because the application cannot function without accurate timestamps.
        std.debug.panic("Failed to get current time: {}", .{err});
    };

    const timestamp = timespec.sec;

    // Assertions: Postconditions (sanity checks)
    // Timestamp should be positive (after 1970-01-01)
    std.debug.assert(timestamp > 0);
    // Timestamp should be reasonable (sanity check for obviously wrong values).
    std.debug.assert(timestamp > MIN_VALID_TIMESTAMP);
    std.debug.assert(timestamp < MAX_VALID_TIMESTAMP);

    return timestamp;
}
