---
name: tuist-inspect
description: Use when the user asks to audit the Tuist dependency graph, check for implicit or redundant imports, or verify there are no double-linked static libraries. Triggers include "tuist inspect", "check dependency graph", "implicit imports", "redundant imports", or "double linked static libraries".
---

# Inspect Tuist Dependency Graph

Identify any issues in the dependency graph of this project.

## 1. Regenerate from scratch

```sh
tuist generate --no-open --cache-profile none
```

The command should _not_ return double-linked static library warnings:

> Target 'X' has been linked from target 'Y' and target 'Z', it is a static product so may introduce unwanted side effects.

If you find a static target that is linked from multiple targets, make it dynamic by adding it to `Package.swift` as `.framework`.

## 2. Check for implicit dependencies

```sh
tuist inspect implicit-imports
```

Expected output:

> Loading and constructing the graph
> It might take a while if the cache is empty
> We did not find any implicit dependencies in your project.

## 3. Check for redundant dependencies

```sh
tuist inspect redundant-imports
```

Expected output:

> Loading and constructing the graph
> It might take a while if the cache is empty
> We did not find any redundant dependencies in your project.

## Resolution

If any issue is reported:

- **Implicit dependencies** — make them explicit in the relevant `Package.swift` files.
- **Redundant dependencies** — import the target at least once in the dependent target.
- **Double-linked static libraries** — change the product type to `.framework` in `Package.swift`.

Raise a flag if any of these checks fail.
