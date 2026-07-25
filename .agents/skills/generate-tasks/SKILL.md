---
name: generate-tasks
description: Use when the user asks to generate a task list, break a PRD into tasks, or scaffold a TODO.md from a product requirements document. Triggers include "generate tasks", "create a task list", "break this PRD into tasks", or "scaffold TODO.md".
---

# Generate Task List from PRD

Guide an AI assistant in creating a detailed, step-by-step task list in Markdown format based on an existing Product Requirements Document (PRD). The task list should guide a developer through implementation.

## Output

- **Format:** Markdown (`.md`)
- **Location:** `./TODO.md`

The generated task list _must_ follow this structure:

```markdown
## Tasks

- [ ] Parent Task Title
  - [ ] Sub-task description
  - [ ] Sub-task description
- [ ] Parent Task Title
  - [ ] Sub-task description
- [ ] Parent Task Title (may not require sub-tasks if purely structural or configuration)
```

## Target Audience

Assume the primary reader of the task list is a **developer** who will implement the feature.
