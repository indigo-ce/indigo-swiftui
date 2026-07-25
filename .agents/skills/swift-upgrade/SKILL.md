---
name: swift-upgrade
description: Use when the user asks to upgrade Swift dependencies, update Package.swift, or refresh outdated SPM packages. Triggers include "upgrade Swift dependencies", "update Swift packages", "swift outdated", or "bump dependencies".
---

# Upgrade Swift Dependencies

a. Run the command to check for outdated Swift dependencies:

```bash
swift outdated
```

b. Manually set the Swift dependencies in `Package.swift` to their latest versions, including breaking changes.

> Note: No need to verify if the project builds successfully after the update, and do not search for latest versions using any method other than the `swift outdated` command.

c. After updating the dependencies, run the following command to update the package:

```bash
tuist install
```

d. Display a list of updated dependencies, with ⚠️ in front of the dependencies that were updated to a breaking change.
