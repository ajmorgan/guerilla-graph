# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Guerilla Graph (gg)** is a dependency-aware task tracker for parallel agent coordination, written in Zig. It provides a CLI tool for managing features and tasks with dependency tracking, cycle detection, and parallel execution support.

**Key characteristics:**
- Language: Zig (minimum version 0.16.0-dev.1484+d0ba6642b)
- Storage: SQLite (single file, single machine)
- Scale: 100s-1000s of tasks, 2-10 agents
- Performance target: <1ms for single operations, <5ms for graph queries

## Build Commands

### Building the Project
```bash
# Build the executable (outputs to zig-out/bin/gg)
zig build

# Note: Binary is invoked as 'gg' throughout documentation
# The full name 'guerilla_graph' may also be available

# Run the application
zig build run

# Run with arguments
zig build run -- arg1 arg2

# Build for specific target/optimization
zig build -Dtarget=x86_64-linux -Doptimize=ReleaseFast
```

### Testing
```bash
# Run all tests (both module and executable tests)
zig build test

# Run tests with fuzz testing
zig build test --fuzz
```

### Build System Details
- Build configuration: `build.zig`
- Package configuration: `build.zig.zon`
- The project exposes a `guerilla_graph` module (root: `src/root.zig`)
- The CLI executable is built from `src/main.zig` and imports the module
- Test executables are created for both the module and the CLI

## Architecture

### Module Structure

The system follows an aggregation pattern with clear separation of concerns:

**Storage modules (functional split):**
- `task_storage.zig` - Aggregator
  - `task_storage_crud.zig` - CRUD operations
  - `task_storage_lifecycle.zig` - Lifecycle operations
  - `task_storage_queries.zig` - Query operations

**Command modules (command-per-file):**
- `commands/task.zig` - Aggregator
  - `commands/task_new.zig`
  - `commands/task_start.zig`
  - `commands/task_complete.zig`
  - `commands/task_show.zig`
  - `commands/task_update.zig`
  - `commands/task_delete.zig`
  - `commands/task_list.zig`

**Format modules (resource-type split):**
- `format.zig` - Aggregator
  - `format_task.zig` - Task formatters
  - `format_plan.zig` - Plan formatters
  - `format_system.zig` - System formatters
  - `format_common.zig` - Shared helpers

All aggregators use re-export pattern for backward compatibility (zero breaking changes).

### Core Data Model

**Two-level hierarchy:**
- **Plans** (top-level containers): Organizational units with kebab-case slugs (auth, payments, tech-debt, etc.)
- **Tasks** (work items under plans): Tasks with IDs in format `<slug>:NNN` (auth:001, auth:002, etc.)

**Key concepts:**
- Plans use INTEGER primary keys internally with TEXT slugs for user display
- Tasks are numbered per-plan (auth:001, auth:002, payments:001, payments:002)
- Task IDs are formatted as `{slug}:{plan_task_number:0>3}` (e.g., auth:001)
- Tasks can depend on other tasks (dependencies use internal INTEGER IDs)
- Dependencies form a directed acyclic graph (DAG) - cycles are prevented
- Task statuses: `open`, `in_progress`, `completed`
- Tasks are "ready" when all blockers are completed (unblocked for parallel execution)
- Task descriptions support YAML frontmatter + Markdown for rich implementation instructions
- All tasks must belong to a plan (plan_id is NOT NULL)
- Cascade deletion: When a plan is deleted, all its tasks are permanently deleted (ON DELETE CASCADE)
- Per-plan task numbering uses atomic counter stored in plans.task_counter
- Plan slugs can be renamed without breaking foreign key relationships (references use INTEGER IDs)
- **File-level serialization**: Tasks modifying the same file must form dependency chains to prevent concurrent modification conflicts (critical for parallel agent execution)

### Database Schema

SQLite database with three main tables:

**1. plans** - Top-level organizational containers:
```sql
CREATE TABLE plans (
    id INTEGER PRIMARY KEY AUTOINCREMENT,  -- Internal ID (fast joins)
    slug TEXT UNIQUE NOT NULL,             -- User-facing ID: "auth", "payments"
    title TEXT NOT NULL CHECK(length(title) > 0 AND length(title) <= 500),
    description TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL DEFAULT 'open' CHECK(status IN ('open', 'in_progress', 'completed')),
    task_counter INTEGER NOT NULL DEFAULT 0,  -- Atomic counter for per-plan task numbering
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    execution_started_at INTEGER,
    completed_at INTEGER
);
CREATE INDEX idx_plans_slug ON plans(slug);
CREATE INDEX idx_plans_status ON plans(status);
```

