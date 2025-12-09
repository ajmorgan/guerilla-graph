# Review Work

## Variables

- `{{task_id}}` - Task identifier (e.g., storage:001)
- `{{expected_files}}` - Files expected to be modified (from task's Where section)
- `{{success_criteria}}` - Success criteria from task description

## Prompt

You are reviewing the implementation of task {{task_id}} to verify it matches the task intent.

**Purpose**: Verify sub-agents implemented what the task asked (not re-auditing Tiger Style - that was done in plan-audit/task-audit).

## Expected Changes

**Files to be modified**:
{{expected_files}}

**Success criteria**:
{{success_criteria}}

## Review Process

1. **Check for blockers**:
   - If agent reported blockers/errors, identify them
   - Report any implementation issues

2. **Verify task intent was applied**:

   a. Read each expected file:
      - Check that changes align with task's "How" section
      - Verify changes are present (not skipped)

   b. Check success criteria:
      - If task listed specific criteria (e.g., "function X exists"), verify them
      - Flag if criterion not met

3. **Categorize result**:
   - ✅ COMPLETE: Task intent applied, ready for compilation
   - ⚠️ PARTIAL: Some changes missing or incomplete
   - ❌ BLOCKED: Agent couldn't proceed, needs intervention

**Focus**: Did the code changes match the task description? Not re-auditing code quality.

## Report Format

Provide a summary:

```
## Review Summary

**Task**: {{task_id}}

**Files Checked**:
- <file-path> - ✅ Modified as expected / ⚠️ Changes missing / ❌ Not modified
- <file-path> - ✅ Modified as expected / ⚠️ Changes missing / ❌ Not modified

**Success Criteria**:
- [ ] <criterion> - ✅ MET / ❌ NOT MET / ⏭️ CANNOT VERIFY

**Overall Status**: ✅ COMPLETE / ⚠️ PARTIAL / ❌ BLOCKED

**Issues Found**:
<List any issues, or "None">

**Recommendation**: PROCEED TO COMPILATION / FIX ISSUES FIRST / RE-RUN AGENT
```
