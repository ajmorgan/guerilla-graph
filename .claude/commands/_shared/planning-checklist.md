# Planning Quality Checklist

Use this checklist to validate PLAN.md before running `/gg-task-gen`:

## Completeness

### Requirements
- [ ] Overview clearly states what and why
- [ ] Goals are specific and measurable
- [ ] Non-goals explicitly listed
- [ ] Success criteria defined

### Current State Analysis
- [ ] Existing implementation documented
- [ ] File paths provided for all current code
- [ ] Code snippets show current state
- [ ] Limitations/gaps identified

### Architecture Design
- [ ] Data flow documented (entry → service → repository → database)
- [ ] Key design decisions have rationale
- [ ] Integration points identified (Airtable, Infinity, Workday)
- [ ] Alternative approaches considered

### Implementation Phases
- [ ] All phases present: Database, Entity, Service, GraphQL, Authorization, Testing
- [ ] Each phase has: Goal, Changes, Pattern References, Rationale
- [ ] File paths are specific (not placeholders)
- [ ] Code snippets show current → proposed changes
- [ ] Line numbers approximate but reasonable

## Maintainability

### Single Responsibility Principle (SRP)
- [ ] Each class/method has one clear responsibility
- [ ] No God classes or methods doing too much
- [ ] Service methods focused on single operations

### DRY Principle
- [ ] Existing patterns referenced with file:line
- [ ] Utilities reused (not duplicated)
- [ ] Common logic extracted to shared methods

### No Tech Debt
- [ ] No backward compatibility hacks
- [ ] No workarounds or "temporary" solutions
- [ ] Clean, straightforward approach

## Implementability

### Specificity
- [ ] All file paths verified (files exist)
- [ ] Line numbers provided (approximate OK)
- [ ] No vague terms ("update appropriately", "as needed")
- [ ] Clear instructions for each change

### Pattern References
- [ ] Every recommendation has example from codebase
- [ ] file:line references for all patterns
- [ ] Code snippets from actual files

### Dependencies
- [ ] Phase dependencies clear (what blocks what)
- [ ] Parallel opportunities identified
- [ ] No circular dependencies

## Performance & Quality

### N+1 Query Analysis
- [ ] Query count table provided
- [ ] Complexity analysis (O notation)
- [ ] Prevention strategy documented
- [ ] Batch operations identified
- [ ] DataLoaders for GraphQL

### Authorization
- [ ] Policy files identified
- [ ] @PreAuthorize annotations planned
- [ ] Permission levels defined (Owner, Editor, Viewer)

### Testing
- [ ] Service tests planned (unit tests)
- [ ] Repository tests planned (TestContainers)
- [ ] GraphQL integration tests planned
- [ ] Success cases covered
- [ ] Error cases covered
- [ ] Edge cases covered

### Risk Assessment
- [ ] Complexity categorized (Low/Medium/High)
- [ ] Mitigation strategies for risks
- [ ] Breaking changes documented with justification

## File Change Summary

- [ ] All files to create listed
- [ ] All files to modify listed
- [ ] All files to delete listed (if any)
- [ ] Purpose/changes documented for each

## Estimated Complexity

- [ ] Overall complexity assessed (Simple/Moderate/Complex)
- [ ] Per-phase complexity breakdown
- [ ] Justification for complexity rating

## Red Flags (Should NOT appear in plan)

❌ **Vague Instructions**
- "Update appropriately"
- "Handle errors as needed"
- "Add validation"
- "Implement business logic"

❌ **Placeholder Paths**
- "src/main/java/.../SomeService.java" (no specific path)
- "Update the service file"
- "Modify the entity"

❌ **Missing Details**
- No line numbers
- No code snippets
- No pattern references
- No rationale for decisions

❌ **Tech Debt Indicators**
- "For backward compatibility, keep old endpoint"
- "Temporary workaround"
- "Hack to make it work"
- "Quick fix"

❌ **Performance Risks**
- Queries inside loops
- No batch operations planned
- No DataLoaders for GraphQL
- Missing N+1 analysis

## Sign-Off

If all checkboxes are checked and no red flags present:

✅ **Plan is ready for `/gg-task-gen PLAN.md`**

If checklist incomplete:
- Revise plan to address gaps
- Re-run planning with more exploration
- Add missing pattern references
- Clarify vague sections
