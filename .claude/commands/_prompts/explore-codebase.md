# Explore Codebase

## Variables

- `{{feature_summary}}` - Brief description of the feature being implemented
- `{{language}}` - Programming language/stack (e.g., Zig, Java/Spring, Python)
- `{{architecture}}` - Module structure and organization (e.g., CLI tool, web service)

## Prompt

**Explore the codebase yourself** using Read, Grep, and Glob tools to understand how to implement {{feature_summary}}.

**Project Context**:
- Language: {{language}}
- Architecture: {{architecture}}

**Exploration Focus**:

1. **Similar Existing Features**
   - Find implementations similar to this feature
   - Identify patterns to follow (file:line references)
   - Note any relevant utilities or helpers

2. **Architecture Patterns**
   - How is code organized? (layers, modules, packages)
   - Where would this feature fit?
   - What's the data flow? (entry → processing → storage → return)

3. **Data/State Management**
   - How is data stored? (database, files, memory)
   - What data structures are used?
   - Are there existing types/schemas to extend?

4. **Integration Points**
   - What other systems/modules will this touch?
   - Are there APIs, databases, external services involved?
   - How do existing features integrate?

5. **Testing Patterns**
   - Where are tests located?
   - What testing framework/style is used?
   - How are similar features tested?

6. **Performance Considerations**
   - Are there performance targets?
   - How do similar features optimize?
   - Any N+1 query risks or batch operation patterns?

7. **Error Handling**
   - How are errors handled in similar code?
   - What error types exist?
   - How are errors surfaced to users?

**Document findings with**:
- file:line references with code snippets
- Brief rationale for why each finding is relevant
- Verification that all file paths exist in the codebase

**If exploration finds insufficient code**:
- Report what was found/not found
- Ask user for clarification about feature or codebase structure
