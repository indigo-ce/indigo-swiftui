# Combolab → Indigo template backport proposals

Ideas battle-tested in `combolab-swiftui` worth folding into the Indigo template. **Proposals only — no code copied.** Each item notes why it helps every future project spun from this template, and what to watch out for.

Open PRs on `indigo-swiftui` at time of writing: **none**. So nothing to reconcile against in-flight work.

Scope note: Combolab targets iOS 18 / macOS 15 and keeps features flat in `App/Sources`; Indigo targets iOS 26 / macOS 26 and modularizes each feature into its own framework target. Those are deliberate divergences — Indigo's are the better template defaults, so they are **not** on this list. App-specific deps (NetworkImage, Gzip, Kroma, explicit GRDB/StructuredQueries) and app-specific components/views are also excluded.

---

## Tier 1 — high value, clearly generalizable

### 1. Seed the `Components` library with the battle-tested generic set

Indigo ships only `BasicButton`. Combolab has grown a set of dependency-free, genuinely reusable primitives that belong in every project:

- **`ButtonStyles`** — `glassButtonStyle()` / `glassProminentButtonStyle()` with an `iOS 26 .glass` → pre-26 `.bordered` fallback, plus a `primaryCTA()` convenience. This is the strongest fit: Indigo targets iOS 26 and this is exactly the "use Liquid Glass, degrade gracefully" pattern a template should demonstrate.
- **`HFlow`** — a proper `Layout`-conforming flow/wrap container. Comes up constantly (tag clouds, chip rows) and is annoying to rewrite.
- **`InlineNotice`** — standardized inline info/warning banner (icon + message + tint).
- **`View+PlaceholderShimmer`** (`.placeholderShimmer()`) — redaction + shimmer for loading states. Pairs naturally with the `@FetchAll` loading story.
- **`View+OnFirstAppear`** (`.once { }`) — run-once onAppear. Tiny, universally useful.
- **`ActivityView`** — `UIActivityViewController` share-sheet wrapper.
- **`ScaledImage`, `TagLabelView`, `ScrollableTabRow`, `View+OnShake`** — solid secondary candidates.

Why template-wide: these are the "I always end up writing these again" pieces. Shipping them documents the intended component conventions (public initializers, `LocalizedStringKey`, no external deps).

Watch out: keep `Components` dependency-free (it already is). `View+OnShake` and `ActivityView` are UIKit-backed — gate under `#if canImport(UIKit)` so the macOS target still builds, since Indigo is multiplatform where Combolab leans iOS.

### 2. Adopt a shared `.xctestplan` for the whole app

Combolab drives its scheme with `testAction: .testPlans([...All.xctestplan])` — one test plan aggregating every target. Indigo currently has no test plan; with features split across separate framework targets, a single plan is the clean way to "run everything" locally and in the GitHub Actions workflow.

Why template-wide: gives a canonical `⌘U` / CI entry point regardless of how many feature modules a project grows, and a home for parallelization/randomized-order/coverage settings.

### 3. Fold the OpenSpec workflow into the template

Combolab uses OpenSpec heavily (`openspec/specs`, `openspec/changes`, `changes/archive`) to drive spec-first changes. Indigo has an empty `openspec/` dir but no scaffolding or documentation.

Proposal: seed the minimal OpenSpec structure and add a short "Spec-driven changes" section to `CLAUDE.md` pointing at it. This bakes the battle-tested proposal→design→tasks→archive loop into every new project instead of re-establishing it each time.

Watch out: keep the *seeded* content empty/example-only — don't carry over Combolab's actual specs.

---

## Tier 2 — worth doing, smaller or needs a judgment call

### 4. Bump `jwt-auth-client` 1.4.0 → 2.0.0 and adopt the 2.0 refresh contract

The template advertises "JWTAuth with automatic token refresh," but pins 1.4.0. Combolab moved to 2.0.0 and, per its own agent memory, hardened a real bug: **auth refresh wiping the session on a transient network error**. The template's headline auth feature should ship the battle-tested version and the "don't clear tokens on network failure, only on genuine auth failure" behavior.

Watch out: 2.0 is a breaking API change (a new refresh contract). This is the one item that needs real code work + a look at `JWTAuthClient+Live` wiring, not a version-number bump. Propose as its own focused change.

### 5. Add a shared `JSONCoders` helper in `Core/Clients`

Combolab centralizes its `JSONEncoder`/`JSONDecoder` config (date strategy, key strategy) in one `JSONCoders.swift` instead of scattering ad-hoc coders across the API client. Small, obviously reusable, sets a good default for any project that talks to a JSON API.

### 6. Migrate the app icon to Icon Composer (`.icon`)

