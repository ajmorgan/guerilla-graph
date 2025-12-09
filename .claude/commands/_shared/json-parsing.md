# JSON Parsing Module

Reusable JSON parsing operations for extracting structured data from agent responses.

## Purpose

Provides standard algorithms for parsing audit results from agent prose responses, with fallback parsing for unstructured text.

---

## Operation 1: Extract JSON Block

**Purpose**: Extract JSON from markdown code fence in agent response

**Input**:
- `response`: Full agent response text (string)

**Output**:
- `json_text`: Extracted JSON string (or null if not found)
- `parse_method`: "structured" | "not_found"
- `note`: Context about extraction result

**Algorithm**:
```
1. Search for ```json marker in response
2. If found:
   - Extract content between ```json and closing ```
   - Trim whitespace
   - json_text = extracted content
   - parse_method = "structured"
   - note = "Found JSON block with {length} chars"
3. If not found:
   - json_text = null
   - parse_method = "not_found"
   - note = "No JSON block found, will use fallback parsing"
4. Return result
```

**Usage**:
```markdown
result = ExtractJSONBlock(agent_response)
If result.parse_method == "structured":
  audit_result = JSON.parse(result.json_text)
Else:
  audit_result = FallbackParseFindings(agent_response)
```

---

## Operation 2: Fallback Parse Findings

**Purpose**: Extract findings from unstructured prose when no JSON block present

**Input**:
- `response`: Agent response text without JSON block

**Output**:
- `findings`: Array of finding objects {severity, issue, line_number}
- `counts`: {critical: int, high: int, medium: int, low: int}
- `parse_method`: "fallback"

**Algorithm**:
```
1. Initialize findings = [], counts = {critical: 0, high: 0, medium: 0, low: 0}
2. Split response into lines
3. For each line:
   - Search for severity keywords (case-insensitive):
     - "CRITICAL" | "Critical" → severity = "Critical"
     - "HIGH" | "High" → severity = "High"
     - "MEDIUM" | "Medium" → severity = "Medium"
     - "LOW" | "Low" → severity = "Low"
   - If severity found:
     - Extract issue text (rest of line after severity keyword)
     - Trim whitespace
     - Create finding: {severity, issue, line_number: null}
     - Add to findings array
     - Increment counts[severity.toLowerCase()]
4. Return {findings, counts, parse_method: "fallback"}
```

**Usage**:
```markdown
result = FallbackParseFindings(agent_response)
For each finding in result.findings:
  Report issue with severity level
```

---

## Operation 3: Parse Audit Result

**Purpose**: Parse complete audit result from agent response (structured or fallback)

**Input**:
- `response`: Full agent response text

**Output**:
- `task_id`: Task identifier (or null)
- `status`: "PASS" | "NEEDS_WORK" | "UNKNOWN"
- `findings`: Array of findings {severity, issue, line_number}
- `counts`: {critical: int, high: int, medium: int, low: int}
- `summary`: Summary text (or null)
- `parse_method`: "structured" | "fallback" | "failed"

**Algorithm**:
```
1. Try structured parsing first:
   - result = ExtractJSONBlock(response)
   - If result.parse_method == "structured":
     - Try: JSON.parse(result.json_text)
     - Extract: task_id, status, findings, summary
     - Calculate counts from findings array
     - Return {task_id, status, findings, counts, summary, parse_method: "structured"}
     - On parse error: continue to fallback

2. Fallback parsing:
   - fallback = FallbackParseFindings(response)
   - Determine status:
     - If counts.critical > 0 OR counts.high > 0: status = "NEEDS_WORK"
     - Else if any findings: status = "NEEDS_WORK"
     - Else: status = "PASS"
   - Extract task_id by searching for pattern:
     - Search for "[task_id]:" or "Task: [task_id]"
     - Extract task_id string
   - Return {task_id, status, findings: fallback.findings, counts: fallback.counts, summary: null, parse_method: "fallback"}

3. If both fail:
   - Return {task_id: null, status: "UNKNOWN", findings: [], counts: {critical: 0, high: 0, medium: 0, low: 0}, summary: null, parse_method: "failed"}
