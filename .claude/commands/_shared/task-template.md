# Standard Task Description Template

Use this template to create consistent, high-quality task descriptions.

## Purpose

Provides standard format for gg task descriptions with:
- YAML frontmatter (metadata)
- What/Why/Where/How structure (implementation details)
- Code snippets from actual codebase
- Clear success criteria

---

## Template Structure

```markdown
---
complexity: trivial|simple|moderate|complex|very_complex
language: [zig|java|python|rust|etc]
affected_components: [component1, component2]
requires_review: true|false
files:
  - path: [file-path]
    action: modify|create|delete
    lines: [line-range]  # Optional: e.g., "100-150"
automated_tests:
  - [test name or description]
validation_commands:
  - [build/test command]
---

## What

[One-sentence description of specific implementation goal]

## Why

[Explanation of rationale]:
- What problem this solves
- How it fits into architecture
- Why this approach over alternatives

**Context**: [Optional - broader context from plan]

## Where

### Files to Modify:
- `[file-path]:[line-number]` - [Specific change description]
- `[file-path]:[line-number]` - [Specific change description]

### Files to Create:
- `[new-file-path]` - [Purpose and structure]

### Files to Delete:
- `[old-file-path]` - [Why being removed]

## How

### Step 1: [Clear step description]

**Current code** (`[file-path]:[line-number]`):
```[language]
[Actual code from codebase - use Read tool to get this]
```

**Change to**:
```[language]
[Modified code showing specific changes]
```

**Rationale**: [Why this specific change - architecture fit, performance, etc.]

### Step 2: [Next step description]

[Repeat pattern: current → change → rationale]

[Continue for all steps needed]

## Patterns to Follow

[Reference existing code patterns in codebase]:
- Similar implementation: `[file]:[line]` - [Why similar]
- Naming convention: `[file]:[line]` - [Pattern example]
- Error handling: `[file]:[line]` - [Pattern to follow]
- Memory management: `[file]:[line]` - [RAII pattern]

## Validation

After implementation, verify:
1. [Specific compilation check]: `[command]`
2. [Specific test scenario]: `[command with filter]`
3. [Specific integration check]: `[verification step]`

## Success Criteria

- [ ] [Specific, testable outcome]
- [ ] [Specific, testable outcome]
- [ ] [Specific, testable outcome]
- [ ] Follows SRP (single clear responsibility)
- [ ] Follows DRY (reuses existing patterns)
- [ ] No backwards compatibility tech debt
- [ ] Performance target met (if applicable)
```

---

## Field Definitions

### YAML Frontmatter Fields

**complexity**:
- `trivial`: <10 lines changed, simple edit
- `simple`: 10-50 lines, straightforward implementation
- `moderate`: 50-200 lines, some design needed
- `complex`: 200-500 lines, significant design
- `very_complex`: >500 lines, architectural changes

**language**: Programming language (zig, java, python, rust, typescript, etc.)

**affected_components**: List of modules/systems touched (e.g., [storage, types, cli])

**requires_review**: Boolean - does this need human review before implementation?

**files.path**: Relative path from project root

**files.action**:
- `modify`: Edit existing file
- `create`: Create new file
- `delete`: Remove file

**files.lines**: Optional line range affected (e.g., "100-150", "245")

**automated_tests**: List of test names that verify this change

**validation_commands**: Shell commands to verify success

---

## Section Guidelines

### What (1-2 sentences)

Specific implementation goal. Answer: "What are we building/changing?"

**Good**:
- "Add task description field to storage layer with proper memory management"
- "Create sql_executor_basic_test.zig by extracting Section 1 tests"

**Bad**:
- "Update the system" (too vague)
- "Make it work better" (not specific)

---

### Why (2-4 sentences)

Rationale and architecture fit. Answer: "Why this change? Why this approach?"

**Good**:
- "Tasks need rich context for agent execution. Current implementation only stores title. This enables full implementation instructions without external documentation."

**Bad**:
- "Because we need it" (no rationale)
- "To make it better" (no architectural context)

---

### Where (Specific file:line references)

**Must include**:
- Exact file paths (verified to exist)
- Approximate line numbers (±5 lines acceptable)
- Categorized by action (Modify, Create, Delete)

**Good**:
```markdown
### Files to Modify:
- `src/storage.zig:245` - Add description column to CREATE TABLE
- `src/types.zig:95` - Add description field to Task struct

### Files to Create:
- `tests/task_test.zig` - Unit tests for task command handlers
```

**Bad**:
```markdown
- Update the storage file (no path)
- src/TODO.zig (placeholder)
- Various files (too vague)
```

---

### How (Step-by-step with code)

**Must include**:
- Numbered steps
- Current code → Changed code pattern
- Rationale for each change
- Code snippets from actual codebase

