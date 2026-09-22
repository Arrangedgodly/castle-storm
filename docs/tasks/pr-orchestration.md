# PR Orchestration: Castle Storm Visual & Playable Redesign

## Overview
Redesign Castle Storm from the minimalist ink-on-paper tarot card table into an accessible, visually rich, and intuitive medieval strategy/idle experience. Sliced into phased incremental PRs:
1. Core playable loop stabilization and structured presenter contracts.
2. Dedicated modular view components (Top HUD, Village & Production, Roster & Armory, Castle Siege).
3. Primary viewport integration and boot shell swap.
4. Visual polish, asset dressing, and acceptance test sweep.

## Dependency Graph
- T-01: Playable Action & Presenter Contracts (Base: main)
  ├──> T-02: Dedicated Top HUD & Resource Bar (Base: feature/redesign-t01-contracts) [Stacked on T-01]
  ├──> T-03: Village & Production Panel (Base: feature/redesign-t01-contracts) [Stacked on T-01]
  ├──> T-04: Roster & Military Armory Panel (Base: feature/redesign-t01-contracts) [Stacked on T-01]
  └──> T-05: Castle Siege & Threat Panel (Base: feature/redesign-t01-contracts) [Stacked on T-01]
       └──> T-06: Unified Playable Game Viewport (Base: feature/redesign-t05-siege) [Stacked on T-02..T-05]
            └──> T-07: Visual Dressing & Icon Styling (Base: feature/redesign-t06-gameplay-screen) [Stacked on T-06]
                 └──> T-08: Acceptance & Playability Sweep (Base: feature/redesign-t07-visuals) [Stacked on T-07]

## Task Ledger Table
| ID | Title | Branch | Base | Mode | Blocked By | Status | PR URL | Linked? |
|---|---|---|---|---|---|---|---|---|
| T-01 | Playable Action & Presenter Contracts | feature/redesign-t01-contracts | main | autonomous | None | pr-open | https://github.com/Arrangedgodly/castle-storm/pull/1 | Yes |
| T-02 | Dedicated Top HUD & Resource Bar | feature/redesign-t02-hud | feature/redesign-t01-contracts | autonomous | None (T-01 pr-open) | pr-open | https://github.com/Arrangedgodly/castle-storm/pull/2 | Yes |
| T-03 | Village & Production Panel | feature/redesign-t03-village | feature/redesign-t01-contracts | autonomous | None (T-01 pr-open) | pr-open | https://github.com/Arrangedgodly/castle-storm/pull/3 | Yes |
| T-04 | Roster & Military Armory Panel | feature/redesign-t04-roster | feature/redesign-t01-contracts | autonomous | None (T-01 pr-open) | pr-open | https://github.com/Arrangedgodly/castle-storm/pull/4 | Yes |
| T-05 | Castle Siege & Threat Panel | feature/redesign-t05-siege | feature/redesign-t01-contracts | autonomous | None (T-01 pr-open) | pr-open | https://github.com/Arrangedgodly/castle-storm/pull/5 | Yes |
| T-06 | Unified Playable Game Viewport | feature/redesign-t06-gameplay-screen | feature/redesign-t05-siege | autonomous | None (T-02..T-05 pr-open) | pr-open | https://github.com/Arrangedgodly/castle-storm/pull/6 | Yes |
| T-07 | Visual Dressing & Icon Styling | feature/redesign-t07-visuals | feature/redesign-t06-gameplay-screen | autonomous | None (T-06 pr-open) | ready | - | - |
| T-08 | Acceptance & Playability Sweep | feature/redesign-t08-acceptance | feature/redesign-t07-visuals | autonomous | T-07 | pending | - | - |

## Execution Protocol
- **Stacking**: Branching tasks T-02 through T-05 are created from `feature/redesign-t01-contracts`.
- **Validation**: Every slice must pass unit tests via `cmd.exe /c "..."` before PR creation.
- **Thread Linking**: Every PR is linked via `link_pull_request` MCP tool immediately upon opening.
