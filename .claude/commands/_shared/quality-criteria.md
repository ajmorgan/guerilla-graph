# Task Quality Criteria

Reference this file to ensure tasks meet quality standards for implementation.

## Purpose

Defines the quality bar for gg tasks. Used by:
- `/gg-task-gen`: Verify tasks BEFORE creation (preventive)
- `/gg-task-audit`: Verify tasks AFTER creation (detective)

Single source of truth - update here, affects both commands.

---

## The Five Criteria

### 1. Full Context

**Required Elements**:
- YAML frontmatter with `files` array
- What: Specific implementation goal (1-2 sentences)
- Why: Rationale explaining decisions and architecture fit
- Where: Real file paths with approximate line numbers
- How: Step-by-step instructions with code snippets (current → change)

**YAML Frontmatter Requirements**:
```yaml
---
complexity: trivial|simple|moderate|complex|very_complex
language: [language]
affected_components: [components]
requires_review: true|false
files:
  - path: [file-path]
    action: modify|create|delete
    lines: [line-numbers]  # Optional
automated_tests:
  - [test names]
validation_commands:
  - [build/test commands]
---
```

**Verification Checklist**:
- [ ] YAML frontmatter has `files` array with path, action
- [ ] Files array matches files mentioned in Where section
- [ ] File paths are specific (not placeholders like "path/to/file")
- [ ] Line numbers provided (even if approximate)
- [ ] Code snippets from actual codebase (not invented)
- [ ] Rationale explains WHY this approach chosen
- [ ] All four sections present: What, Where, How, Why

**Critical Issues**:
- Missing `files` array in YAML frontmatter
- Missing file paths entirely
- Placeholder paths like "src/TODO.zig"
- No code snippets in How section
- Files array doesn't match Where section

**High Issues**:
- Missing line numbers
- Missing rationale
- Incomplete Where or How sections

---

### 2. Implementability

**Can an agent execute this task without external documentation?**

**Required Characteristics**:
- Instructions clear and actionable
- No vague terms ("update appropriately", "as needed", "handle errors")
- Step-by-step format with numbered steps
- Each step has current code → changed code pattern
- Success criteria specific and testable

**Verification Checklist**:
- [ ] Could implement without asking questions
- [ ] All steps unambiguous
- [ ] Each step has clear "done" state
- [ ] No references to external docs needed

**Critical Issues**:
- Instructions say "implement as appropriate" with no guidance
- Steps are vague ("update the function")
- Missing critical implementation details

**High Issues**:
- Some steps lack code examples
- Success criteria subjective ("make it better")
- Assumes knowledge not in task

---

### 3. Maintainability

**Does the work follow best practices AND align with plan goals?**

**Plan Alignment** (check FIRST):
1. Verify task aligns with plan's Goals
2. Verify task avoids plan's Non-Goals
3. Only flag issues that CONTRADICT the plan

**Best Practices Checklist**:
- [ ] Follows Single Responsibility Principle
- [ ] Reuses existing patterns (DRY)
- [ ] No technical debt (workarounds, TODOs, backwards compatibility tech debt)
- [ ] Performance considerations noted (N+1 queries, batching)
- [ ] Clean solution (not temporary fixes)

**Code Quality** (see `code-verification.md`):
- [ ] Generated code follows `.claude/hooks/engineering_principles.md`
- [ ] No violations of project's engineering principles

**DO NOT Flag**:
- Breaking changes documented in plan's "Breaking Changes" section
- Architectural decisions matching plan's stated approach
- Lack of backward compatibility if plan doesn't require it

**Critical Issues**:
- Task implements something explicitly in plan's Non-Goals
- Introduces technical debt (workarounds, "TODO: fix later")
- Breaking change NOT documented in plan

**High Issues**:
- Doesn't follow patterns referenced in plan
- Missing performance considerations for bulk operations
- Violates SRP or DRY principles

---

### 4. Correctness

**Are the details accurate?**

**File Verification** (see `file-verification.md`):
- [ ] All file paths exist in codebase
- [ ] Line numbers within ±5 lines of actual location
- [ ] Code snippets match actual codebase
- [ ] Referenced patterns actually exist
- [ ] Proposed changes align with codebase architecture

**Verification Steps** (REQUIRED):
1. For EACH file path: Use Read tool to verify existence
2. For EACH line number: Check approximate accuracy (±5 lines acceptable)
3. For EACH pattern reference: Verify it exists in codebase
4. For EACH function mentioned: Verify signature matches

**Critical Issues**:
- File path doesn't exist
- Referenced function/method doesn't exist
- Line number off by >5 lines

**High Issues**:
- Pattern reference doesn't match actual code
- Code snippet outdated or incorrect
- Function signature doesn't match reality

**DO NOT Flag**:
- Minor formatting differences in code snippets
- Line numbers within ±5 lines of actual
- Approximate file size estimates

---

