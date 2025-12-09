//! Top-level help content for Guerilla Graph CLI.
//!
//! This module contains the main help text displayed when running `gg help`
//! or `gg --help`. It provides an overview of all commands, global flags,
//! and quick-start examples.

/// Main help text for the Guerilla Graph CLI.
/// Displayed when running: gg help, gg --help, or gg with no arguments.
pub const help_text =
    \\Guerilla Graph (gg) - Dependency-aware task tracker for parallel agent coordination
    \\
    \\USAGE:
    \\  gg <command> [arguments] [flags]
    \\
    \\COMMANDS:
    \\
    \\Workflow Context:
    \\  workflow               Show workflow context for AI agents
    \\  help                   Show this help message
    \\
    \\Smart Commands (auto-detect plan vs task):
    \\  new <slug>             Create plan (e.g., gg new auth --title "Auth")
    \\  new <slug>:            Create task (e.g., gg new auth: --title "Login")
    \\  show <id>              Show plan (auth) or task (auth:001) details
    \\  update <id> [options]  Update plan or task properties
    \\
    \\Task Shortcuts:
    \\  start <task-id>        Mark task as in progress
    \\  complete <task-id>...  Mark task(s) as completed
    \\
    \\Dependency Management:
    \\  dep add <task-id> --blocks-on <task-id>
    \\                         Add a dependency (task waits for blocker)
    \\  dep remove <task-id> --blocks-on <task-id>
    \\                         Remove a dependency
    \\  dep blockers <task-id> Show what this task is waiting on (transitive)
    \\  dep dependents <task-id>
    \\                         Show what depends on this task (transitive)
    \\
    \\Query Commands:
    \\  ready [plan-slug]      Show unblocked tasks available for work
    \\  blocked [options]      Show tasks blocked by dependencies
    \\  ls [options]           Show hierarchical structure
    \\  task ls [options]      List tasks with filters (--status, --plan)
    \\  plan ls [options]      List all plans
    \\
    \\System Commands:
    \\  init [--force]         Initialize a new gg workspace
    \\  doctor                 Run health checks on database (11 checks)
    \\
    \\Explicit Commands (alternatives to smart commands):
    \\  plan new <slug>        Create plan explicitly
    \\  plan show <slug>       Show plan details
    \\  plan update <slug>     Update plan
    \\  plan delete <slug>     Delete plan and all tasks
    \\  task new --plan <slug> Create task explicitly
    \\  task show <id>         Show task details
    \\  task update <id>       Update task
    \\  task delete <id>       Delete task
    \\
    \\GLOBAL FLAGS:
    \\  --json                 Output in JSON format
    \\  --help                 Show help for specific command
    \\
    \\EXAMPLES:
    \\
    \\  Quick Start:
    \\    gg init
    \\    gg workflow
    \\    gg new auth --title "Authentication System"
    \\    gg new auth: --title "Add login endpoint"
    \\    gg ready
    \\
    \\  Basic Workflow (claim task, work, complete):
    \\    gg ready
    \\    gg start auth:001
    \\    gg show auth:001
    \\    # ... do the work ...
    \\    gg complete auth:001
    \\
    \\  Smart Commands (auto-detect plan vs task):
    \\    gg new auth --title "Auth"     # Creates plan (no colon)
    \\    gg new auth: --title "Login"   # Creates task (colon suffix)
    \\    gg show auth                   # Shows plan
    \\    gg show auth:001               # Shows task
    \\
    \\  Health Check:
    \\    gg doctor                      # Run 11 integrity checks
    \\
    \\TASK ID FORMAT:
    \\  Tasks are identified as <plan-slug>:NNN (e.g., auth:001, payments:003)
    \\  Per-plan numbering: Each plan has its own sequence starting at 001
    \\
    \\DEPENDENCY GRAPH:
    \\  - Tasks form a Directed Acyclic Graph (DAG)
    \\  - Cycle detection prevents circular dependencies
    \\  - Tasks are "ready" when all blockers are completed
    \\  - Use 'gg dep blockers' to trace transitive dependencies
    \\
    \\For command-specific help, run:
    \\  gg <resource> --help       (e.g., gg plan --help)
    \\  gg <resource> <action> --help
    \\                             (e.g., gg task new --help)
    \\
    \\For comprehensive tutorials and workflows:
    \\  gg workflow                (Shows agent workflow context)
    \\
    \\
;
