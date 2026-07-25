---
name: xcode-snapshot
description: Use when the user wants to snapshot generated Xcode projects before making manual changes in Xcode, then diff afterwards to capture what needs to be moved into Project.swift or xcconfig files. Triggers include "snapshot xcodeproj", "diff Xcode changes", "what changed in Xcode", or "backport manual Xcode edits to Tuist".
---

# Snapshot Generated Xcode Projects

Create snapshots of all generated `.xcodeproj` files so manual Xcode changes can be diffed and backported into the Tuist manifests.

## 1. Clean and regenerate

```bash
tuist clean
find . -name "*.xcodeproj" -type d -exec rm -rf {} +
tuist install
tuist generate
```

## 2. Snapshot the freshly generated projects

```bash
find . -name "*.xcodeproj" -type d -exec sh -c 'cp -r "$1" "$1.snapshot"' _ {} \;
```

## 3. Wait for the user

Tell the user to make their changes in Xcode and let you know when done.

## 4. Diff the snapshots

When the user signals they're done:

```bash
find . -name "*.xcodeproj.snapshot" -type d | while read snapshot; do
  original="${snapshot%.snapshot}"
  echo "=== Comparing $original ==="
  diff -u "$snapshot/project.pbxproj" "$original/project.pbxproj" || true
done
```

## 5. Analyze the diff

Identify which settings need updating in `Project.swift` or xcconfig files.

**Ignore non-functional / cosmetic changes:**

- `objectVersion` changes (e.g., 55 to 56) — Xcode metadata
- Array-to-string format conversions in build settings (functionally identical)
- Added `lastKnownFileType` to file references (metadata only)
- Build setting array formatting changes

**Focus only on meaningful changes:**

- New build settings (e.g., `INFOPLIST_KEY_*` additions)
- Changed values for existing settings
- Added / removed files or dependencies
- New build phases

## 6. Clean up snapshots

```bash
find . -name "*.xcodeproj.snapshot" -type d -exec rm -rf {} +
```

## 7. Follow up with the user

Once the analysis is done, ask the user which changes to reapply to xcconfig files or project files in Tuist.
