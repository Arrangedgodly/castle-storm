# PR Orchestration: Castle Storm Redesign & Gameplay Overhauls

## Overview
Redesign Castle Storm into an accessible, visually rich, and intuitive medieval strategy experience, expanded through deep tactical gameplay overhauls.

---

## Epic 1: Visual & UI Overhaul (Completed)
1. Core playable loop stabilization and structured presenter contracts.
2. Dedicated modular view components (Top HUD, Village & Production, Roster & Armory, Castle Siege).
3. Primary viewport integration and boot shell swap.
4. Visual polish, asset dressing, and acceptance test sweep.

### Epic 1 Task Ledger
| ID | Title | Branch | Base | Mode | Blocked By | Status | PR URL | Linked? |
|---|---|---|---|---|---|---|---|---|
| T-01 | Playable Action & Presenter Contracts | feature/redesign-t01-contracts | main | autonomous | None | pr-open | https://github.com/Arrangedgodly/castle-storm/pull/1 | Yes |
| T-02 | Dedicated Top HUD & Resource Bar | feature/redesign-t02-hud | feature/redesign-t01-contracts | autonomous | None (T-01 pr-open) | pr-open | https://github.com/Arrangedgodly/castle-storm/pull/2 | Yes |
| T-03 | Village & Production Panel | feature/redesign-t03-village | feature/redesign-t01-contracts | autonomous | None (T-01 pr-open) | pr-open | https://github.com/Arrangedgodly/castle-storm/pull/3 | Yes |
| T-04 | Roster & Military Armory Panel | feature/redesign-t04-roster | feature/redesign-t01-contracts | autonomous | None (T-01 pr-open) | pr-open | https://github.com/Arrangedgodly/castle-storm/pull/4 | Yes |
| T-05 | Castle Siege & Threat Panel | feature/redesign-t05-siege | feature/redesign-t01-contracts | autonomous | None (T-01 pr-open) | pr-open | https://github.com/Arrangedgodly/castle-storm/pull/5 | Yes |
| T-06 | Unified Playable Game Viewport | feature/redesign-t06-gameplay-screen | feature/redesign-t05-siege | autonomous | None (T-02..T-05 pr-open) | pr-open | https://github.com/Arrangedgodly/castle-storm/pull/6 | Yes |
| T-07 | Visual Dressing & Icon Styling | feature/redesign-t07-visuals | feature/redesign-t06-gameplay-screen | autonomous | None (T-06 pr-open) | pr-open | https://github.com/Arrangedgodly/castle-storm/pull/7 | Yes |
| T-08 | Acceptance & Playability Sweep | feature/redesign-t08-acceptance | feature/redesign-t07-visuals | autonomous | None (T-07 pr-open) | pr-open | https://github.com/Arrangedgodly/castle-storm/pull/8 | Yes |

---

## Epic 2: Tactical Siege Combat
Expands the assault from an instant binary dice roll into an interactive, multi-stage siege with tactical casualty choices, breach stances, duel challenges, and strategic retreat.

### Dependency Graph
- TS-01: Multi-Phase Siege Rules & Combat Resolver (Base: feature/redesign-t08-acceptance)
  └──> TS-02: Tactical Siege Presenter & Telemetry Contracts (Base: feature/siege-ts01-resolver) [Stacked on TS-01]
       └──> TS-03: Interactive Siege Tactical Viewport (Base: feature/siege-ts02-presenter) [Stacked on TS-02]
            └──> TS-04: SiegePanel & GameplayScreen Tactical Integration (Base: feature/siege-ts03-ui) [Stacked on TS-03]
                 └──> TS-05: Full Tactical Siege Acceptance Sweep (Base: feature/siege-ts04-integration) [Stacked on TS-04]

### Epic 2 Task Ledger
| ID | Title | Branch | Base | Mode | Blocked By | Status | PR URL | Linked? |
|---|---|---|---|---|---|---|---|---|
| TS-01 | Multi-Phase Siege Rules & Combat Resolver | feature/siege-ts01-resolver | feature/redesign-t08-acceptance | autonomous | None | pr-open | https://github.com/Arrangedgodly/castle-storm/pull/9 | Yes |
| TS-02 | Tactical Siege Presenter & Contracts | feature/siege-ts02-presenter | feature/siege-ts01-resolver | autonomous | TS-01 | pr-open | https://github.com/Arrangedgodly/castle-storm/pull/10 | Yes |
| TS-03 | Interactive Siege Tactical Viewport | feature/siege-ts03-ui | feature/siege-ts02-presenter | autonomous | TS-02 | pr-open | https://github.com/Arrangedgodly/castle-storm/pull/11 | Yes |
| TS-04 | SiegePanel & GameplayScreen Integration | feature/siege-ts04-integration | feature/siege-ts03-ui | autonomous | TS-03 | pr-open | - | - |
| TS-05 | Full Tactical Siege Acceptance Sweep | feature/siege-ts05-acceptance | feature/siege-ts04-integration | autonomous | TS-04 | ready | - | - |

## Execution Protocol
- **Stacking**: Stacked sequential layers built on top of `feature/redesign-t08-acceptance`.
- **Validation**: Every slice must pass unit tests via `cmd.exe /c "..."` before PR creation.
- **Thread Linking**: Every PR is linked via `link_pull_request` MCP tool immediately upon opening.
