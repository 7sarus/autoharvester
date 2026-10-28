# WX-78 Auto-Harvester

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
  - Miscellaneous ground loot (pinecones, rocks, flint, flowers, etc.)
- **Gear Safety:** Miscellaneous loot gathering strictly excludes weapons, tools, armor, finite-use items, and irreplaceable quest objects.
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
- **Scan Radius Stepper:** Adjust harvest radius between 10, 15, 20, and 25 units in real time.
- **Target Filtering:** Individual toggle checkboxes for each harvestable category.
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

The mod includes an offline test harness covering syntax validation and 14 comprehensive test suites:

```bash
./test.sh
```

The test runner resolves game scripts dynamically and includes standalone fallback mocks to run cleanly in CI environments without requiring a local game installation.
