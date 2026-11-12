# Reverie

A World of Warcraft addon that turns travel and idle time into a film shot. When you take a flight path, fly a mount or go AFK, it hides the UI, adds letterbox bars, and shows a title card with your character name, guild, realm, level and zone.

## Install

Copy this folder into `World of Warcraft/_retail_/Interface/AddOns/Reverie` (or `_classic_era_`). The folder name must be `Reverie`.

## Use

- `/reverie` opens the options window. It's also linked from the game's Options › AddOns page.
- `/reverie preview` shows the overlay now. Press Escape to leave it.
- `/reverie stop` dismisses the overlay until the current trigger ends.

In the options window you can:

- show or hide each text element: character name, guild, realm, level/race/class, zone, subzone and away timer
- pin each one to one of nine screen positions (elements sharing a position stack in list order) or place it freely
- choose what starts the overlay: flight paths, flying mount, going AFK
- turn the letterbox bars on or off, and fade the text after 10 seconds
- turn on a slow camera orbit and zoom out

Settings are saved per account in `ReverieDB`. The overlay never starts in combat, and it closes if combat begins.

## Develop

```bash
luacheck .
```

```bash
lua tests/run.lua
```

The tests cover the pure layout logic in `Layout.lua` and need a Lua 5.1 interpreter.
