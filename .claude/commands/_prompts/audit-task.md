# Audit Task

## Variables

- `{{task_id}}` - Task identifier (e.g., storage:001)
- `{{title}}` - Task title
- `{{description}}` - Full task description (YAML frontmatter + What/Why/Where/How)
- `{{plan_goals}}` - Goals from PLAN.md
- `{{plan_non_goals}}` - Non-Goals from PLAN.md
- `{{architecture_overview}}` - Architecture section from PLAN.md
- `{{breaking_changes}}` - Breaking changes from PLAN.md

## Prompt

You are auditing task {{task_id}} for quality.

## Shared Modules (Already Loaded)

The orchestrator has loaded:
- quality-criteria.md: 5 quality dimensions
- code-verification.md: Engineering principles checks
- file-verification.md: File operations
- dependency-analysis.md: Dependency logic

Use these as your quality standards reference.

## Plan Context

**Goals**: {{plan_goals}}
**Non-Goals**: {{plan_non_goals}}
**Architecture**: {{architecture_overview}}
**Breaking Changes**: {{breaking_changes}}

**CRITICAL**: Verify task aligns with Goals, avoids Non-Goals.

## Task Details

**ID**: {{task_id}}
**Title**: {{title}}
**Description**:
```
{{description}}
```

## Your Task

Audit against quality-criteria.md and REPORT issues. DO NOT fix.

**Quality Criteria** (from quality-criteria.md):
1. Full Context - YAML frontmatter, What/Why/Where/How
2. Implementability - Clear instructions, no vague terms
3. Maintainability - Follows SRP/DRY, aligns with plan
4. Correctness - Files exist, line numbers accurate
5. Dependencies - File-level serialization, phase order

**Code Verification** (from code-verification.md):
- Check proposed code follows engineering_principles.md
- Verify functions ≤70 lines
- Check type usage (u32/i64 not usize)
- Verify defer for cleanup
- Check naming conventions

**N+1 Query Detection** (CRITICAL - check ALL code):
- CRITICAL if: repository.find*() or service.get*() called inside for/forEach/stream().map()
- HIGH if: DGS @DgsData resolver fetches related entities without DataLoader
- Pattern to flag: `entities.stream().map(e -> repository.findBy*(e.getId()))`
- Correct pattern: Batch fetch with `findByIdIn(ids)` then `groupBy()`

**File Verification** (from file-verification.md):
- VerifyFileExists for each file path
- VerifyLineNumber for accuracy
- DetectOldSchemaMarkers for schema issues

**MUST return JSON**:
```json
{
  "task_id": "{{task_id}}",
  "status": "PASS|NEEDS_WORK",
  "findings": [
    {
      "severity": "Critical|High|Medium|Low",
      "category": "FullContext|Implementability|Maintainability|Correctness|Dependencies",
      "issue": "...",
      "recommendation": "...",
      "verification": "..."
    }
  ],
  "files_verified": [...],
  "summary": {"critical": 0, "high": 0, "medium": 0, "low": 0}
}
```
