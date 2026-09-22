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

## Epic 2: Tactical Siege Combat (Completed)
Expands the assault from an instant binary dice roll into an interactive, multi-stage siege with tactical casualty choices, breach stances, duel challenges, and strategic retreat.

### Epic 2 Task Ledger
| ID | Title | Branch | Base | Mode | Blocked By | Status | PR URL | Linked? |
|---|---|---|---|---|---|---|---|---|
| TS-01 | Multi-Phase Siege Rules & Combat Resolver | feature/siege-ts01-resolver | feature/redesign-t08-acceptance | autonomous | None | pr-open | https://github.com/Arrangedgodly/castle-storm/pull/9 | Yes |
| TS-02 | Tactical Siege Presenter & Contracts | feature/siege-ts02-presenter | feature/siege-ts01-resolver | autonomous | TS-01 | pr-open | https://github.com/Arrangedgodly/castle-storm/pull/10 | Yes |
| TS-03 | Interactive Siege Tactical Viewport | feature/siege-ts03-ui | feature/siege-ts02-presenter | autonomous | TS-02 | pr-open | https://github.com/Arrangedgodly/castle-storm/pull/11 | Yes |
| TS-04 | SiegePanel & GameplayScreen Integration | feature/siege-ts04-integration | feature/siege-ts03-ui | autonomous | TS-03 | pr-open | https://github.com/Arrangedgodly/castle-storm/pull/12 | Yes |
| TS-05 | Full Tactical Siege Acceptance Sweep | feature/siege-ts05-acceptance | feature/siege-ts04-integration | autonomous | TS-04 | pr-open | https://github.com/Arrangedgodly/castle-storm/pull/13 | Yes |

---

## Epic 3: Clandestine Operations & Infiltration
Expands pre-assault strategy with covert operations (bribing gatekeepers, poisoning garrison supplies, smuggling weapons, planting informants) that create tactical breach advantages.

### Dependency Graph
- CO-01: Covert Operations Rules & Simulation System (Base: feature/siege-ts05-acceptance)
  └──> CO-02: Covert Ops Presenter & Telemetry Contracts (Base: feature/covert-co01-system) [Stacked on CO-01]
       └──> CO-03: Covert Infiltration Panel & Operation Cards (Base: feature/covert-co02-presenter) [Stacked on CO-02]
            └──> CO-04: GameplayScreen Integration & Acceptance Sweep (Base: feature/covert-co03-ui) [Stacked on CO-03]

### Epic 3 Task Ledger
| ID | Title | Branch | Base | Mode | Blocked By | Status | PR URL | Linked? |
|---|---|---|---|---|---|---|---|---|
| CO-01 | Covert Operations Simulation System | feature/covert-co01-system | feature/siege-ts05-acceptance | autonomous | None | pr-open | - | - |
| CO-02 | Covert Ops Presenter & Contracts | feature/covert-co02-presenter | feature/covert-co01-system | autonomous | CO-01 | ready | - | - |
| CO-03 | Covert Infiltration Panel & Operation Cards | feature/covert-co03-ui | feature/covert-co02-presenter | autonomous | CO-02 | blocked | - | - |
| CO-04 | GameplayScreen Integration & Acceptance Sweep | feature/covert-co04-integration | feature/covert-co03-ui | autonomous | CO-03 | blocked | - | - |

## Execution Protocol
- **Stacking**: Stacked sequential layers built on top of `feature/siege-ts05-acceptance`.
- **Validation**: Every slice must pass unit tests via `cmd.exe /c "..."` before PR creation.
- **Thread Linking**: Every PR is linked via `link_pull_request` MCP tool immediately upon opening.
