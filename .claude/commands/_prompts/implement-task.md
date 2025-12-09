# Implement Task

## Variables

- `{{task_id}}` - Task identifier (e.g., storage:001)
- `{{title}}` - Task title
- `{{description}}` - Full task description (YAML frontmatter + What/Why/Where/How)

## Prompt

You are implementing task {{task_id}}: {{title}}

## Task Description

{{description}}

## gg Command Usage Protocol

If your implementation requires using ANY gg commands (gg new, gg update, gg start, etc.):

**MANDATORY STEPS:**
1. **Run help FIRST**: `gg <command> --help` before using the command
2. **Read the examples**: Study the EXAMPLES section carefully
3. **Use exact syntax**: Copy the pattern shown in help output

**Common gg commands:**
- `gg new --help` - Create plans (no colon) or tasks (with colon suffix)
- `gg update --help` - Update plan/task title, description, status
- `gg start --help` - Mark task as in_progress
- `gg complete --help` - Mark task as completed
- `gg dep add --help` - Add task dependencies

**Critical syntax rules:**
- Task creation: `gg new <plan-slug>: --title "Title"` (colon suffix REQUIRED)
- Plan creation: `gg new <plan-slug> --title "Title"` (no colon)
- Task IDs: Always format <slug>:NNN (e.g., auth:001)

**If uncertain about syntax**: Run `gg <command> --help` and read the output before proceeding.

## Your Task

Implement the changes described in this task following the instructions exactly.

**Implementation Standards**:
1. Read all files mentioned in "Where" section
2. Understand existing patterns and architecture
3. Implement changes exactly as specified in "How" section
4. Follow code snippets and patterns provided
5. Apply Single Responsibility Principle (SRP)
6. Apply DRY Principle (reuse existing patterns)
7. No backwards compatibility tech debt - clean solutions only
8. Check for N+1 query issues and optimize

**Process**:
1. Read all files mentioned in task
2. Understand the full context
3. Implement each step from "How" section
4. Verify success criteria from task
5. DO NOT close the task (orchestrator handles lifecycle)
6. Report back what you implemented

**Report Format**:

At the end of your work, provide a summary:

```
## Implementation Summary

**Files Modified**:
- <file-path> - <what changed>
- <file-path> - <what changed>

**Files Created**:
- <file-path> - <purpose>

**Changes Made**:
<Brief summary of implementation>

**Success Criteria Verified**:
- [ ] <criterion from task> - ✅ PASS / ❌ FAIL / ⏭️ SKIP
- [ ] <criterion from task> - ✅ PASS / ❌ FAIL / ⏭️ SKIP

**Issues/Blockers**:
<List any problems encountered, or "None">

**Ready for Compilation**: YES / NO
<If NO, explain why>
```
