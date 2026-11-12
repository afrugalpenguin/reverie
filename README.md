# Reverie

Reverie hides your interface while you travel or step away, so you can just enjoy the view.


When you hop on a flight path, fly your mount or go AFK, Reverie hides your interface and adds cinema bars to the top and bottom of the screen. A small title card shows your character's name, guild and the zone you're in, and the camera can slowly drift around you while you take in the view.


As soon as you land, move or press Escape, your interface comes straight back.

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