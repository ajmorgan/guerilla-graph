# Task Quality Standards

**Shared reference for all gg commands**

## Core Criteria

Each task must meet these four criteria:

### 1. Implementability
Can an agent execute the work without external documentation?
- Clear, actionable instructions
- Specific file paths and line numbers
- Code snippets showing patterns to follow
- No ambiguity about what needs to be done

### 2. Maintainability
Does the work follow project standards?
- Follows established patterns and conventions
- Applies Single Responsibility Principle (SRP)
- Applies DRY Principle (Don't Repeat Yourself)
- No backwards compatibility tech debt (clean solutions only)
- Includes rationale for architectural decisions

### 3. Full Context
Self-contained work package with four elements:
- **What**: Specific implementation steps
- **Where**: Exact file paths and line numbers
- **How**: Code snippets, patterns to follow
- **Why**: Rationale and architectural context

### 4. Dependencies
Proper dependency tracking enables parallel execution:
- Blocking relationships are correct
- Independent work can run in parallel
- Dependencies reflect actual technical constraints

## Critical Quality Rules

1. **NO PLACEHOLDERS**: Every file path, line number, code snippet must be from actual codebase exploration
2. **NO VAGUE INSTRUCTIONS**: "Update X" → "Add field Y to class X at line Z, following pattern in FileA:123"
3. **NO MISSING CONTEXT**: Every "what" needs "where", "how", and "why"
4. **NO ASSUMPTIONS**: If uncertain, explore the codebase or ask the user
5. **NO SHORTCUTS**: Generate complete, audit-ready tasks from the start
6. **MAXIMIZE PARALLELISM**: Only create sequential dependencies where truly required

## Example: Good vs Bad Task Descriptions

### ❌ BAD (Vague, No Context):
```
Update the Scenario entity to support business unit.
Add the field and update the service.
```

### ✅ GOOD (Specific, Full Context):
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
