# Code Verification Module

Verify that proposed code changes follow project engineering standards.

## Purpose

Checks that CODE in task descriptions follows `.claude/hooks/engineering_principles.md`.

Used by:
- `/gg-task-gen`: Verify code BEFORE creating tasks
- `/gg-task-audit`: Verify code IN existing tasks

---

## Engineering Principles Reference

**Location**: `.claude/hooks/engineering_principles.md`

**Key Standards** (store in working memory before verification):

**Safety & Correctness**:
- Functions ≤70 lines maximum
- Explicitly-sized types (u32, i64) not usize (except loop indices, array lengths)
- Error handling explicit (no ignored `_` returns except cleanup)
- Defer for resource cleanup
- Assertions for preconditions/postconditions

**Code Quality**:
- Single Responsibility Principle
- DRY principle (reuse existing patterns)
- No backwards compatibility tech debt
- Variables at smallest scope

**Naming**:
- Functions: snake_case
- Types: PascalCase
- No abbreviations (except i, j, k in loops)
- Full words: `statement` not `stmt`, `allocator` not `alloc`

**Comments**:
- Rationale documented (why this approach)
- Sentences with capitalization and punctuation

---

## Verification Algorithm

### Step 1: Extract Code Blocks from Task

```
Input: task_description (string)
Output: code_blocks (array of {language, code, location})

Algorithm:
1. Search for all code fence markers (```zig, ```java, etc.)
2. For each code block:
   a. Extract language identifier
   b. Extract code content
   c. Note location context (which section: How, Where, etc.)
   d. Store in code_blocks array
3. Return code_blocks
```

### Step 2: Analyze Each Code Block

```
For each code_block in code_blocks:

  1. **Check Function Length**:
     - Count lines in function bodies
     - If function >70 lines: Flag "Function exceeds 70-line limit"

  2. **Check Type Usage**:
     - Search for `usize` usage
     - If usize used in business logic (not loop indices): Flag "Use u32/i64 instead of usize"
     - Exception: Loop indices, array lengths acceptable

  3. **Check Error Handling**:
     - Search for `_ =` patterns
     - Check if in defer/cleanup context
     - If ignored outside cleanup: Flag "Ignored error return"

  4. **Check Naming**:
     - Extract function names (pub fn NAME)
     - Verify snake_case
     - Check for abbreviations: stmt, alloc, db, etc.
     - If abbreviated: Flag "Use full word: statement not stmt"

  5. **Check Memory Management**:
     - If allocator passed: Check for defer cleanup
     - If allocates: Check for corresponding free/deinit
     - If missing: Flag "Missing defer cleanup for allocation"

  6. **Check Comments**:
     - Look for rationale comments
     - Check if sentences (capitalized, punctuation)
     - If missing rationale: Flag "Add comment explaining why"
```

### Step 3: Report Violations

```
For each violation found:
  Create finding:
    severity: "High" (code quality issues are important but not always blocking)
    category: "Maintainability"
    issue: [specific violation]
    recommendation: [how to fix]
    verification: [how to confirm fixed]
```

---

## Violation Patterns

### Pattern 1: usize in Business Logic

**Detected**:
```zig
pub fn processItems(count: usize) !void {
    // Business logic using usize
}
```

**Issue**: "Use explicitly-sized types (u32, i64) not usize"

**Recommendation**:
```zig
pub fn processItems(count: u32) !void {
    // Use u32 for bounded counts
}
```

**Exception**: Loop indices and array lengths are acceptable:
```zig
for (items, 0..) |item, i| { // i is usize - OK
```

---

### Pattern 2: Function >70 Lines

**Detected**: Function body has 85 lines

**Issue**: "Function exceeds 70-line limit"

**Recommendation**: "Split into helper functions, each ≤70 lines"

---

### Pattern 3: Ignored Error

**Detected**:
```zig
_ = storage.createTask(task);  // Outside defer block
```

**Issue**: "Error return ignored outside cleanup context"

**Recommendation**:
```zig
try storage.createTask(task);  // Propagate error
```

**Exception**: Allowed in defer/cleanup:
```zig
defer _ = database.close();  // OK in cleanup
```

---

### Pattern 4: Abbreviations

**Detected**:
```zig
pub fn initDb(alloc: Allocator) !void
```

**Issue**: "Use full words: database not db, allocator not alloc"

**Recommendation**:
```zig
pub fn initDatabase(allocator: Allocator) !void
```

---

### Pattern 5: Missing Defer

**Detected**:
```zig
pub fn loadData(allocator: Allocator) ![]Data {
    var list = try ArrayList(Data).init(allocator);
    // ... populate list
    return list.toOwnedSlice();  // No defer list.deinit()
}
```

**Issue**: "Missing defer cleanup - memory leak on error path"

**Recommendation**:
```zig
pub fn loadData(allocator: Allocator) ![]Data {
    var list = ArrayList(Data).init(allocator);
    defer list.deinit();  // Cleanup on error paths
    // ... populate list
    return try list.toOwnedSlice();
}
```

---

### Pattern 6: Missing Rationale Comment

**Detected**:
```zig
const max_depth = 100;
```

**Issue**: "Magic number without rationale comment"

**Recommendation**:
```zig
// Limit recursion depth to prevent stack overflow (SQL CTEs support 100 levels).
const max_depth = 100;
```

---

### Pattern 7: N+1 Query Risk

**Flag these patterns**:
- `repository.find*()` or `service.get*()` called inside for/forEach/stream().map()
- DGS `@DgsData` resolver fetching related entities without DataLoader
- Entity relationship access (`.getChildren()`, `.getParent()`) inside loops

**Severity**: CRITICAL in hot paths (GraphQL resolvers), HIGH in batch jobs

**Fix direction**: Batch fetch with `findByIdIn(ids)` then `groupBy()`

---

## Usage Examples

### In task-gen:

```markdown
After creating task description with code examples:

1. Read `.claude/commands/_shared/code-verification.md`
2. Extract all code blocks from task description
3. Run verification algorithm on each block
4. If violations found:
   - Fix code in task description
   - Add rationale comments
   - Ensure engineering principles followed
5. Only create task if code passes verification
```

### In task-audit:

```markdown
When auditing task:

1. Read `.claude/commands/_shared/code-verification.md`
2. Extract all code blocks from task description
3. Run verification algorithm
4. Report violations as findings:
   - Severity: "High"
   - Category: "Maintainability"
   - Include specific fix recommendation
```

---

## Limits

- Max code blocks to check: 50 per task
- Max function length: 70 lines
- Max violations to report: 20 per task

**Rationale**: Prevent runaway analysis, focus on critical issues.

