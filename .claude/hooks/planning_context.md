# Planning Context - Netflix ACT Codebase

## Project Structure Quick Reference

### Core Entities (src/main/java/com/netflix/animationcrewtracker/model/db/)
- `Role.java` - Crew member assignments to scenarios
- `RoleSharedAttributes.java` - Linking-id shared data across scenarios
- `Scenario.java` - Planning scenarios (OPEN → LIVE → COMPLETE)
- `Project.java` - Animation projects
- `Talent.java` - Crew members
- `Position.java` - Job positions with departments and job families
- `BusinessUnit.java` - Business unit taxonomy

### Service Layer Patterns
- `service/simple/` - Lookup tables (PositionType, BusinessUnit, Location)
- `service/role/` - Complex role operations (Query, Save, Diff, BulkUpsert)
- `service/talent/` - Talent operations and sync
- `service/scenario/` - Scenario lifecycle management
- `service/scheduler/` - Background jobs (Airtable, Workday sync)

### GraphQL Patterns
- Schema: `src/main/resources/schema/*.graphqls`
- Resolvers: `controller/graphql/*Mutation.java`, `*Query.java`
- DataFetchers: `controller/graphql/datafetcher/`
- DataLoaders: Use for N+1 prevention

### Database Patterns
- Migrations: `src/main/resources/db/migration/V*.sql`
- Always add indexes for foreign keys and frequently queried fields
- Use `gen_random_uuid()` for UUIDs
- TestContainers for repository tests

### Authorization
- Policies: `src/main/resources/policy/*.polar`
- StudioAuthz for entity-level access control
- Permission levels: Owner, Editor, Viewer

## Planning Imperatives

### ALWAYS Include in Plans
1. **N+1 Query Analysis** - Identify batch operations, DataLoaders
2. **Authorization** - Policy files and @PreAuthorize annotations
3. **Testing** - Unit tests (service), integration tests (GraphQL)
4. **Pattern References** - File:line examples from existing code
5. **Migration Indexes** - Performance implications

### NEVER Include in Plans
1. **Backward Compatibility** - Clean solutions only
2. **Vague Instructions** - "Update appropriately", "Handle errors"
3. **Placeholder Paths** - All file paths must be specific and verified
4. **Tech Debt** - No workarounds, no hacks

## Common Patterns to Reference

### Batch Operations
See: `RoleBulkUpsertService.java` - Example of bulk operations with batch size 500

### DataLoader Pattern
See: `TalentDataLoader.java` - Example of batching GraphQL nested queries

### Migration Pattern
See: Recent `V1.0.*__*.sql` files in db/migration/

### Service Testing Pattern
See: `RoleQueryServiceTest.java` - Example of mocking and comprehensive test coverage

### GraphQL Schema Pattern
See: `schema.graphqls` - Existing types, mutations, queries

## Decision Framework

When you encounter forks in the road, ask yourself:

1. **Is there an existing pattern?** → Follow it (DRY)
2. **Multiple valid approaches?** → Ask user (strategic question)
3. **Performance vs simplicity?** → Analyze and recommend
4. **Breaking change needed?** → Always prefer clean break (no tech debt)

## Complexity Indicators

**Simple**:
- Single entity changes
- Standard CRUD operations
- Follows clear existing pattern
- No integration points

**Moderate**:
- Multiple entities affected
- Custom business logic
- GraphQL schema changes
- Authorization updates
- Integration with 1 external system

**Complex**:
- Cross-entity transactions
- Multiple integration points
- Complex business rules
- Performance-critical operations
- Large-scale migrations
