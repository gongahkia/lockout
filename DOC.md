# LockOut: Structure, Purpose, Intent, and Agent-Developer Value Expansion

## 1) Repository structure and product intent

`LockOut` is a macOS menu bar application with a layered architecture:

- `LockOut-macOS/`: app lifecycle, UI, menu bar integration, onboarding, overlay presentation, and platform service integration (notifications, EventKit, launch at login, AppKit interaction).
- `Packages/LockOutCore/`: scheduling engine, settings models, persistence abstractions, analytics/insights, managed-policy resolution, sync services, and shared observability APIs.
- `LockOut-macOSUITests/`: user-journey regression coverage for onboarding, settings, and profile UX.
- `docs/` + scripts/Make targets: release/update setup and project operations.

Philosophically, LockOut is not just a timer. It is a behavior-shaping system that combines:

- environment-aware interruption timing,
- policy and role-based enforcement,
- profile automation,
- sync + managed controls,
- and history/insight loops.

That makes it well-positioned for people doing deep computer-bound work, including agent developers running long coding/eval loops.

## 2) Current value proposition for agent developers

### What was already strong

- Multiple break types with independent cadence and timers.
- Deferrals tied to context (meeting/fullscreen/app changes).
- Profile system with automation triggers (time windows, frontmost app, focus mode, calendar, external displays).
- Cloud sync and managed policy support.
- Insight generation from behavior history.

### What was missing before this expansion

- Several high-impact paths still had silent failure patterns (`try?` + no surfaced diagnostics).
- No first-class “agent workflow bootstrap” to quickly map LockOut to common agent-dev operating modes.
- No in-app diagnostics feed for runtime triage.
- Limited articulation of how LockOut maps to conventions in modern agent tooling ecosystems.

## 3) Market conventions used to evaluate fit (researched March 30, 2026)

Agent-development tooling has converged around a few baseline expectations:

1. Terminal/IDE-native flow with Git-aware iteration loops.
2. Strong traceability and observability for agent decisions and failures.
3. Evaluation and reliability feedback loops, not just one-off prompt edits.
4. Extensibility through standardized context/tool interfaces (MCP).
5. Explicit controls for risk, security boundaries, and policy governance.

Reference signals:

- Aider emphasizes terminal-native AI pair programming, codebase mapping, git-integrated changes, and lint/test loops.
  - https://github.com/Aider-AI/aider
- Langfuse positions itself as open-source LLM engineering with observability, evals, prompt management, and OpenTelemetry integration.
  - https://github.com/langfuse/langfuse
- LangSmith documents a framework-agnostic workflow spanning tracing, evaluation, prompt iteration, deployment, and production reliability.
  - https://docs.langchain.com/langsmith/home
- OpenTelemetry now publishes generative-AI semantic conventions (events/metrics/spans), including agent spans and MCP-related conventions.
  - https://opentelemetry.io/docs/specs/semconv/gen-ai/
  - https://opentelemetry.io/docs/specs/semconv/gen-ai/gen-ai-metrics/
- GitHub’s MCP guidance emphasizes MCP as a standard context/tool interface with growing local/remote support and toolset controls for accuracy/security.
  - https://docs.github.com/en/copilot/concepts/context/mcp

Inference for LockOut: agent developers expect reliability, explicit introspection, and rapid adaptation to distinct work modes. The product should therefore behave like an operational guardrail system, not only a wellness timer.

## 4) Expansion implemented in this repository

### Reliability and error transparency hardening

Implemented explicit diagnostics and removed silent-failure behavior across core and app paths.

- Added persistent diagnostics event store in core:
  - `Packages/LockOutCore/Sources/LockOutCore/Diagnostics.swift`
- Replaced silent metadata encode/decode failures with logged failures:
  - `Insights.swift`, `SettingsSyncService.swift`, `CloudKitSyncService.swift`, `BreakHistoryRepository.swift`
- Wired app-level observability to persistent diagnostics:
  - `LockOut-macOS/AppDelegate.swift`
- Hardened file logging bootstrap/write/prune lifecycle and fallback behavior:
  - `LockOut-macOS/FileLogger.swift`
- Removed silent export failures and surfaced them in UI + diagnostics:
  - `LockOut-macOS/StatisticsView.swift`
  - `LockOut-macOS/SettingsView.swift`
- Added sound-playback fallback diagnostics in overlay flow:
  - `LockOut-macOS/BreakOverlayWindowController.swift`

### Agent-developer depth and breadth expansion

Added first-class agent workflow presets and bootstrap mechanisms.

- New preset engine for agent-centric profile packs:
  - `Packages/LockOutCore/Sources/LockOutCore/AgentDeveloperPresets.swift`
- Profile editor one-click bootstrap for agent presets:
  - `LockOut-macOS/ProfileEditorView.swift`
- Onboarding includes an `Agent Developer` preset path:
  - `LockOut-macOS/OnboardingWindowController.swift`

The preset pack seeds differentiated operating modes:

- `Agent Sprint Coding`
- `Agent Eval Runs`
- `Agent Incident Response`

and creates starter automation rules (disabled by default for safe adoption).

### New verification coverage

- `AgentDeveloperPresetsTests.swift`
- `DiagnosticsStoreTests.swift`

These tests validate profile bootstrap behavior, idempotency, rule ordering, diagnostics retention, and severity counting.

## 5) How this improves real adoption for agent developers

LockOut now better supports real agent-dev use cases by default:

- Fast setup: users can onboard directly into agent-focused routines.
- Contextual control: profile/rule structures align with common agent work phases.
- Debuggability: errors are now inspectable in-app (Diagnostics section) and persisted.
- Operational safety: export/sync/audio/logging failures are not silently ignored.
- Team readiness: managed settings, policy controls, and sync metadata remain central.

## 6) In-app diagnostics workflow (recommended)

1. Open `Settings` -> `Diagnostics`.
2. Inspect error/warning counts and recent event stream.
3. Use `Refresh Diagnostics` while reproducing an issue.
4. Use `Clear Diagnostics` after triage to isolate fresh failures.
5. For deeper inspection, check file logs under `~/Library/Logs/LockOut/`.

## 7) Remaining strategic opportunities

To further strengthen LockOut as an agent-dev operational tool:

- Export diagnostics in OpenTelemetry-friendly schema for external observability backends.
- Add policy-based escalation rules (for example, force stricter mode after repeated deferrals).
- Add explicit session tagging (coding/eval/incident) to enrich insight segmentation.
- Add CLI/automation hooks for profile toggling in scripted workflows.

These are natural follow-ons now that core diagnostics and agent preset primitives are in place.
