---
description: Create a snapshot of generated Xcode projects before making manual changes, then wait for changes and show diff
---

Create snapshots of all generated .xcodeproj files to track manual Xcode changes.

Execute these steps:

1. Clean existing projects and generate fresh ones:

   ```bash
   tuist clean
   find . -name "*.xcodeproj" -type d -exec rm -rf {} +
   tuist install
   tuist generate
   ```

2. Create snapshots of the freshly generated projects:

   ```bash
   find . -name "*.xcodeproj" -type d -exec sh -c 'cp -r "$1" "$1.snapshot"' _ {} \;
   ```

3. Tell the user to make their changes in Xcode and let you know when done

4. When the user indicates they're done, show diffs using:

   ```bash
   find . -name "*.xcodeproj.snapshot" -type d | while read snapshot; do
     original="${snapshot%.snapshot}"
     echo "=== Comparing $original ==="
     diff -u "$snapshot/project.pbxproj" "$original/project.pbxproj" || true
   done
   ```

5. Analyze the diff output and identify which settings need updating in Project.swift or xcconfig files

   IMPORTANT: Ignore non-functional/cosmetic changes:
   - `objectVersion` changes (e.g., 55 to 56) - just Xcode metadata
   - Array-to-string format conversions in build settings (functionally identical)
   - Added `lastKnownFileType` to file references (metadata only)
   - Build setting array formatting changes

   Focus only on meaningful changes like:
   - New build settings (e.g., `INFOPLIST_KEY_*` additions)
   - Changed values for existing settings
   - Added/removed files or dependencies
   - New build phases

6. Clean up snapshots using:

   ```bash
   find . -name "*.xcodeproj.snapshot" -type d -exec rm -rf {} +
   ```

7. Once done, ask the user which changes to reapply to xcconfig files or project
   files in Tuist if necessary.

8. Clean up the mess.
