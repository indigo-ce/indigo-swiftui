---
name: xbridge
description: "Use when working with Xcode projects — building, testing, reading files, searching code, or running SwiftUI previews. Triggers include: 'build Xcode project', 'run tests', 'xbridge', 'Xcode MCP', or any Xcode development task."
---

# xbridge Skill

This skill enables AI agents to interact with Xcode projects. The preferred method is the **xbridge CLI**, which works without per-session permission dialogs. The Xcode MCP bridge (`xcrun mcpbridge`) is supported as a manual fallback but requires approving a dialog in Xcode at the start of every new session.

## Step 1: Check for xbridge

Before attempting any Xcode task, run:

```bash
which xbridge
```

If found, verify the bridge is running:

```bash
xbridge status
```

If the output indicates the bridge is not running, tell the user:

> **The Xcode MCP bridge isn't running.** Please make sure Xcode is open with a project, then run:
>
> ```
> xbridge restart
> ```
>
> If this is your first time connecting, Xcode may show a permission dialog — click **Allow** to proceed.

Wait for the user to confirm before continuing.

If found and bridge is running, skip to [Using xbridge](#using-xbridge).

If not found, ask the user:

> **xbridge is not installed. How would you like to connect to Xcode?**
>
> **Option A (recommended):** Install xbridge via Homebrew — no per-session dialogs, full CLI access.
>
> **Option B:** Set up the Xcode MCP bridge manually — requires approving a permission dialog in Xcode at the start of every Claude Code session.

## Option A: Install xbridge

```bash
brew tap 4rays/tap
brew install xbridge
```

Confirm the install:

```bash
xbridge status
```

Enable Xcode MCP: open **Xcode > Settings** (⌘,) → **Intelligence** → enable **Xcode Tools** under Model Context Protocol.

Then open your project in Xcode and proceed to [Using xbridge](#using-xbridge).

## Option B: Xcode MCP Bridge (manual setup)

### 1. Enable Xcode MCP in Settings

1. Open **Xcode > Settings** (⌘,)
2. Select **Intelligence** in the sidebar
3. Under **Model Context Protocol**, toggle **Xcode Tools** ON

### 2. Add the server to Claude Code

```bash
claude mcp add --transport stdio xcode -- xcrun mcpbridge
claude mcp list
```

### 3. For Codex

```bash
codex mcp add xcode -- xcrun mcpbridge
codex mcp list
```

### 4. Grant permission

When the client first connects, Xcode shows a permission dialog — click **Allow**. This dialog reappears every new session.

MCP tools available: `XcodeRead`, `XcodeWrite`, `XcodeUpdate`, `XcodeGlob`, `XcodeGrep`, `XcodeLS`, `XcodeMakeDir`, `XcodeRM`, `XcodeMV`, `XcodeListWindows`, `XcodeListNavigatorIssues`, `XcodeRefreshCodeIssuesInFile`, `BuildProject`, `GetBuildLog`, `RunAllTests`, `RunSomeTests`, `GetTestList`, `ExecuteSnippet`, `RenderPreview`, `DocumentationSearch`.

## Using xbridge

### Prerequisites

- xbridge installed (`brew install xbridge` via the `4rays/tap` tap)
- Xcode running with a project open
- Xcode MCP enabled in **Xcode > Settings > Intelligence > Model Context Protocol**

### Get a Tab ID First

Most commands require a tab ID. Always start with:

```bash
xbridge list-windows
```

This returns identifiers like `windowtab1`, `windowtab2`. Use the relevant one in subsequent commands.

## Timeouts

Build, test, and log commands can run for minutes on large projects. Always pass `--timeout` when calling these via `xbridge call`, or set a generous shell timeout. Start conservative and scale up:

| Project size                  | Suggested timeout |
| ----------------------------- | ----------------- |
| Small (toy/sample)            | 1 min             |
| Medium (single app)           | 5 min             |
| Large (monorepo/many targets) | 15+ min           |

Commands most likely to need a timeout: `build`, `test`, `test-run`, `build-log`, `refresh-issues`.

## Commands Reference

### Daemon & Status

| Command           | Description                   |
| ----------------- | ----------------------------- |
| `xbridge status`  | Show daemon and bridge status |
| `xbridge stop`    | Stop the daemon               |
| `xbridge restart` | Restart the Xcode MCP bridge  |

### Discovery

| Command                           | Description                               |
| --------------------------------- | ----------------------------------------- |
| `xbridge tools`                   | List all MCP tools from Xcode             |
| `xbridge tool-schema <ToolName>`  | Show input schema for a tool              |
| `xbridge call <ToolName> [json]`  | Call any MCP tool with optional JSON args |
| `xbridge list-windows`            | List open Xcode windows and tabs          |

### File Operations

| Command                                       | Description                   |
| --------------------------------------------- | ----------------------------- |
| `xbridge read <file> <tab-id>`                | Read a file                   |
| `xbridge write <tab-id> <path> <content>`     | Create or overwrite a file    |
| `xbridge update <tab-id> <path> <old> <new>`  | Replace text in a file        |
| `xbridge ls <tab-id> <path>`                  | List files at path            |
| `xbridge glob <tab-id> [pattern]`             | Find files matching a pattern |
| `xbridge grep <pattern> <tab-id> [path]`      | Search file contents          |
| `xbridge mkdir <tab-id> <path>`               | Create a directory            |
| `xbridge rm <tab-id> <path>`                  | Remove a file or directory    |
| `xbridge mv <tab-id> <src> <dst>`             | Move or rename a file         |

### Build & Test

| Command                                            | Description                             |
| -------------------------------------------------- | --------------------------------------- |
| `xbridge build <tab-id>`                           | Build the project                       |
| `xbridge build-log <tab-id>`                       | Show the build log                      |
| `xbridge test <tab-id>`                            | Run all tests                           |
| `xbridge test-list <tab-id>`                       | List available tests                    |
| `xbridge test-run <tab-id> <target> <identifier>`  | Run a specific test                     |
| `xbridge issues <tab-id> [severity]`               | Show build issues (severity: `error`\|`warning`\|`remark`, default: `error`) |
| `xbridge refresh-issues <tab-id> <file>`           | Refresh compiler diagnostics for a file |

### Advanced

| Command                                          | Description                          |
| ------------------------------------------------ | ------------------------------------ |
| `xbridge exec <tab-id> <file> <purpose> <code>`  | Execute a Swift code snippet         |
| `xbridge preview <tab-id> <file> [index]`        | Render a SwiftUI preview             |
| `xbridge docs <query> [framework]`               | Search Apple Developer Documentation |

## Common Workflows

### Build a project

```bash
xbridge list-windows
# → windowtab1  /path/to/Project.xcodeproj

xbridge build windowtab1
xbridge build-log windowtab1
```

### Run tests

```bash
xbridge list-windows
xbridge test-list windowtab1
# Output truncates on large projects — full list written to path in `fullTestListPath` field
xbridge test windowtab1
# or a specific test — parentheses () required in identifier or test won't be found:
xbridge test-run windowtab1 MyTarget 'MyTests/testSomething()'
```

### Edit a file

```bash
xbridge update windowtab1 Sources/MyView.swift 'Text("Hello")' 'Text("Hello, World!")'
```

### Search code

```bash
xbridge grep "someFunction" windowtab1 Sources/
```

### Get Xcode issues

```bash
xbridge list-windows
# → windowtab1  /path/to/Project.xcodeproj

xbridge issues windowtab1
# Lists errors only (default)

xbridge issues windowtab1 warning
# Lists warnings and above

xbridge issues windowtab1 remark
# Lists everything

# Refresh diagnostics for a specific file first if issues are stale.
# Path is relative to workspace root (ProjectName/Path/To/File.swift):
xbridge refresh-issues windowtab1 MyApp/Sources/MyView.swift
xbridge issues windowtab1
```

### Search documentation

```bash
xbridge docs "SwiftUI List" SwiftUI
```

> **Note:** `docs` output can be large (30KB+). Use narrow, specific queries and pass a framework name to limit results.

## Troubleshooting

**xbridge not found**
Install with `brew tap 4rays/tap && brew install xbridge`.

**`xbridge status` shows daemon not running**
Run `xbridge restart` and ensure Xcode is open with a project.

**No tab IDs from `xbridge list-windows`**
Xcode must be running with a project open. Run `open MyApp.xcodeproj` first.

**Xcode MCP not enabled**
Go to **Xcode > Settings > Intelligence > Model Context Protocol** and enable Xcode Tools.

**MCP permission denied (bridge fallback)**
In Xcode Settings, revoke the process entry under MCP, reconnect to trigger the dialog, then click **Allow**.

## Project Context

Add an `AGENTS.md` or `CLAUDE.md` in your project root:

```markdown
# Project Context

## Build System

- iOS 18 SwiftUI project
- Main scheme: MyApp

## Testing

- Test scheme: MyAppTests

## Project Structure

- Sources in: Sources/
- Tests in: Tests/
```

## Resources

- [Apple MCP Documentation](https://developer.apple.com/documentation/xcode/giving-external-agents-access-to-xcode)