**2. tasks** - Work items with per-plan numbering:
```sql
CREATE TABLE tasks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,  -- Internal ID (for dependencies)
    plan_id INTEGER NOT NULL,              -- FK to plans.id
    plan_task_number INTEGER NOT NULL,     -- Per-plan number: 1, 2, 3...
    title TEXT NOT NULL CHECK(length(title) > 0 AND length(title) <= 500),
    description TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL DEFAULT 'open' CHECK(status IN ('open', 'in_progress', 'completed')),
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    started_at INTEGER,
    completed_at INTEGER,
    FOREIGN KEY (plan_id) REFERENCES plans(id) ON DELETE CASCADE,
    UNIQUE (plan_id, plan_task_number)
);
CREATE INDEX idx_tasks_status ON tasks(status);
CREATE INDEX idx_tasks_plan_id ON tasks(plan_id);
CREATE INDEX idx_tasks_status_plan ON tasks(status, plan_id);
CREATE INDEX idx_tasks_plan_created ON tasks(plan_id, created_at ASC);
```

**3. dependencies** - Task blocking relationships:
```sql
CREATE TABLE dependencies (
    task_id INTEGER NOT NULL,              -- Task that is blocked
    blocks_on_id INTEGER NOT NULL,         -- Task that blocks
    created_at INTEGER NOT NULL,
    PRIMARY KEY (task_id, blocks_on_id),
    FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE,
    FOREIGN KEY (blocks_on_id) REFERENCES tasks(id) ON DELETE CASCADE,
    CHECK (task_id != blocks_on_id)
);
CREATE INDEX idx_dependencies_task ON dependencies(task_id);
CREATE INDEX idx_dependencies_blocks ON dependencies(blocks_on_id);
```

**Key design decisions:**
- **INTEGER PKs with TEXT slugs**: Fast joins (INTEGER comparison) with user-friendly identifiers
- **Per-plan task numbering**: Each plan has its own sequence (auth:001, auth:002, payments:001)
- **Atomic counter**: plans.task_counter eliminates race conditions in ID generation
- **Immutable foreign keys**: Renaming plan slugs doesn't break task relationships
- **Foreign keys enforce referential integrity**: CASCADE deletes propagate properly
- **CHECK constraints enforce business rules**: status ↔ timestamp consistency
- **Indexes optimize queries**: Covering indexes for common access patterns (status+plan, plan+created)
- **Cycle detection uses recursive CTEs**: Prevent dependency graph corruption before insertion

### CLI Command Categories

The `gg` CLI uses a resource-oriented command structure with the pattern `gg <resource> <action>`:

1. **Plan management**: `plan new`, `plan show`, `plan ls`, `plan update`, `plan delete`
2. **Task management**:
   - Canonical forms: `task new`, `task start`, `task complete`, `task update`, `task show`, `task delete`, `task ls`
   - Shortcuts (aliases): `start`, `complete`, `show`, `update` (all map to `task <action>`)
   - Note: To reopen a completed task, use `task update <id> --status open`
3. **Dependency management**: `dep add`, `dep remove`, `dep blockers`, `dep dependents`
4. **Query shortcuts**: `ready`, `blocked`, `ls`
5. **System commands**: `init`, `workflow`, `doctor`, `help`

**Performance critical operations:**
- Ready tasks query (find unblocked work for agents)
- Cycle detection (prevent dependency graph corruption)
- Transitive blocker/dependent traversal

### AI Agent Workflow

The project includes slash commands for AI-assisted development with parallel agent execution.

**CRITICAL: Quality Gate Process**

Follow this sequence exactly - each step has quality gates that prevent technical debt:

```
1. /gg-plan-gen <feature-description>
   ↓
   Generates PLAN.md with phases and architecture
   ↓
2. /gg-plan-audit [PLAN.md]
   ↓
   Iteratively audits plan (max 5 iterations until no Critical/High issues)
   Quality check: Maintainability, Implementability, Correct file paths
   ↓
   ✅ Plan approved (no Critical/High issues)
   ↓
3. /gg-task-gen [PLAN.md]
   ↓
   Generates gg plan + tasks with full What/Why/Where/How context
   ↓
4. /gg-task-audit <plan-slug>
   ↓
   Iteratively audits ALL tasks in parallel (max 5 iterations)
   Quality check: Full Context, Implementability, Correctness, Dependencies
   ↓
   ✅ All tasks approved (no Critical/High issues)
   ↓
5. /gg-execute <plan-slug>
   ↓
   Parallel agent execution with compilation gates after each wave
```

**DO NOT skip audit steps** - they enforce Tiger Style's zero technical debt policy.

**Command Details**:

1. **`/gg-plan-gen <feature-description>`**
   - Input: Feature description text or path to spec file
   - Output: PLAN.md with phases, architecture, success criteria
   - Time: 10-30 minutes (includes codebase exploration)

2. **`/gg-plan-audit [PLAN.md]`**
   - Input: PLAN.md file (default if not specified)
   - Output: Iteratively refined PLAN.md
   - Checks: File paths exist, line numbers accurate, patterns verified
   - Converges when: No Critical/High issues remain (typically 2-3 iterations)
   - Time: 5-15 minutes per iteration

3. **`/gg-task-gen [PLAN.md]`**
   - Input: Audited PLAN.md
   - Output: gg plan + tasks with dependencies set up
   - Each task has: YAML frontmatter + What/Why/Where/How sections
   - File-level serialization: Automatically chains tasks modifying same file
   - Time: 15-30 minutes

4. **`/gg-task-audit <plan-slug>`**
   - Input: Plan slug (e.g., "tiger-refactor")
   - Output: Iteratively refined tasks
   - Checks: Parallel agents audit all tasks simultaneously
   - Verifies: Full context, correct file paths, clear instructions
   - Converges when: No Critical/High issues remain (typically 2-3 iterations)
   - Time: 10-20 minutes per iteration (parallelized)

5. **`/gg-execute <plan-slug>`**
   - Input: Audited plan slug
   - Output: Implemented feature with all tasks completed
   - Process: Finds ready work → spawns parallel agents → compiles → tests → closes tasks
   - Waves: Multiple waves until all tasks complete
   - Time: Varies by plan size (typically 30-90 minutes)

**Key Features**:
- **Parallel execution**: Multiple agents work on independent tasks simultaneously
- **Iterative auditing**: Plans and tasks refined until quality standards met (max 5 iterations)
- **File-level serialization**: Tasks modifying same file automatically serialized to prevent conflicts
- **Quality gates**: Each wave validated (compilation, tests) before task completion

**Quality Criteria** (enforced during audit):
- **Full Context**: Real file paths, line numbers, code snippets, rationale (What/Why/Where/How)
- **Implementability**: Clear, unambiguous step-by-step instructions
- **Maintainability**: SRP, DRY, no backwards compatibility tech debt, clean solutions
- **Correctness**: Verified file paths, accurate line numbers, real code patterns
- **Dependencies**: File-level serialization + phase dependencies for maximum parallelism

See `.claude/commands/README.md` for slash command details.

### Description Format

Tasks use a structured format with YAML frontmatter + What/Why/Where/How sections:

```markdown
---
complexity: moderate
language: zig
affected_components: [storage, types]
requires_review: true
automated_tests:
  - test "storage: create task with description"
validation_commands:
  - zig build test --test-filter "storage"
---

## What
Add task description field to storage layer with proper memory management

## Why
Tasks need rich context for agent execution. Current implementation only stores title.
This enables full implementation instructions without external documentation.

## Where
- `src/storage.zig:245` - Add description column to CREATE TABLE
- `src/storage.zig:312` - Update createTask to accept description
- `src/types.zig:95` - Add description field to Task struct

## How
### Step 1: Update Task type
**Current code** (`src/types.zig:95`):
```zig
pub const Task = struct {
    id: u32,
    title: []const u8,
    status: TaskStatus,
    // ...
};
```

**Change to**:
```zig
pub const Task = struct {
    id: u32,
    title: []const u8,
    description: []const u8,  // Add this field
    status: TaskStatus,
    // ...
};
```

**Rationale**: Description stored as UTF-8 string, follows existing title pattern

[... additional steps ...]

## Patterns to Follow
- Memory management: `src/storage.zig:156` - allocator.dupe pattern for strings
- SQL parameters: `src/storage.zig:289` - bind_text usage

## Validation
1. Verify compilation: `zig build`
2. Verify tests pass: `zig build test --test-filter "storage"`
3. Check no memory leaks in test allocator

## Success Criteria
- [ ] Task type includes description field
- [ ] Storage layer persists descriptions
- [ ] Memory properly managed (no leaks)
- [ ] Tests verify description round-trip
```