Combolab uses the new `AppIcon.icon` (Icon Composer) format; Indigo still uses an `Assets.xcassets` app icon. Since Indigo targets iOS 26, the modern `.icon` format (layered, Liquid-Glass-aware) is the on-brand default for a 2026 template.

Watch out: tooling/Tuist resource handling for `.icon` — verify it generates cleanly before committing.

### 7. Modernize `Package.swift` language settings

Combolab uses `swift-tools-version: 6.3` and sets `swiftLanguageModes: [.v6]`; Indigo is on `6.0`. Low-risk modernization that keeps the template current.

---

## Tier 3 — minor / optional polish

- **Align `.swift-format`** — the two configs differ (Combolab sets `tabWidth: 4`, `fileScopedDeclarationPrivacy: private`, etc.). Pick one canonical style for both repos.
- **`.gitattributes` with Git LFS** — Combolab tracks `*.db` resources via LFS. Only worth it if the template starts shipping a seed database; otherwise skip.
- **`.vscode/tasks.json`** — Combolab ships build/refresh-build-server tasks. Nice for the SourceKit-LSP editing path, but Indigo's `xbridge`/Tuist workflow may make it redundant.

---

## Explicitly NOT recommended (divergences / would be regressions)

- **Lowering deployment targets** to iOS 18 / macOS 15 — Combolab is conservative because it ships; the template should stay on 26.
- **Flattening features into `App/Sources`** — Indigo's per-feature framework targets are the better template pattern.
- **Flipping the default framework product type to dynamic** — Combolab defaults external packages to dynamic `.framework`; Indigo defaults to `.staticFramework`. Static is usually the better app-launch default; only revisit if a concrete build-time problem shows up.
- **App-specific deps/components** — NetworkImage, Gzip, Kroma, explicit GRDB/StructuredQueries, and all `Combo*`/`Character*` UI stay in Combolab.

---

## Deep dive (loop iteration 2 — no new PRs or Combolab commits since first pass)

Fleshing out the two most self-contained Tier-1 items into concrete, sequenced plans. Still design-level — no code to copy verbatim, so each stays a clean template author decision.

### 1a. `Components` seed — concrete roster + multiplatform strategy

Indigo's `Components` target builds for `.iPhone`, `.iPad`, `.mac` and must stay dependency-free. Combolab's components were written iOS-first, so the real work isn't copying — it's deciding the cross-platform contract. Split the roster by portability:

**Pure SwiftUI — ship as-is (cross-platform, no gating):**
- `HFlow` (Layout), `InlineNotice`, `ButtonStyles` (`glassButtonStyle` / `glassProminentButtonStyle` / `primaryCTA`), `ScaledImage`, `TagLabelView`, `ScrollableTabRow`, `.placeholderShimmer()`, `.once { }`.
- `ButtonStyles` already has the `#available(iOS 26, macOS 26)` glass fallback built in — it's the natural flagship of the seed since Indigo is a 26-target template.

**UIKit-backed — ship gated, or provide an AppKit path:**
- `ActivityView` (`UIActivityViewController`) — wrap in `#if canImport(UIKit)`. Optionally add a macOS `NSSharingServicePicker` sibling later; gating alone is enough for v1.
- `View+OnShake` (`UIDevice`/`UIWindow` motion) — iOS-only concept; gate under `#if os(iOS)` so it simply doesn't exist on macOS rather than faking it.
- `WebView` — Combolab's is `WKWebView` (works on both platforms via WebKit, but its `UIViewRepresentable` is iOS-only). Prefer a `WKWebView` wrapper that conditionally conforms to `UIViewRepresentable`/`NSViewRepresentable`. This is the one that needs genuine rewrite, not a port — lowest priority.

**Suggested sequence:** land the pure-SwiftUI eight first (zero-risk, immediately demonstrates conventions), then the two gated iOS-only helpers, then reconsider `WebView` only if a project needs it. Keep every public type with an explicit `public init`, `LocalizedStringKey` for user-facing strings, and a matching preview.

**Doc follow-through:** the current `CLAUDE.md` says Components is "dependency-free reusable SwiftUI components" but only ships `BasicButton`. After seeding, list the roster there so the convention is discoverable.

### 2a. Shared `.xctestplan` — concrete shape for Indigo's split targets

Because Indigo modularizes features, the generated test targets are roughly: `CoreTests`, `ComponentsTests`, `NotesListFeatureTests`, `NoteEditorFeatureTests`, plus the App target's tests. Today there's no single "run everything" surface.