**Good**:
```markdown
### Step 1: Update Task struct

**Current code** (`src/types.zig:95`):
```zig
pub const Task = struct {
    id: u32,
    title: []const u8,
    status: TaskStatus,
};
```

**Change to**:
```zig
pub const Task = struct {
    id: u32,
    title: []const u8,
    description: []const u8,  // Add this field
    status: TaskStatus,
};
```

**Rationale**: Description stored as UTF-8 string, follows existing title pattern for consistency.
```

**Bad**:
```markdown
1. Update the Task type
2. Add the field
3. Make it work
```

---

## Validation Examples

### Example 1: Simple Edit

```markdown
---
complexity: simple
language: zig
affected_components: [types]
files:
  - path: src/types.zig
    action: modify
    lines: 95
validation_commands:
  - zig build test --test-filter "types"
---

## What
Add description field to Task struct.

## Why
Tasks need rich context for implementation. Current Task only has title field.

## Where
- `src/types.zig:95` - Add description field after title

## How

### Step 1: Update Task struct

**Current code** (`src/types.zig:95`):
```zig
pub const Task = struct {
    id: u32,
    title: []const u8,
    status: TaskStatus,
};
```

**Change to**:
```zig
pub const Task = struct {
    id: u32,
    title: []const u8,
    description: []const u8,  // Add field
    status: TaskStatus,
};
```

**Rationale**: Follows existing string field pattern (title).

## Validation
1. Compile: `zig build`
2. Test: `zig build test --test-filter "types"`

## Success Criteria
- [ ] Field added to Task struct
- [ ] Compiles without errors
- [ ] Tests pass
```

---

### Example 2: New File Creation

```markdown
---
complexity: moderate
language: zig
affected_components: [tests, commands]
files:
  - path: tests/commands/task_test.zig
    action: create
automated_tests:
  - test "task new: success with plan"
  - test "task start: success"
validation_commands:
  - zig build test --test-filter "task_test"
---

## What
Create tests/commands/task_test.zig with unit tests for 7 task command modules.

## Why
After tiger-refactor split commands/task.zig into 7 modules, no unit tests exist. Creates test coverage gap.

## Where
### Files to Create:
- `tests/commands/task_test.zig` - New file (~500 lines)

### Pattern Reference:
- `tests/commands/plan_test.zig:1-388` - Model to follow

## How

### Step 1: Create file with imports

**New file** (`tests/commands/task_test.zig`):
```zig
//! Tests for task command handlers.

const std = @import("std");
const guerilla_graph = @import("guerilla_graph");
const Storage = guerilla_graph.storage.Storage;
const test_utils = @import("../test_utils.zig");
```

**Rationale**: Follows plan_test.zig import pattern for consistency.

### Step 2: Add task new tests

[Pattern from plan_test.zig:48-97]

## Patterns to Follow
- Test structure: `tests/commands/plan_test.zig:31-97`
- Database setup: `tests/commands/plan_test.zig:36-40`

## Validation
1. Compile: `zig build`
2. Run tests: `zig build test --test-filter "task_test"`

## Success Criteria
- [ ] File created
- [ ] 7 command sections (new/start/complete/show/update/delete/list)
- [ ] Tests pass
- [ ] File 400-560 lines
```

---

## Common Mistakes to Avoid

❌ **Generic code examples**:
```markdown
**Current code**:
```zig
// Some generic code
```
```

✅ **Real code from codebase**:
```markdown
**Current code** (`src/storage.zig:245`):
```zig
pub fn createTask(self: *Storage, title: []const u8) !Task {
    // Actual code from file
}
```
```

---

❌ **Vague instructions**:
```markdown
1. Update the function appropriately
2. Handle errors as needed
```

✅ **Specific steps**:
```markdown
### Step 1: Add error handling

**Current code** (`src/storage.zig:250`):
```zig
const result = sqlite3_exec(db, sql);
```

**Change to**:
```zig
const result = sqlite3_exec(db, sql);
if (result != SQLITE_OK) {
    return SqliteError.ExecFailed;
}
```

**Rationale**: Explicit error checking prevents silent failures.
```

---

❌ **No rationale**:
```markdown
Change X to Y.
```

✅ **With rationale**:
```markdown
Change X to Y.

**Rationale**: Approach Y provides better memory safety because Z. Follows pattern from existing code at file.zig:123.
```

---

## Limits

- YAML frontmatter: ≤50 lines
- What section: ≤200 words
- Why section: ≤400 words
- Where section: ≤50 file references
- How section: ≤20 steps
- Each code snippet: ≤50 lines

**Rationale**: Keep tasks focused and readable. If exceeding limits, task is too large - split it.

---

## Notes

This template is language-agnostic:
- Replace `[language]` with actual language (zig, java, python, etc.)
- Adapt code snippet syntax
- Use project's build/test commands

The structure (YAML + What/Why/Where/How) is universal.
