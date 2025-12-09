# File Verification Module

Reusable file operations for verifying paths, reading code, extracting snippets.

## Purpose

Provides standard algorithms for file operations used across commands.

---

## Operation 1: Verify File Exists

**Purpose**: Check if file path is valid

**Input**:
- `file_path`: Path to verify (string)

**Output**:
- `exists`: boolean
- `note`: Context about result

**Algorithm**:
```
1. Try: Read(file_path)
2. If succeeds:
   - exists = true
   - note = "File verified: [size] bytes"
3. If fails:
   - exists = false
   - note = "File not found: [error]"
```

**Usage**:
```markdown
For each file_path in task:
  result = VerifyFileExists(file_path)
  If not result.exists:
    Flag as Critical: "File path doesn't exist: {file_path}"
```

---

## Operation 2: Verify Line Number Accuracy

**Purpose**: Check if line number reference is approximately correct

**Input**:
- `file_path`: File to check
- `target_line`: Line number claimed in task
- `tolerance`: Acceptable range (default ±5 lines)

**Output**:
- `status`: ACCURATE | OFF | WAY_OFF
- `actual_line`: Where code actually found (if different)
- `note`: Explanation

**Algorithm**:
```
1. Read file with Read tool
2. Get total line count from read result
3. Check if target_line within valid range:
   - If target_line > total_lines:
     - status = WAY_OFF
     - note = "Line {target_line} doesn't exist (file has {total_lines} lines)"
4. If valid range:
   - status = ACCURATE (within ±5 is acceptable)
   - note = "Line number reasonable for file size"
```

**Note**: Deep verification (searching for exact code snippet) is expensive. We accept ±5 line tolerance as "good enough" for task quality.

**Usage**:
```markdown
For each file:line reference in task:
  result = VerifyLineNumber(file_path, line_number)
  If result.status == WAY_OFF:
    Flag as Critical: "Line number off by >5 lines"
```

---

## Operation 3: Extract Code Snippet

**Purpose**: Get real code from codebase for task descriptions

**Input**:
- `file_path`: File to read
- `line_number`: Target line
- `context_lines`: Lines before/after (default 10)

**Output**:
- `code_snippet`: Extracted code with line numbers
- `start_line`: First line of snippet
- `end_line`: Last line of snippet

**Algorithm**:
```
1. Read file with Read tool
2. Calculate range:
   - start = max(1, line_number - context_lines/2)
   - end = line_number + context_lines/2
3. Extract lines in range [start, end]
4. Format with line numbers (cat -n style)
5. Return code_snippet
```

**Usage**:
```markdown
When creating task with code example:
  snippet = ExtractCodeSnippet("src/types.zig", 95, 10)

  Add to task How section:
  **Current code** (`src/types.zig:95`):
  ```zig
  {snippet}
  ```
```

---

## Operation 4: Verify Pattern Exists

**Purpose**: Check if referenced pattern actually exists in codebase

**Input**:
- `file_path`: File to search
- `pattern_description`: What to look for (e.g., "RAII pattern with defer")
- `reference_line`: Approximate location (optional)

**Output**:
- `found`: boolean
- `actual_line`: Where pattern found
- `code_snippet`: The actual pattern

**Algorithm**:
```
1. Read file with Read tool
2. If reference_line provided:
   - Search window [reference_line - 10, reference_line + 10]
3. If not found or no reference_line:
   - Search entire file
4. Look for pattern keywords (defer, deinit, try, etc.)
5. If found:
   - Extract snippet
   - Return found=true, actual_line, code_snippet
6. If not found:
   - Return found=false
```

**Usage**:
```markdown
When task references existing pattern:
  "Pattern to follow: src/storage.zig:156 - allocator.dupe pattern"

  Verify:
  result = VerifyPatternExists("src/storage.zig", "allocator.dupe", 156)
  If not result.found:
    Flag as High: "Pattern reference doesn't match actual code"
```

---

## Operation 5: Detect OLD SCHEMA Markers

**Purpose**: Check if file has compatibility issues

**Input**:
- `file_path`: File to check

**Output**:
- `has_marker`: boolean
- `marker_line`: Line number where marker found
- `marker_text`: The actual comment

**Algorithm**:
```
1. Read file with Read tool
2. Search for comments containing:
   - "OLD SCHEMA"
   - "// TODO: migrate"
   - "// DEPRECATED"
3. If found:
   - has_marker = true
   - Extract line number and text
4. Return result
```

**Usage**:
```markdown
Before creating task to modify file:
  result = DetectOldSchemaMarkers(file_path)
  If result.has_marker:
    Flag as Critical: "File has OLD SCHEMA marker at line {result.marker_line}"
    Recommendation: "Create prerequisite task to migrate schema first"
```

---

## Limits

- Max files to verify per task: 50
- Max context lines for snippet: 20
- Max pattern searches: 10 per file

**Rationale**: Prevent runaway file operations, focus on critical verifications.

---

## Integration Pattern

```markdown
### Standard Verification Workflow

1. Read verification modules:
   ```
   Read(".claude/commands/_shared/file-verification.md")
   ```

2. Store operations in working memory:
   - VerifyFileExists
   - VerifyLineNumber
   - ExtractCodeSnippet
   - VerifyPatternExists
   - DetectOldSchemaMarkers

3. For each file reference in task:
   - Run VerifyFileExists
   - Run DetectOldSchemaMarkers
   - Run VerifyLineNumber (if line number provided)
   - Run ExtractCodeSnippet (if code example needed)
   - Run VerifyPatternExists (if pattern referenced)

4. Collect results and report issues
```

---

## Example: Complete File Verification

```markdown
Task references: `src/storage.zig:245 - Add description column`

Verification:
1. VerifyFileExists("src/storage.zig")
   → Result: exists=true, note="File verified: 8,234 bytes"

2. DetectOldSchemaMarkers("src/storage.zig")
   → Result: has_marker=false (no schema issues)

3. VerifyLineNumber("src/storage.zig", 245, tolerance=5)
   → Result: status=ACCURATE, note="Line 245 within valid range"

4. ExtractCodeSnippet("src/storage.zig", 245, context=10)
   → Result:
   ```zig
   240  pub fn createTask(self: *Storage, title: []const u8) !Task {
   241      const sql =
   242          \\INSERT INTO tasks (title, status, created_at)
   243          \\VALUES (?1, ?2, ?3)
   244      ;
   245      const now = utils.unixTimestamp();
   246      // ...
   ```

5. VerifyPatternExists("src/storage.zig", "allocator.dupe pattern", 156)
   → Result: found=true, actual_line=158, code_snippet=[pattern code]

**Verdict**: ✅ All verifications passed
```

---

## Error Handling

**File Not Found**:
- Return exists=false
- Include file path in note
- Caller decides severity (usually Critical)

**Line Number Out of Range**:
- Return status=WAY_OFF
- Include actual file size in note
- Caller decides severity (usually Critical if >5 lines off)

**Pattern Not Found**:
- Return found=false
- Include search details in note
- Caller decides severity (usually High)

**Read Tool Failure**:
- Return error result
- Include error message
- Caller should log and continue (don't fail entire process)

---

## Notes

This module is **read-only** - never modifies files. Only reads and reports.

Designed for both **preventive** (task-gen) and **detective** (task-audit) usage.