Proposal shape:
- One `Indigo.xctestplan` at repo root (mirrors Combolab's `App/Resources/All.xctestplan` placement — either root or `App/Resources` is fine; root is more discoverable).
- Wire it via the App scheme's `testAction: .testPlans([...])` in `App/Project.swift`, exactly as Combolab does.
- Default config worth baking in: parallelizable targets on, randomized test order (surfaces order-dependent failures early — Combolab's agent memory notes it hit feature-test crashes, so this is battle-tested pain), and code-coverage scoped to the first-party targets only (exclude external packages).
- Keeps `tuist test` / `⌘U` / the existing GitHub Actions workflow all pointing at the same canonical set as the project grows more feature modules.

Watch out: Tuist regenerates schemes, so the test plan must be declared in the manifest (not hand-edited into the `.xcworkspace`) or it won't survive `tuist generate`.

## Deep dive (loop iteration 3 — still no new PRs or Combolab commits)

Fleshing out the remaining Tier-1/Tier-2 items. After this the proposal is saturated for the current state of both repos.

### 3a. OpenSpec seed — concrete shape

Combolab's `openspec/` is refreshingly minimal at the top: just `config.yaml` + `specs/` + `changes/` (with `changes/archive/` for finished work). No `project.md`/`AGENTS.md` needed. Seeding the template is therefore cheap:

- Commit `openspec/config.yaml` and empty (or `.gitkeep`-only) `specs/` and `changes/` directories.
- Add a short **"Spec-driven changes"** section to `CLAUDE.md`: propose → design → tasks → implement → archive, pointing at the OpenSpec skills already available in this environment (`openspec-propose`, `openspec-apply-change`, `openspec-archive-change`, etc.).
- Carry over **none** of Combolab's actual specs/changes — the value is the workflow scaffold, not the content.

Why template-wide: every project spun from Indigo starts with the same battle-tested change-management loop instead of re-inventing it; the empty dirs make the convention self-documenting.

### 4a. JWTAuth — the real gap is that the template never *demonstrates* auth

This is bigger than a version bump. Reality check on the current template:

- `CLAUDE.md` lists **"JWTAuth — Authentication with automatic token refresh"** as a key dependency.
- `Package.swift` pins `jwt-auth-client` at **1.4.0**.
- But `Core/Sources/Clients/` contains **only `NotesClient.swift`** — there is *no* `JWTAuthClient+Live`, no auth wiring, no demonstration anywhere. The headline feature is advertised but not shown.

Combolab, meanwhile, has the fully battle-tested integration plus a subtle production-bug fix baked into the 2.0 contract. The proposal is therefore two-part:

**(a) Bump to 2.0.0** — note `from: "2.0.0"` is required explicitly; SPM `from:` won't cross a major from 1.4. Kaishin maintains the library (`indigo-ce/jwt-auth-client`, local checkout at `/Users/kaishin/Developer/Projects/Indigo/jwt-auth-client`), so the library side is under your control.

**(b) Ship a template `JWTAuthClient+Live` that encodes the 2.0 refresh contract.** The battle-tested behavior to demonstrate (learned from a real "users randomly logged out" bug):

> `refreshExpiredTokens()` must destroy stored credentials **only** when the server explicitly rejects the refresh token. In the `refresh` closure, map an HTTP **401** from `/auth/refresh` to `AuthTokens.Error.refreshRejected` (the one error that wipes the keychain); let **everything else** — timeouts, DNS failures, `.invalidHTTPResponse`, `.decodingError`, transport errors — propagate untouched so tokens survive a transient outage and retry on the next authenticated request.

The old 1.4 behavior destroyed tokens on *any* refresh error, so a momentary network blip at the instant the access token expired logged the user out for real. That's exactly the kind of hard-won correctness a template should hand every future project for free.

Complementary detail worth demonstrating: treat an `.expired` auth state the same as `.valid` at app launch (load the app, refresh silently on the next request) rather than gating behind a "reconnecting" screen.

Scope note: this needs a small amount of real integration code (a `DependencyKey` conforming `+Live` and a minimal auth-state gate in the app's root), plus deciding how much of a demo auth flow the template should show. It's the highest-effort item here and deserves its own PR — but it's also the one that closes an actual gap between what `CLAUDE.md` promises and what the template delivers.

---

## Status

Proposal complete and saturated against the current state of both repos (Indigo: no open PRs; Combolab HEAD `bfd72e1`). All Tier-1 and the load-bearing Tier-2 items now have concrete, sequenced plans. Recommended order to execute: **#1 Components seed** (zero-risk, immediate) → **#2 xctestplan** → **#3 OpenSpec seed** → **#4 JWTAuth demo + 2.0 contract** (own PR, real code) → Tier-2/3 polish.