### 5. Dependencies

**Are blocking relationships correct?**

**Dependency Analysis** (see `dependency-analysis.md`):
- [ ] File-level serialization applied (same-file tasks chained)
- [ ] Phase dependencies correct (logical order)
- [ ] Independent work can run in parallel
- [ ] No unnecessary sequential bottlenecks

**Verification**:
- Review task's "Blocking" and "Blocked by" lists
- Identify if task modifies files that other tasks modify
- Check if task needs output from other tasks

**Critical Issues**:
- Task modifies same file as another task without dependency
- Task needs output from another task but no dependency exists

**High Issues**:
- Unnecessary sequential constraint (could run in parallel)
- Missing dependency on prerequisite work

---

## Quality Checklist (Quick Reference)

Use this checklist to validate each task:

**Context**:
- [ ] YAML frontmatter complete (complexity, language, files array)
- [ ] What/Why/Where/How sections present
- [ ] Code snippets from actual codebase

**Correctness**:
- [ ] All file paths verified (use file-verification.md)
- [ ] Line numbers accurate (±5 lines)
- [ ] Code follows engineering principles (use code-verification.md)

**Dependencies**:
- [ ] File-level serialization checked (use dependency-analysis.md)
- [ ] Phase dependencies logical
- [ ] No cycles, maximum parallelism

**Implementability**:
- [ ] Clear step-by-step instructions
- [ ] No vague terms or placeholders
- [ ] Specific success criteria

**Maintainability**:
- [ ] Aligns with plan Goals/Non-Goals
- [ ] Follows SRP, DRY, clean design
- [ ] No technical debt introduced

---

## Focus: Implementation Blockers Only

**Severity Definitions**:

**Critical** (must fix before execution):
- Missing essential context (file paths, functions undefined)
- Major inaccuracies (files don't exist, line numbers off by >5)
- Implementation blockers (vague instructions, contradicts plan)
- Technical debt (workarounds, TODOs, hacks)

**High** (should fix, but not blocking):
- Some steps lack code examples
- Pattern reference slightly off
- Missing optional context

**Medium/Low** (can defer):
- Minor formatting differences
- Approximate estimates slightly off
- Style improvements

**DO NOT Report**:
- Line number precision within ±5 lines
- Approximate file size estimates
- Style/documentation suggestions
- Adding more detail when existing detail sufficient

---

## VerifyTaskQuality Operation

**Purpose**: Validate a task description against quality criteria before creation or after audit

**Input**:
- `task_description`: Complete task description (YAML frontmatter + markdown)
- `plan_context`: Optional - Goals, Non-Goals from PLAN.md for alignment check

**Output**:
- `is_valid`: boolean (true if no Critical issues)
- `findings`: Array of {severity, category, issue, recommendation}
- `counts`: {critical: int, high: int, medium: int, low: int}

**Algorithm**:
```
1. Initialize findings = [], counts = {critical: 0, high: 0, medium: 0, low: 0}

2. Check Full Context:
   a. Parse YAML frontmatter
      - If missing `files` array: Add Critical finding
      - If missing `complexity`: Add High finding
   b. Check for ## What section
      - If missing or empty: Add Critical finding
   c. Check for ## Why section
      - If missing or empty: Add High finding
   d. Check for ## Where section
      - If missing: Add Critical finding
      - If no file paths (pattern: `path:line`): Add Critical finding
   e. Check for ## How section
      - If missing: Add Critical finding
      - If no code snippets (```): Add High finding

