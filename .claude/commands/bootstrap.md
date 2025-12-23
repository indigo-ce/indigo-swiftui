---
argument-hint: "Project Name"
description: Bootstrap new project from template
---

Rename this SwiftUI project template to "$ARGUMENTS". Use the todo list to keep progress trackable.

## Files to Update

Update the following files to use the new project name (search for additional files containing "Indigo Stack CE" or similar template text):

- `Tuist/ProjectDescriptionHelpers/Config.swift` - Update `teamReverseDomain` and `appTarget` with new project name
- `CLAUDE.md` - Replace "Indigo Stack CE" references with the new project name and update project-specific details
- `README.md` - Update project name and description
- `Package.swift` - Update package name if present
- Any source files in `App/Sources/` that reference the template name
- Any other files found containing "Indigo Stack CE" or template references

## Files to Delete

- `scripts/bootstrap.js` (if exists)
- `_TODO.md`
- `.build/` directory contents (build artifacts)

## Files to Rename

- If `_TODO.md` exists, rename it to `TODO.md` (replacing the current one)

## Additional Tasks

- Update the bundle identifier pattern in project configuration to match the new name
- Remove all mentions of "template" from the project
- Ensure CLAUDE.md contains project-specific architecture details, not generic template information
- Run `tuist generate` after renaming to regenerate Xcode workspace

## Project Name Formatting

- Use PascalCase for the app target name (e.g., "MyApp")
- Ensure consistency across all configuration files
