# Product

<!-- impeccable:product-schema 1 -->

## Platform

desktop + mobile game (Godot 4; one custom game UI — responsive, not per-OS adaptive)

## Stack

Godot 4.x latest stable (user-chosen at intake). Single codebase; export presets for Windows/macOS/Linux (Steam Deck) first, Android later, iOS post-MVP. Data-driven content (units, buildings, gear, regimes as declarative resources/JSON).

## Users

- **Idle/incremental mobile players**: 3–5 minute check-ins several times daily; want visible progress per session, no punishment for leaving.
- **Roguelite Deck/desktop players**: 20–40 minute couch sessions; want randomized identities, real failure stakes, run-to-run variety.

## Product Purpose

Castle Storm (working title) fuses idle army-building with a roguelite restart loop: start as one peasant, build a revolution in real time (recruit, assign workers, craft gear, train knights), storm the castle when ready, then restart as a new randomized peasant living under the regime that won — including, post-MVP, your own former army. Success = a complete run loop that players restart because the reset is the narrative ("underdog topples the king, then becomes the thing they fought"), not a punishment.

## Positioning

No neighboring product combines check-in-friendly incremental production with identity-randomized roguelite restarts where the player's victorious army becomes the next cycle's oppressor. Idle games don't let you lose; roguelites don't respect 3-minute sessions. This does both.

## Operating Context

- Short daily check-ins (collect, reassign, queue, one event choice) plus longer evening/Deck sessions (upgrades, suspicion management, assault prep).
- Fully offline, single-player, local saves. Production continues in real time; offline progress resolves from timestamps at launch (capped, default 8h).
- Three input modes with full parity: touch (≥48dp targets), controller (Deck focus navigation), keyboard/mouse.
- Responsive portrait + landscape layouts from one codebase (Deck 1280×800, 1920×1080, common phone portrait sizes).

## Capabilities and Constraints

Authority for scope detail: `docs/ultron/town-hall.md` (approved scoping brief).

- MVP: 3 resources (food/timber/iron), 4 upgradeable buildings, peasant→worker/militia→trainee→knight path + parallel archer branch, 2 gear slots × 3 tiers, 4 regime flavors (1 combat modifier + 1 economy quirk each), suspicion/crackdown failure system, player-initiated auto-resolved assault with visible odds, randomized leader identities on restart.
- Failure banks full meta progress; assault is player-chosen with visible win odds.
- Post-MVP layers, one at a time: L1 persistent legacy unlock tree; L2 enemy escalation (your winning army becomes the next garrison).
- Non-goals (MVP): multiplayer, accounts, cloud sync, backend, push notifications, monetization hooks, interactive battle, localization beyond English scaffolding, iOS build.
- Save architecture: versioned schema, atomic writes, rotating slots, meta save separate from run save.
- Economy must be deterministic and headlessly simulatable (CI: full run in accelerated time, 1000h fast-forward stability).

## Brand Commitments

- Working title: **Castle Storm** (repo: castle-storm).
- Premium pay-once intent (Steam + mobile stores later); timers serve fun, never conversion. No ads, no IAP, no energy-gating.
- Clock manipulation is treated as a design nuisance (clamps/caps), never DRM or anti-cheat theater.

## Evidence on Hand

None. No art, copy, audio, or assets exist yet. MVP ships with placeholder/asset-pack art; do not fabricate screenshots, testimonials, or store claims. Art direction is decided in the design phase (shape), not in this file.

## Product Principles

1. **The reset is the story** — every system must make restarting feel like a new chapter, never a punishment.
2. **Respect the 3-minute session** — every core verb (assign, collect, queue, choose) completes in a check-in; depth comes from accumulation, not duration.
3. **Losing banks progress** — failure costs the run, never the meta.
4. **Data over code** — content lives in declarative, validated data so randomization and layers are config, not rewrites.
5. **One game, every screen** — touch, controller, and mouse parity plus responsive orientation are acceptance criteria on every UI task, not a final pass.

## Accessibility & Inclusion

Input parity is mandatory (touch/controller/kb+m). Touch targets ≥48dp; colorblind-safe resource iconography (icon+shape+text, never color alone); font scaling; Deck focus navigation everywhere.
