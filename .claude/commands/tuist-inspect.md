---
description: Run Tuist inspect commands to evaluate the dependency graph of the project.
---

In order to identify any issues in the dependency graph of this of this project, run the following commands:

```sh
tuist generate --no-open --cache-profile none
```

The commands should _not_ return double linked static library warnings:

> Target 'X' has been linked from target 'Y' and target 'Z', it is a static product so may introduce unwanted side effects.

If you find a static target that is linked from multiple targets, make it dynamic by adding it to Package.swift as `.framework`.

Next run:

```sh
tuist inspect implicit-imports
```

It should return.

> Loading and constructing the graph
> It might take a while if the cache is empty
> We did not find any implicit dependencies in your project.

```sh
tuist inspect redundant-imports
```

> Loading and constructing the graph
> It might take a while if the cache is empty
> We did not find any redundant dependencies in your project.

If there are any redundant or implicit dependencies raise a flag.
Implicit dependencies are fixed by making them explicit in package files,
and redundant imports are fixed by importing the target at least one in the dependent target.
