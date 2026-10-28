name = "WX-78 Auto-Harvester"
description = "Spawns a scaled-down WX-78 companion that follows the player, automatically harvests nearby resources, and transfers them to inventory."
author = "Modder"
version = "1.0"
forumthread = ""
api_version = 6

dont_starve_compatible = true
reign_of_giants_compatible = true
shipwrecked_compatible = true
hamlet_compatible = true

configuration_options = {
    {
        name = "KEY_TOGGLE_UI",
        label = "Toggle UI Key",
        hover = "Key to open or close the Harvester settings panel.",
        options = {
            { description = "H", data = 104 },
            { description = "J", data = 106 },
            { description = "K", data = 107 },
            { description = "V", data = 118 },
            { description = "B", data = 98 },
            { description = "N", data = 110 },
            { description = "F7", data = 288 },
            { description = "F8", data = 289 },
        },
        default = 104,
    },
    {
        name = "KEY_TOGGLE_STORAGE",
        label = "Toggle Storage Key",
        hover = "Key to open or close WX Companion storage container.",
        options = {
            { description = "C", data = 99 },
            { description = "B", data = 98 },
            { description = "J", data = 106 },
            { description = "K", data = 107 },
            { description = "V", data = 118 },
        },
        default = 99,
    },
    {
        name = "DEFAULT_RADIUS",
        label = "Default Radius",
        hover = "Initial harvest scan radius around the player.",
        options = {
            { description = "10", data = 10 },
            { description = "15", data = 15 },
            { description = "20", data = 20 },
            { description = "25", data = 25 },
        },
        default = 15,
    },
    {
        name = "DEBUG_LOGGING",
        label = "Debug Logging",
        hover = "Enable detailed diagnostics in game log.txt",
        options = {
            { description = "Verbose (Debug)", data = 1 },
            { description = "Normal (Info)", data = 2 },
            { description = "Warnings Only", data = 3 },
            { description = "Errors Only", data = 4 },
        },
        default = 2,
    },
}
