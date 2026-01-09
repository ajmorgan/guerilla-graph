# Guerilla Graph (gg)

A dependency-aware task tracker for parallel AI agent coordination, written in Zig.

## What is Guerilla Graph?

Guerilla Graph enables AI agents (like Claude Code) to work on complex features in parallel by:

- **Tracking tasks as a DAG** - Dependencies form a directed acyclic graph with cycle detection
- **Finding ready work** - The `gg ready` command returns unblocked tasks for parallel execution
- **Coordinating agents** - Multiple agents work simultaneously on independent tasks
- **Preventing conflicts** - File-level serialization ensures tasks modifying the same file don't run concurrently

## Quick Start

```bash
# Build
zig build

# Initialize workspace
gg init

# Create a plan (feature container)
gg new auth --title "Authentication System"

# Create tasks under the plan
gg new auth: --title "Add login endpoint"       # Creates auth:001
gg new auth: --title "Add JWT middleware"       # Creates auth:002
gg new auth: --title "Add tests"                # Creates auth:003

# Set up dependencies (auth:002 waits for auth:001)
gg dep add auth:002 --blocks-on auth:001
gg dep add auth:003 --blocks-on auth:002

# Find available work
gg ready

# Work on a task
gg start auth:001
# ... do the work ...
gg complete auth:001

# Now auth:002 becomes ready
gg ready
```

## Core Concepts

### Plans and Tasks

- **Plans**: Top-level containers with kebab-case slugs (`auth`, `payments`, `tech-debt`)
- **Tasks**: Work items with IDs in format `<slug>:NNN` (`auth:001`, `auth:002`)
- **Statuses**: `open` → `in_progress` → `completed`

### Dependencies

Tasks can depend on other tasks, forming a DAG:

```bash
# auth:002 waits for auth:001
gg dep add auth:002 --blocks-on auth:001

# View what blocks a task
gg dep blockers auth:003

# View what a task unblocks
gg dep dependents auth:001
```

### Ready Tasks

A task is "ready" when all its blockers are completed:

```bash
gg ready              # All ready tasks
gg ready auth         # Ready tasks in auth plan
gg ready --json       # JSON output for scripting
```

## CLI Commands

| Category           | Commands                                                  |
| ------------------ | --------------------------------------------------------- |
| **Smart Commands** | `new`, `show`, `update` (auto-detect plan vs task)        |
| **Task Shortcuts** | `start`, `complete`                                       |
| **Dependencies**   | `dep add`, `dep remove`, `dep blockers`, `dep dependents` |
| **Queries**        | `ready`, `blocked`, `ls`, `task ls`, `plan ls`            |
| **System**         | `init`, `workflow`, `doctor`, `help`                      |

All commands support `--json` for machine-readable output.

## Claude Code Integration

### Hooks

Guerilla Graph integrates with Claude Code through hooks in `.claude/settings.json`:

| Hook               | Trigger        | Purpose                              |
| ------------------ | -------------- | ------------------------------------ |
| `SessionStart`     | Session begins | Loads `gg workflow` context          |
| `UserPromptSubmit` | Every message  | Injects engineering principles       |
| `SubagentStart`    | Agent spawns   | Ensures agents follow same standards |

### Slash Commands

Five slash commands provide a quality-gated workflow:

```
/gg-plan-gen <feature>   → Generate PLAN.md from feature description
       ↓
/gg-plan-audit           → Iteratively audit plan (max 5 iterations)
       ↓
/gg-task-gen             → Create gg tasks with dependencies
       ↓
/gg-task-audit <slug>    → Audit all tasks in parallel (max 5 iterations)
       ↓
/gg-execute <slug>       → Execute with parallel agents + compilation gates
```

Each step has quality gates that prevent technical debt.

### Parallel Agent Execution

The `/gg-execute` command:
1. Finds ready tasks with `gg ready`
2. Spawns N agents (one per ready task)
3. Validates all work compiles
4. Closes tasks only if build passes
5. Repeats until all tasks complete

## Building

```bash
# Requirements
# - Zig 0.16.0-dev.1484 or later
# - SQLite (system library)

# Build
zig build

# Run tests
zig build test

# Build optimized
zig build -Doptimize=ReleaseFast
```

## Architecture

```
src/
├── main.zig              # CLI entry point
├── root.zig              # Library module root (public API)
├── cli.zig               # Command parsing
├── types.zig             # Task, Plan, Dependency structs
├── utils.zig             # Task ID parsing, kebab-case validation
├── c_imports.zig         # C bindings (SQLite)
├── storage.zig           # SQLite wrapper + schema
├── sql_executor.zig      # SQL execution layer
├── task_storage.zig      # Task storage aggregator
├── task_storage_crud.zig # Task CRUD operations
├── task_storage_lifecycle.zig  # Task start/complete
├── task_storage_queries.zig    # Task queries (ready, blocked)
├── plan_storage.zig      # Plan operations
├── deps_storage.zig      # Dependency operations
├── task_manager.zig      # Task orchestration
├── format.zig            # Output formatting aggregator
├── format_task.zig       # Task formatters
├── format_plan.zig       # Plan formatters
├── format_system.zig     # System formatters
├── format_common.zig     # Shared formatting helpers
├── health_check.zig      # Database health checks
├── commands/             # Command implementations
│   ├── task*.zig         # new, start, complete, show, update, delete, list
│   ├── plan.zig
│   ├── dep.zig
│   ├── ready.zig
│   └── ...
└── help/                 # Help text
    ├── help.zig          # Help system entry point
    └── content/          # Per-command help content
```

### Database Schema

SQLite with three tables:
- `plans` - Feature containers with slugs and atomic task counters
- `tasks` - Work items with per-plan numbering
- `dependencies` - Task blocking relationships (DAG edges)

Performance targets: <1ms for CRUD, <5ms for graph queries.

## Task Descriptions

Tasks support rich descriptions with YAML frontmatter:

```markdown
---
complexity: moderate
affected_components: [storage, types]
validation_commands:
  - zig build test
---

## What
Add description field to Task struct

## Why
Enable rich implementation context for agents

## Where
- src/types.zig:95 - Task struct definition
- src/storage.zig:245 - CREATE TABLE statement

## How
### Step 1: Update Task type
[Detailed implementation steps with code snippets]
```

## Engineering Principles

The project follows Tiger Style from TigerBeetle (see `TIGER_STYLE.md`):

## License

MIT