**Important:** This format is REQUIRED for all tasks. The YAML frontmatter provides metadata for agent execution, and the What/Why/Where/How structure ensures tasks have full context for implementation without external documentation.

## Development Guidelines

### Engineering Principles & Hooks

This project follows Tiger Style principles (see `TIGER_STYLE.md`) with engineering practices defined in `.claude/hooks/engineering_principles.md`.

**Key practices automatically loaded via hooks**:
- **code_exploration_and_planning**: Explore codebase systematically before changes
- **coding**: Safety (assertions, explicit types, 70-line functions), quality (SRP, DRY), documentation
- **naming**: Precise nouns/verbs, `snake_case` for functions, `PascalCase` for types
- **memory_and_resources**: RAII pattern, `defer` for cleanup, minimize scope
- **dependencies_and_tooling**: Zero dependencies policy (except Zig toolchain + system libraries)
- **technical_debt**: Zero technical debt policy - implement correctly the first time
- **test_organization**: Split by functional area (90-560 lines per test file)
- **tools**: Use agents for exploration (>3 files), work directly for focused edits

These principles are automatically injected into AI agent context via hooks.

### Zig-Specific Practices

1. **Memory management**: Use explicit allocators (e.g., `std.mem.Allocator`), avoid leaks
2. **Error handling**: Use Zig's error unions (`!Type`), propagate errors with `try`
3. **Testing**: Write tests in the same file using `test` blocks
4. **Build system**: Leverage `std.Build` DSL for defining build steps and dependencies
5. **Zig documentation**: Use zig-docs MCP server for builtin functions and standard library lookup

### Code Organization

- `main.zig`: CLI entry point with argument parsing
- `root.zig`: Library module root (public API for consumers)
- Keep modules focused and single-purpose
- Use explicit imports, avoid wildcards
- Follow Zig naming conventions (snake_case for functions, PascalCase for types)

### SQLite Integration

- Use C bindings via `@cImport(@cInclude("sqlite3.h"))`
- Prepare statements for reuse (performance optimization)
- Use transactions for multi-statement operations
- Close resources properly in `deinit` functions
- Leverage indexes for query performance

### Performance Considerations

- Target: <1ms for CRUD operations, <5ms for graph queries
- **INTEGER primary keys**: 20-40x faster joins than TEXT comparison at scale
- **Atomic counter**: O(1) task ID generation (single row update) vs O(log n) for MAX() approach
- Use prepared statements to avoid re-parsing SQL
- Limit recursive CTE depth (100 levels) to prevent pathological cases
- Exclude large descriptions from list queries (only include in `show` command)
- Index all foreign keys and commonly filtered columns
- Covering indexes for hot paths: (status, plan_id) and (plan_id, created_at DESC)

## Common Patterns

### Example Usage Session

```bash
# Initialize workspace
gg init

# Create plans (slugs are kebab-case identifiers)
gg plan new auth --title "Authentication System"
# Creates plan with slug "auth", internal ID assigned automatically

gg plan new payments --title "Payment Processing"
# Creates plan with slug "payments", internal ID assigned automatically

# Create tasks under plans (returns formatted IDs)
gg task new "Add login endpoint" --plan auth
# Output: Created task auth:001 (plan_id=1, plan_task_number=1)

gg task new "Add JWT middleware" --plan auth
# Output: Created task auth:002 (plan_id=1, plan_task_number=2)
gg dep add auth:002 --blocks-on auth:001

gg task new "Add tests" --plan auth
# Output: Created task auth:003 (plan_id=1, plan_task_number=3)
gg dep add auth:003 --blocks-on auth:002

gg task new "Stripe integration" --plan payments
# Output: Created task payments:001 (plan_id=2, plan_task_number=1)

# Find available work (displays formatted IDs)
gg ready
# Output:
#   ID         Plan      Title                      Created
#   ────────────────────────────────────────────────────────
#   auth:001   auth      Add login endpoint         2 hours ago
#   pay:001    payments  Stripe integration         30 mins ago

# Work on a task (accept formatted IDs)
gg task start auth:001      # System resolves to internal ID
gg task show auth:001       # Read implementation details
# ... do the work ...
gg task complete auth:001   # Mark as done

# Manage dependencies (use formatted IDs)
gg dep add auth:003 --blocks-on auth:002    # System resolves both to internal IDs
gg dep blockers auth:003                     # What's blocking this?
gg dep dependents auth:001                   # What will this unblock?

# Query system state (displays formatted IDs)
gg task ls --status in_progress           # What's being worked on?
gg blocked                                   # What's waiting?
gg ready                                     # What can be started?

# Backwards compatibility: internal IDs still work
gg task show 1              # Equivalent to auth:001 (if internal ID = 1)

# Health check
gg doctor
```