```

**Usage**:
```markdown
For each agent_response in parallel_audits:
  result = ParseAuditResult(agent_response)

  If result.status == "NEEDS_WORK":
    needs_work_tasks.add(result.task_id)

  Log findings:
    For each finding in result.findings:
      Print: "[{severity}] {issue}"
```

---

## Limits

- Max response size: 100KB (prevent memory issues)
- Max findings per response: 100
- Max issue text length: 500 chars (truncate if longer)

**Rationale**: Prevent runaway parsing, focus on actionable findings.

---

## Integration Pattern

```markdown
### Standard Parsing Workflow

1. Read parsing module:
   ```
   Read(".claude/commands/_shared/json-parsing.md")
   ```

2. Store operations in working memory:
   - ExtractJSONBlock
   - FallbackParseFindings
   - ParseAuditResult

3. For each agent audit response:
   - Run ParseAuditResult(response)
   - Check result.status
   - Process findings array
   - Update task state based on status

4. Aggregate results across all responses
```

---

## Example: Complete Parsing Flow

```markdown
Agent Response (structured):
```
Task auth:001 audit complete:

```json
{
  "task_id": "auth:001",
  "status": "NEEDS_WORK",
  "findings": [
    {"severity": "Critical", "issue": "File path doesn't exist: src/auth.zig", "line_number": null},
    {"severity": "High", "issue": "Missing validation command", "line_number": 45}
  ],
  "summary": "Task needs correct file paths and validation steps"
}
```
```

Parsing:
1. ExtractJSONBlock(response)
   → Result: json_text=[JSON content], parse_method="structured"

2. JSON.parse(json_text)
   → Result: {task_id: "auth:001", status: "NEEDS_WORK", findings: [...]}

3. ParseAuditResult returns:
   {
     task_id: "auth:001",
     status: "NEEDS_WORK",
     findings: [
       {severity: "Critical", issue: "File path doesn't exist: src/auth.zig", line_number: null},
       {severity: "High", issue: "Missing validation command", line_number: 45}
     ],
     counts: {critical: 1, high: 1, medium: 0, low: 0},
     summary: "Task needs correct file paths and validation steps",
     parse_method: "structured"
   }

**Verdict**: ✅ Structured parsing successful, task needs work
```

---

## Example: Fallback Parsing

```markdown
Agent Response (unstructured):
```
Auditing task auth:001...

Critical: File src/auth.zig doesn't exist in codebase
High: Missing test validation steps in How section
Medium: Consider adding error handling example

Overall the task needs refinement before implementation.
```

Parsing:
1. ExtractJSONBlock(response)
   → Result: json_text=null, parse_method="not_found"

2. FallbackParseFindings(response)
   → Result: findings=[
       {severity: "Critical", issue: "File src/auth.zig doesn't exist in codebase", line_number: null},
       {severity: "High", issue: "Missing test validation steps in How section", line_number: null},
       {severity: "Medium", issue: "Consider adding error handling example", line_number: null}
     ], counts: {critical: 1, high: 1, medium: 1, low: 0}

3. ParseAuditResult returns:
   {
     task_id: "auth:001",
     status: "NEEDS_WORK",
     findings: [...],
     counts: {critical: 1, high: 1, medium: 1, low: 0},
     summary: null,
     parse_method: "fallback"
   }

**Verdict**: ✅ Fallback parsing successful, task needs work
```

---

## Error Handling

**Invalid JSON in structured block**:
- Log parse error
- Fall back to FallbackParseFindings
- Continue processing (don't fail)

**No findings found in either method**:
- Assume status = "PASS"
- Return empty findings array
- Log warning about ambiguous response

**Malformed severity keywords**:
- Skip line
- Continue scanning (don't fail entire parse)

**Response too large**:
- Truncate to 100KB
- Parse truncated content
- Log warning about truncation

---

## Notes

This module is **read-only** - never modifies responses, only parses and reports.

Designed for **robust parsing** - always returns a result, falls back gracefully when structured parsing fails.

**Severity mapping**: Case-insensitive keywords map to consistent casing (Critical, High, Medium, Low).