3. Check Implementability:
   a. Search for vague terms:
      - "appropriately", "as needed", "handle errors", "update accordingly"
      - If found: Add Critical finding with location
   b. Check for numbered steps in How section
      - If no steps (### Step N pattern): Add High finding
   c. Check for current → change pattern
      - If no "Current code" or "Change to" blocks: Add High finding

4. Check Correctness (if file-verification available):
   a. For each file path in Where section:
      - result = VerifyFileExists(file_path)
      - If not result.exists: Add Critical finding
   b. For each line number reference:
      - result = VerifyLineNumber(file_path, line_number)
      - If result.status == WAY_OFF: Add Critical finding

5. Check Maintainability (if plan_context provided):
   a. For each Non-Goal in plan_context:
      - If task description mentions Non-Goal topic: Add Critical finding
   b. Search for tech debt indicators:
      - "workaround", "temporary", "TODO", "hack", "backward compat"
      - If found: Add Critical finding

6. Check Dependencies (if dependency info available):
   a. Extract files from task's YAML frontmatter
   b. Check if other tasks modify same files
   c. If conflict and no dependency: Add Critical finding

7. Calculate is_valid:
   is_valid = (counts.critical == 0)

8. Return {is_valid, findings, counts}
```

**Usage**:
```markdown
# Before creating task (gg-task-gen)
result = VerifyTaskQuality(task_description, plan_context)
If not result.is_valid:
  FOR finding IN result.findings WHERE severity == "Critical":
    Fix issue in task_description
  Re-verify until is_valid == true
Create task only after verification passes

# During audit (gg-task-audit)
result = VerifyTaskQuality(task_description, plan_context)
Return result as agent findings
```

**Severity Assignment**:
- **Critical**: Blocks implementation (missing files, vague instructions, contradicts plan)
- **High**: Significantly impacts quality (missing rationale, no code examples)
- **Medium**: Minor quality issue (approximate line numbers, style suggestions)
- **Low**: Nitpick (formatting, optional improvements)

---

## Integration Notes

Commands using this file should:
1. Read this file at start of execution
2. Store criteria in working memory
3. Apply VerifyTaskQuality to each task being verified/created
4. Use severity definitions for consistent reporting

---

## Examples

### Example: Task Failing Full Context

**Before** (fails Full Context check):
```markdown
---
complexity: moderate
---

## What
Update the storage layer

## How
Make the necessary changes to support descriptions
```

**Issues Found**:
- Critical: Missing `files` array in YAML frontmatter
- Critical: No file paths in Where section (section missing entirely)
- High: No code snippets showing current state

**After** (passes):
```markdown
---
complexity: moderate
language: zig
files:
  - path: src/storage.zig
    action: modify
    lines: 245-260
  - path: src/types.zig
    action: modify
    lines: 95-100
---

## What
Add description field to Task struct and storage layer

## Why
Tasks need rich context for agent execution. Current implementation only stores title.

## Where
- `src/types.zig:95` - Task struct definition
- `src/storage.zig:245` - CREATE TABLE statement
- `src/storage.zig:312` - createTask function

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
    description: []const u8,
    status: TaskStatus,
};
```
```

### Example: Task Failing Implementability

**Before** (fails):
```markdown
## How
1. Update the function appropriately
2. Handle errors as needed
3. Add tests
```

**Issues Found**:
- Critical: "appropriately" is vague - what changes?
- Critical: "as needed" is vague - what error cases?
- High: "Add tests" - what test cases?

**After** (passes):
```markdown
## How
### Step 1: Add description parameter
Add `description: []const u8` as third parameter to `createTask()`.

### Step 2: Bind description in SQL
After binding title (line 318), add:
```zig
try stmt.bind_text(3, task.description);
```

### Step 3: Handle empty descriptions
If description is empty string, bind empty string (not null).

### Step 4: Add test case
In `test "storage: create task"`, verify description round-trips:
```zig
const task = try storage.createTask(alloc, "Title", "Description");
try std.testing.expectEqualStrings("Description", task.description);
```
```

### Example: Good vs Bad Task Descriptions

### BAD (Vague, No Context):
```
Update the Scenario entity to support business unit.
Add the field and update the service.
```

### GOOD (Specific, Full Context):
```
## What

Add business_unit_id foreign key to Scenario entity to track which business unit owns each scenario.

## Why

Scenarios need to be associated with business units for resource planning and reporting.
This follows the existing pattern of business unit associations used in Project entity.

## Where

### Files to Modify:
- `src/main/java/com/netflix/animationcrewtracker/model/db/Scenario.java:45` - Add businessUnitId field
- `src/main/java/com/netflix/animationcrewtracker/repository/ScenarioRepository.java:23` - Add query by businessUnitId

## How

### Step 1: Add field to Scenario entity

**Current code** (`Scenario.java:45`):
```java
  private String scenarioNotes;
  private Integer typeId;
```

**Change to**:
```java
  private String scenarioNotes;
  private Integer typeId;

  @Column(name = "business_unit_id")
  private Integer businessUnitId;
```

**Rationale**: Follows existing foreign key pattern. Migration already added business_unit_id column in V1.0.36.

### Step 2: Add repository query method

**Current code** (`ScenarioRepository.java:23`):
```java
  List<Scenario> findByProjectId(Integer projectId);
```

**Add after**:
```java
  List<Scenario> findByBusinessUnitId(Integer businessUnitId);
```

**Rationale**: Follows Spring Data JDBC naming convention. Enables querying scenarios by business unit.

## Patterns to Follow

- Foreign key pattern: See `Project.java:67` (businessUnitId field)
- Repository query pattern: See `ProjectRepository.java:15` (findByBusinessUnitId)
- Column naming: snake_case in DB, camelCase in Java

## Related Code

- Entity: `Project.java:67` - existing businessUnitId field example
- Migration: `V1.0.36__add_business_unit_id_to_scenario.sql` - DB column already exists
- Service: `BusinessUnitService.java:45` - service for business unit lookups

## Success Criteria

- [ ] Scenario entity has businessUnitId field with @Column annotation
- [ ] ScenarioRepository has findByBusinessUnitId method
- [ ] Follows existing foreign key patterns (Project example)
- [ ] No backwards compatibility code needed (new feature)
```
