# Dependency Analysis Module

Algorithms for detecting file conflicts and building correct dependency graphs.

## Purpose

Provides reusable logic for:
1. File-level serialization (prevent concurrent file modifications)
2. Phase dependency ordering (logical execution order)
3. Cycle detection (prevent deadlocks)

Used by:
- `/gg-task-gen`: Build dependencies DURING task creation
- `/gg-task-audit`: Verify dependencies AFTER task creation

---

## Algorithm 1: File-Level Serialization

**Purpose**: Prevent concurrent modifications to same file

**Input**:
- `tasks`: Array of tasks with file operations

**Output**:
- `dependency_commands`: Array of `gg dep add` commands

**Algorithm**:
```
1. Build file_map: file_path → [task_ids]

   For each task in tasks:
     Parse YAML frontmatter → extract files array
     For each file in files array:
       If file.action == "modify" or "delete":
         Add task.id to file_map[file.path]

2. For each file_path in file_map:
   task_list = file_map[file_path]

   If length(task_list) > 1:
     # Multiple tasks modify this file - serialize them

     Sort task_list by:
       - Phase order (if available)
       - OR creation order
       - OR numeric task ID

     For i from 0 to length(task_list) - 2:
       task_current = task_list[i]
       task_next = task_list[i + 1]

       Generate command:
         "gg dep add {task_next} --blocks-on {task_current}"

       Add to dependency_commands

3. Return dependency_commands
```

**Example**:
```
Tasks:
  - auth:001: modifies src/auth.zig
  - auth:002: modifies src/auth.zig
  - auth:003: modifies src/auth.zig

File map:
  src/auth.zig → [auth:001, auth:002, auth:003]

Output:
  gg dep add auth:002 --blocks-on auth:001
  gg dep add auth:003 --blocks-on auth:002

Result: auth:001 → auth:002 → auth:003 (serialized)
```

---

## Algorithm 2: Phase Dependency Ordering

**Purpose**: Enforce logical execution order (types → storage → API)

**Input**:
- `tasks`: Tasks grouped by phase
- `phase_order`: Array of phase names in order

**Output**:
- `dependency_commands`: Array of `gg dep add` commands

**Algorithm**:
```
1. Group tasks by phase:
   phase_tasks = {} (map: phase_name → [task_ids])

   For each task in tasks:
     Extract phase from task metadata or description
     Add to phase_tasks[phase]

2. Link phases sequentially:

   For i from 0 to length(phase_order) - 2:
     current_phase = phase_order[i]
     next_phase = phase_order[i + 1]

     last_task_current = last task in phase_tasks[current_phase]
     first_task_next = first task in phase_tasks[next_phase]

     Generate command:
       "gg dep add {first_task_next} --blocks-on {last_task_current}"

     Add to dependency_commands

3. Return dependency_commands
```

**Example**:
```
Phases: [types, storage, api]

Tasks:
  types: [types:001, types:002]
  storage: [storage:001]
  api: [api:001, api:002]

Phase links:
  types → storage: storage:001 blocks-on types:002
  storage → api: api:001 blocks-on storage:001

Output:
  gg dep add storage:001 --blocks-on types:002
  gg dep add api:001 --blocks-on storage:001
```

---

## Algorithm 3: Cycle Detection

**Purpose**: Validate proposed dependency doesn't create cycle

**Input**:
- `task_id`: Task to add dependency to
- `blocks_on_id`: Task it will block on
- `existing_graph`: Current dependency graph

**Output**:
- `is_cycle`: boolean
- `cycle_path`: Array of task IDs forming cycle (if found)

**Algorithm**:
```
1. Build adjacency list from existing_graph:
   graph = {} (map: task_id → [dependent_task_ids])

   For each dependency in existing_graph:
     Add dependency.task_id to graph[dependency.blocks_on_id]

2. Add proposed edge:
   Add task_id to graph[blocks_on_id]

3. Run DFS from task_id to check if blocks_on_id is reachable:

   visited = set()
   path = []

   Function DFS(current):
     If current == blocks_on_id:
       # Found cycle
       Return true

     If current in visited:
       Return false

     Add current to visited
     Add current to path

     For each neighbor in graph[current]:
       If DFS(neighbor):
         Return true

     Remove current from path
     Return false

   is_cycle = DFS(task_id)

4. If is_cycle:
   - Return is_cycle=true, cycle_path
5. Else:
   - Return is_cycle=false, cycle_path=[]
```