### Creating a New Module

1. Add source file to `src/`
2. Import in relevant files: `const module_name = @import("module_name.zig");`
3. Expose public API via `pub` declarations
4. Add tests in the same file

### Adding a New CLI Command

1. Parse command in `cli.zig` using resource-action pattern
2. Add high-level operation in `task_manager.zig`
3. Implement storage query in `storage.zig`
4. Add corresponding SQL query following existing patterns in `storage.zig`
5. Update help text in `src/help/` and usage examples

### Writing Tests

```zig
test "description" {
    const gpa = std.testing.allocator;
    // Setup
    var obj = try createObject(gpa);
    defer obj.deinit(gpa); // Always clean up!

    // Test
    try std.testing.expectEqual(expected, actual);
}
```

## References

- Zig build system documentation: Comments in `build.zig`
- Zig language reference: https://ziglang.org/documentation/master/
- Engineering principles: `.claude/hooks/engineering_principles.md` (coding standards, practices)
- Slash commands: `.claude/commands/` (gg-plan-gen, gg-task-gen, etc.)

## Tiger Style Intentional Exceptions

This section documents intentional deviations from Tiger Style guidelines with rationale.

### Use of `usize` for Loop Indices and Array Lengths

**Tiger Style Rule**: Use explicitly-sized types (`u32`, `i64`) instead of architecture-dependent types (`usize`, `isize`).

**Exception**: We use `usize` for:
- Loop indices when iterating over arrays/slices
- Array lengths and buffer sizes
- String lengths from `[]const u8`

**Rationale**: 
- `usize` semantically matches platform pointer width for indexing memory
- Zig's standard library APIs (ArrayList, slices, etc.) use `usize` for lengths
- Converting to `u32` would require many `@intCast` operations without safety benefit
- Arrays and strings are bounded by addressable memory, making `usize` the natural choice

**Examples**:
```zig
// Loop indices
for (items, 0..) |item, index| { // index is usize
    // ...
}

// Array lengths
const buffer_size: usize = 8192;
var buffer: [buffer_size]u8 = undefined;
```

**Locations**: `src/cli.zig`, `src/format.zig`, `src/commands/task.zig`, `src/commands/dep.zig`, `src/commands/plan.zig`, `src/storage.zig`

### Code Duplication in Time Formatting

**Tiger Style Rule**: Apply DRY principle - avoid code duplication.

**Exception**: Time formatting helpers (`formatDuration`, `formatRelativeTime`) are duplicated in:
- `src/commands/ready.zig`
- `src/commands/list.zig`

**Rationale**:
- Functions are small (~30-40 lines each) and stable
- Creating a shared module adds dependency complexity
- Each module can independently evolve its formatting needs
- Duplication is documented and intentional (noted in comments)

**Trade-off**: Simplicity and module independence over strict DRY compliance.

### Functions Slightly Over 70 Lines

**Tiger Style Rule**: Maximum 70 lines per function body (hard limit).

**Current Status**: All functions comply with the 70-line limit after Phase 1 refactoring.

**Note**: Previous exceptions included `handleTaskNew` (commands/task_new.zig) at 114 lines. After refactoring during tiger-refactor:004, the function was split into helper functions (`handleTaskNew_formatJson`, `handleTaskNew_formatText`), reducing the main function body to 63 lines (well under the 70-line limit).

## Agent Notes

- Use the `gg` alias rather than the fully qualified path (`zig-out/bin/gg`)
- Use the zig-docs MCP server for Zig-specific verification during audits