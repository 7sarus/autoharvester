# WX-78 Auto-Harvester

[![CI](https://github.com/7sarus/autoharvester/actions/workflows/build.yml/badge.svg)](https://github.com/7sarus/autoharvester/actions/workflows/build.yml)
[![Star History](https://img.shields.io/github/stars/7sarus/autoharvester?style=social)](https://star-history.com/#7sarus/autoharvester&Date)

![Star History Chart](https://api.star-history.com/svg?repos=7sarus/autoharvester&type=Date)

A companion mod for Klei Entertainment's *Don't Starve* (Singleplayer: Vanilla, Reign of Giants, Shipwrecked, and Hamlet).

Spawns a scaled-down WX-78 companion that follows the player, automatically harvests nearby resources within a configurable radius, and stores items in a top-docked companion inventory.

---

## Features & What Works So Far

### 1. Autonomous Harvesting & Intelligent AI
- **Resource Gathering:** Automatically harvests and picks up nearby resources:
  - Twigs (saplings)
  - Cut Grass
  - Logs & Seeds
  - Berries & Carrots
  - Ground loot (weapons, tools, armor, pinecones, rocks, flint, etc.)
  - Flowers (including evil flowers) and mushroom plants are never picked; their slow regrowth stalls the companion
- **Tool Chores (Woodlogging & Mining):**
  - **Woodlogging:** Chops nearby trees (`ACTIONS.CHOP`) when equipped with an axe or woodcutting tool in equipment slot 16.
  - **Mining:** Mines nearby boulders and mineral deposits (`ACTIONS.MINE`) when equipped with a pickaxe in equipment slot 16.
  - Tool durability is consumed per action as normal; when a tool breaks, WX safely stops the chore.
  - Safety exclusions protect player-built structures, spider dens, and cave entrances from being mined or chopped.
- **Item Safety:** Only quest-critical or irreplaceable items (e.g. Chester Eyebone, Glommer Flower) with the `irreplaceable` tag are left untouched.
- **Pathing Recovery:** If an item cannot be reached or picked up, the AI skips it for 120 seconds instead of getting stuck in an infinite action loop.
- **Visual Harvest Ring:** Visual indicator ring shows current scan radius.

### 2. Top-Docked Companion Storage (1x15 + 3 Equip)
- **Top Margin HUD Dock:** Companion container is anchored to the top of the screen flush with the margin, mirroring the player's bottom inventory bar.
- **18 Total Slots:**
  - **Slots 1–15:** General resource storage.
  - **Slots 16–18:** Dedicated equipment slots (Head, Body, Hands). Equipment placed in these slots is worn visually by the companion.
- **Smart Overflow Routing:** Harvested items fill companion storage first; if full, items transfer to the player's inventory; if both are full, items drop safely at the companion's feet.
- **Unified Storage Toggle:** Open or close storage via hotkey (`C`), the HUD Chest button, or settings UI.

### 3. In-Game Settings UI
- **Control Panel:** Accessible via hotkey (`H`) or the `[WX]` top-right HUD button.
- **Scan Radius Stepper:** Adjust harvest radius between 10, 15, 20, 25, and 30 units in real time.
- **Larger Panel:** Wider and taller, scaled at 1.05x for easier clicking.
- **Categorized Pickup Filters:** Switch parent tabs, toggle a whole group or individual item families, and use `^` / `v` to set saved harvest priority. Unlisted pickables remain under “Other Pickables.”
- **Trap Safety:** The companion harvests sprung traps only; empty traps are ignored.
- **Master Auto-Harvest Switch:** Pause or resume harvesting on demand.

### 4. Singleplayer Engine Stability & Compatibility
- **Full DLC Support:** Verified compatible with Vanilla, Reign of Giants (RoG), Shipwrecked (SW), and Hamlet.
- **Stategraph Safety:** Zero-drain stubs for player stategraph queries (`sanity`, `hunger`, `temperature`, `grogginess`, `poisonable`) prevent crashes without affecting gameplay.
- **Flower & Pickable Handling:** Safe callbacks absorb sanity deltas (e.g. flower picking) cleanly.
- **Structured Logging:** Diagnostic logging with safe error recovery, configurable via Mod Options.

---

## Controls & Keybindings

| Function | Default Key | Mod Configuration |
| :--- | :--- | :--- |
| **Toggle UI Panel** | `H` | Configurable (H, J, K, V, B, N, F7, F8) |
| **Toggle Storage Strip** | `C` | Configurable (C, B, J, K, V) |
| **HUD Shortcuts** | `[WX]` button (top right) / Chest button | Always available |

---

## Installation

### Automatic (Symlink)
Run the included installation script to link `wx_autoharvester` to your Don't Starve mods directory:

```bash
./install.sh
```

The script automatically detects Steam and GOG mod directories on Linux and macOS. To specify a custom path, export `DONT_STARVE_MODS_DIR`:

```bash
DONT_STARVE_MODS_DIR="/path/to/dont_starve/mods" ./install.sh
```

### Manual
Copy or symlink the `wx_autoharvester/` folder directly into your game's `mods/` directory:
- **GOG (Linux):** `~/Games/gog/dont-starve/game/mods/wx_autoharvester`
- **Steam (Linux):** `~/.local/share/Steam/steamapps/common/dont_starve/mods/wx_autoharvester`
- **Windows:** `<Don't Starve Install Dir>\mods\wx_autoharvester`

Enable **WX-78 Auto-Harvester** in the in-game Mods menu.

---

## Automated Test Harness

The mod includes an offline test harness covering syntax validation and 17 comprehensive test suites:

```bash
./test.sh
```

The test runner resolves game scripts dynamically and includes standalone fallback mocks to run cleanly in CI environments without requiring a local game installation.

---

## Status

### What works (automated)
- Lua syntax validation for all mod files.
- Companion spawn and SGwilson stubs.
- Harvest AI: priority over distance, trap handling, chop/mine chores, player-target avoidance, stall recovery.
- Storage routing: companion -> player -> ground.
- Robot egg transform/deploy and settings restore.
- Container top-dock hook.

### Pending in-game verification
- 4-column filter grid fit and master checkboxes.
- Boat riding in Shipwrecked/Hamlet.
- Idle wander and leash behavior.
- Top-dock offset against combined-status/WX icons.
- Debug log HUD visibility across resolutions.
