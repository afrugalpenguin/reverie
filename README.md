# Reverie

Reverie hides your interface while you travel or step away, so you can just enjoy the view.


When you hop on a flight path, fly your mount or go AFK, Reverie hides your interface and adds cinema bars to the top and bottom of the screen. A small title card shows your character's name, guild and the zone you're in, and the camera can slowly drift around you while you take in the view.


As soon as you land, move or press Escape, your interface comes straight back.

## Install

Copy this folder into `World of Warcraft/_forever_/Interface/AddOns/Reverie`. The folder name must be `Reverie`.

## Use

- `/reverie` opens the options window. It's also linked from the game's Options › AddOns page.
- `/reverie preview` shows the overlay now. Press Escape to leave it.
- `/reverie stop` dismisses the overlay until the current trigger ends.
- `/reverie photo`, or the "Take photo" key binding (Options › Keybindings › Reverie), takes a photo. It hides the interface and shows framing guides with the self-timer countdown, then saves one screenshot for each shot type ticked on the Photo tab of the options window. Escape cancels. Afterwards everything comes back, and a note at the top of the screen says what was saved. Photos can't be taken in combat or while the text is unlocked.
- Automatic photos (Photo tab, "Take automatically") on level up, your first visit to a zone, an achievement or a boss kill. Each one takes a normal screenshot straight away, then a photo with your ticked types and no self-timer. If it happens in combat, the photo waits until combat ends, unless that takes more than 30 seconds.
- `/reverie unlock` shows every text element with a dashed outline and its name, even ones you've switched off. Drag any of them with the mouse to place it freely. `/reverie lock` (or Escape) finishes. Unlocking isn't allowed in combat.
- `/reverie text <element> on` or `off` shows or hides an element.
- `/reverie text <element> anchor <position>` pins an element to one of nine positions: `TL`, `TC`, `TR` (top left, middle, right), `ML`, `MC`, `MR` (middle row) or `BL`, `BC`, `BR` (bottom row).
- `/reverie text <element> free` places an element freely, at its last free position.

Elements are `name`, `guild`, `realm`, `level`, `zone`, `subzone` and `away`.

In the options window you can:

- show or hide each text element: character name, guild, realm, level/race/class, zone, subzone and away timer
- pin each one to one of nine screen positions (elements sharing a position stack in list order) or place it freely
- choose what starts the overlay: flight paths, flying mount, going AFK
- turn the letterbox bars on or off, and fade the text after 10 seconds
- turn on a slow camera orbit and zoom out

Elements pinned to the same position stack in a fixed order (name, guild, realm, level, zone, subzone, away). Top and bottom positions sit just inside the letterbox bars when they're on. Free positions are saved as a share of the screen, so they stay in place if you change resolution or UI scale. The subzone hides itself when it's empty or the same as the zone, the guild line disappears if you're not in a guild, and the away timer only appears while the AFK trigger is on.

Settings are saved per account in `ReverieDB`. Settings from 0.1.x carry over automatically. The overlay never starts in combat, and it closes if combat begins.