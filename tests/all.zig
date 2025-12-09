//! Test suite entry point for Guerilla Graph.
//!
//! This file imports all test files to force test discovery.
//! The `_ = @import()` pattern inside a `test` block is essential—
//! without it, Zig's lazy evaluation will skip tests in imported files.

const std = @import("std");

test {
    // Force test discovery for all test files
    // Phase 2 migrations (uncomment as files are created)
    // OLD SCHEMA - Disabled during schema migration:
    // _ = @import("types_test.zig");
    _ = @import("utils_test.zig");
    _ = @import("cli_test.zig");
    // _ = @import("format_test.zig");  // OLD SCHEMA - Split into format_json_test.zig and format_text_test.zig
    _ = @import("format_json_test.zig");
    _ = @import("format_text_test.zig");
    // Task manager tests (split from task_manager_test.zig)
    _ = @import("task_manager_init_test.zig");
    _ = @import("task_manager_validation_test.zig");
    _ = @import("task_manager_error_test.zig");
    // _ = @import("help_test.zig");  // Phase 4.3: Merged into cli_test.zig
    // _ = @import("main_test.zig");  // Phase 4.2: Merged into cli_test.zig
    // _ = @import("root_test.zig");  // Phase 4.1: Deleted - empty placeholder (7 lines)
    // _ = @import("description_file_test.zig");  // Phase 4.4: Merged into utils_test.zig

    // Storage tests (split from storage_test.zig for better organization)
    _ = @import("storage_init_test.zig");
    // _ = @import("storage_plan_test.zig");  // OLD SCHEMA - Replaced by storage_plan_new_test.zig
    _ = @import("storage_plan_new_test.zig"); // NEW SCHEMA
    _ = @import("storage_stats_test.zig");
    // _ = @import("storage_task_crud_test.zig");  // OLD SCHEMA - Replaced by storage_task_crud_new_test.zig
    // _ = @import("storage_task_crud_new_test.zig"); // Phase 3.4: Split into 4 CRUD test files
    // NEW SCHEMA: Per-plan numbering CRUD tests (split by operation type - Phase 3.4)
    _ = @import("storage_task_create_test.zig");
    _ = @import("storage_task_retrieve_test.zig");
    _ = @import("storage_task_update_test.zig");
    _ = @import("storage_task_lifecycle_test.zig");
    _ = @import("storage_dependency_test.zig");
    // _ = @import("storage_task_query_test.zig");  // OLD SCHEMA - Incompatible with new schema (Task.plan field removed)
    // _ = @import("storage_task_query_new_test.zig"); // Phase 3.1: Split into 4 query test files
    // NEW SCHEMA: Per-plan numbering query tests (split by query type - Phase 3.1)
    _ = @import("storage_query_list_test.zig");
    _ = @import("storage_query_ready_test.zig");
    _ = @import("storage_query_blocked_test.zig");
    _ = @import("storage_query_stats_test.zig");
    // _ = @import("sql_executor_test.zig");  // OLD SCHEMA
    // SQL Executor tests (split from sql_executor_test.zig for better organization)
    _ = @import("sql_executor_basic_test.zig");
    _ = @import("sql_executor_binding_test.zig");
    _ = @import("sql_executor_extraction_test.zig");
    _ = @import("sql_executor_errors_test.zig");
    _ = @import("sql_executor_integration_test.zig");
    // NOTE: commands_test.zig has been split into per-command test files below
    _ = @import("benchmarks_test.zig");
    // _ = @import("performance_crud_test.zig");  // TODO: Fix u64/i64 type mismatch
    _ = @import("performance_stress_test.zig");
    _ = @import("performance_cycle_test.zig");

    // Integration tests (split from integration_test.zig)
    _ = @import("integration_basic_flows_test.zig");
    // _ = @import("integration_lifecycle_test.zig");  // Phase 3.3: Split into 3 lifecycle test files
    // Phase 3.3: Lifecycle tests split into 3 focused test files (Tiger Style: ≤620 lines)
    _ = @import("integration_task_lifecycle_test.zig");
    _ = @import("integration_dependency_graph_test.zig");
    _ = @import("integration_ready_blocked_test.zig");
    _ = @import("integration_error_test.zig");
    _ = @import("integration_system_test.zig");
    // _ = @import("integration_flexible_id_test.zig");  // Phase 3.2: Split into 3 flexible ID test files
    // Phase 3.2: Flexible ID tests split into 3 focused test files
    _ = @import("integration_flexible_id_parsing_test.zig");
    _ = @import("integration_flexible_id_task_test.zig");
    _ = @import("integration_flexible_id_dep_test.zig");

    // Command-specific test files (extracted from commands_test.zig)
    _ = @import("commands/plan_test.zig");
    _ = @import("commands/task_test.zig");
    // _ = @import("commands/ready_test.zig");  // Phase 4.5: Merged into storage_task_query_test.zig
    // _ = @import("commands/blocked_test.zig");  // Phase 4.8: Merged into commands/doctor_test.zig
    // _ = @import("commands_plan_parsing_test.zig");  // Phase 4.6: Merged into commands/plan_test.zig
    // _ = @import("commands_task_parsing_test.zig");  // Phase 4.7: Merged into commands/task_test.zig
    _ = @import("commands/doctor_test.zig");
    _ = @import("commands/init_test.zig");
}
