# Audit Plan

## Variables

- `{{plan_path}}` - Path to the plan file (e.g., PLAN.md)
- `{{plan_content}}` - Full content of the plan file

## Prompt

Audit the implementation plan at {{plan_path}} for maintainability and implementability.

CRITICAL: You must return findings in this exact JSON format at the end of your response:

```json
{
  "findings": [
    {
      "severity": "Critical|High|Medium|Low",
      "category": "Maintainability|Implementability|Missing|TigerStyle",
      "section": "Phase N: Name" or "File Change Summary",
      "line_number": 123,
      "issue": "Brief description of the issue",
      "recommendation": "Specific fix to apply",
      "verification": "How to verify the fix (file:line to check)"
    }
  ],
  "summary": {
    "critical": 0,
    "high": 0,
    "medium": 0,
    "low": 0
  }
}
```

Review the plan for:

**Maintainability Issues:**
1. Are phases too large? (Target: <200 lines in plan, single-focused scope)
2. Are file changes specific with line numbers?
3. Are pattern references verified against actual codebase? (Read the files!)
4. Are dependencies between phases clear?
5. Are success criteria measurable?
6. Are N+1 query risks analyzed?

**Implementability Issues:**
1. Can each phase be implemented independently?
2. Are all methods/functions verified to exist? (Check implementation files from PLAN.md)
3. Are function signatures at correct line numbers? (Check files mentioned in PLAN.md)
4. Are error cases enumerated?
5. Are performance targets realistic?
6. Do all TODOs marked for removal actually exist at those line numbers?

**Missing Elements:**
1. Are all affected files in File Change Summary?
2. Are documentation updates included? (CLAUDE.md, README.md)
3. Are integration points identified?

**Coding Standards Adherence** (if project uses Tiger Style or similar):
1. Are assertions mentioned (2+ per function)?
2. Are explicitly-sized types specified (if applicable to language)?
3. Are resource management patterns documented (RAII, defer, etc.)?
4. Are function size limits mentioned (if project has standards)?

**Verification Requirements:**
- For every pattern reference (file:line), READ that file and verify:
  - File exists
  - Line number is approximately correct (±10 lines acceptable if function moved)
  - Pattern described actually matches the code
- For every TODO removal claim, grep for that TODO and verify it exists
- For every method/function call referenced, verify it exists in the codebase

**Design Decision Validation:**
CRITICAL: Before flagging breaking changes or architectural decisions as issues:
1. Read the plan's "Goals" and "Non-Goals" sections (typically near the top)
2. Read the "Risk Assessment" or "Breaking Changes" section if present
3. Check if the issue you found is explicitly mentioned as:
   - An intentional design decision (in Goals/Non-Goals)
   - An acknowledged breaking change with documented mitigation
   - Part of the plan's stated architecture or approach

**Breaking Change Classification:**
- **Critical**: Breaking change that appears unintentional or undocumented
- **Medium**: Breaking change that is intentional but poorly documented in the plan
- **Low**: Breaking change that is well-documented with clear mitigation strategy

Only flag intentional, well-documented breaking changes as Low severity with recommendation to verify the documentation is clear. Never suggest reversing a design decision that is explicitly stated in the plan's Goals or Non-Goals.

After your analysis, provide the JSON findings block.