**Example**:
```
Existing:
  auth:002 blocks-on auth:001
  auth:003 blocks-on auth:002

Proposed:
  auth:001 blocks-on auth:003

Check:
  DFS from auth:001 → auth:002 → auth:003 → back to auth:001
  is_cycle = true
  cycle_path = [auth:001, auth:002, auth:003, auth:001]

Verdict: REJECT (would create cycle)
```

---

## Algorithm 4: Extract File Operations from Task

**Purpose**: Parse task description to find files it will modify

**Input**:
- `task_description`: Full task description (YAML + markdown)

**Output**:
- `file_operations`: Array of {path, action, lines}

**Algorithm**:
```
1. Parse YAML frontmatter:
   - Extract `files` array
   - For each file entry:
     - Extract path, action, lines (optional)
     - Add to file_operations

2. If no YAML frontmatter or empty files array:
   - Parse "## Where" section
   - Extract file paths using regex: `([a-zA-Z0-9_/.]+\.zig):(\d+)`
   - Infer action: "modify" (default)
   - Add to file_operations

3. Return file_operations
```

**Example**:
```
Task description:
---
files:
  - path: src/storage.zig
    action: modify
    lines: 245-260
---

Output:
  [
    {path: "src/storage.zig", action: "modify", lines: "245-260"}
  ]
```

---

## Algorithm 5: Detect File Conflicts

**Purpose**: Find tasks modifying same file without dependencies

**Input**:
- `tasks`: Array of all tasks

**Output**:
- `conflicts`: Array of {file_path, conflicting_tasks, missing_deps}

**Algorithm**:
```
1. Extract file operations from all tasks:
   task_files = {} (map: task_id → [file_paths])

   For each task in tasks:
     ops = ExtractFileOperations(task.description)
     task_files[task.id] = ops.map(op => op.path)

2. Build reverse map:
   file_tasks = {} (map: file_path → [task_ids])

   For each task_id, file_paths in task_files:
     For each file_path in file_paths:
       Add task_id to file_tasks[file_path]

3. Check for conflicts:
   conflicts = []

   For each file_path, task_ids in file_tasks:
     If length(task_ids) > 1:
       # Multiple tasks modify this file

       For each pair (task_a, task_b) in task_ids:
         Check if dependency exists:
           - task_a blocks-on task_b OR
           - task_b blocks-on task_a

         If NO dependency:
           Add to conflicts: {
             file_path: file_path,
             conflicting_tasks: [task_a, task_b],
             missing_deps: "Need: {task_a} → {task_b} or vice versa"
           }

4. Return conflicts
```

**Example**:
```
Tasks:
  - test-org:008: modifies tests/format_test.zig (extracts JSON tests)
  - test-org:009: modifies tests/format_test.zig (extracts text tests)
  - test-org:010: deletes tests/format_test.zig

Check dependencies:
  - test-org:008 → test-org:009: NO dependency
  - test-org:010 blocks on 008/009: NO

Conflicts found:
  {
    file_path: "tests/format_test.zig",
    conflicting_tasks: [test-org:008, test-org:009, test-org:010],
    missing_deps: [
      "test-org:010 → test-org:008",
      "test-org:010 → test-org:009"
    ]
  }

Verdict: CRITICAL issue - file-level serialization violated
```

---

## Usage Examples

### In task-gen:

```markdown
After creating all tasks:

1. Read `.claude/commands/_shared/dependency-analysis.md`
2. Run File-Level Serialization algorithm
3. Execute all generated dependency commands
4. Run Phase Dependency Ordering (if phases defined)
5. Verify no cycles with Cycle Detection

Result: Complete, correct dependency graph before audit.
```

### In task-audit:

```markdown
When auditing dependencies:

1. Read `.claude/commands/_shared/dependency-analysis.md`
2. Run Detect File Conflicts algorithm
3. If conflicts found:
   - Flag as Critical findings
   - Recommend specific dependencies to add
4. Run Cycle Detection on existing graph
5. Report any issues
```

---

## Limits

- Max tasks to analyze: 1000
- Max files to track: 500
- Max dependency chain length: 100

**Rationale**: Prevent pathological cases, support reasonable plan sizes.

