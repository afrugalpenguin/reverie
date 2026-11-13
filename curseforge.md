# Reverie

Reverie hides your interface while you travel or step away, so you can just enjoy the view, and takes clean screenshots of it when you want to keep one.

For WoW Forever.

## The overlay

When you hop on a flight path, fly your mount or go AFK, Reverie hides your interface and adds cinema bars to the top and bottom of the screen. A small title card shows your character's name, guild and the zone you're in, and the camera can slowly drift around you while you take in the view.

As soon as you land, move or press Escape, your interface comes straight back.

The text can fade after 10 seconds without mouse movement; move the mouse and it comes back. The overlay never starts in combat, and it closes if combat begins.

## Photo mode

`/reverie photo`, or the "Take photo" key binding (Options › Keybindings › Reverie), takes a photo. Reverie hides the interface, shows framing guides during the self-timer countdown, then saves one screenshot for each shot type ticked on the Photo tab, about a second apart:

- **Clean**: just the view.
- **Stamped**: with your name, guild, zone and date in a corner.
- **Vignetted**: with darkened edges.
- **Saturated** and **Sepia**: warm colour tints.

Nameplates, other players' names and (optionally) other addons' extras such as waypoint arrows are hidden for the shot. Escape cancels. Afterwards everything comes back, including any game settings Reverie changed for the shot, even if the game crashed or reloaded part-way. A note at the top of the screen says what was saved. Screenshots go to the game's usual Screenshots folder.

Photos are never taken in combat or while the text is unlocked.

### Automatic photos

Reverie can also take photos by itself (Photo tab, "Take automatically") when you level up, visit a zone for the first time, earn an achievement or defeat a boss. Each one takes a normal screenshot with your interface straight away, then a photo with your ticked shot types and no self-timer. If it happens in combat, the photo waits until combat ends, unless that takes more than 30 seconds. Level up is on by default; the others are off.

The zone you log in to doesn't count as a first visit, and zones are remembered per character.

## Commands

- `/reverie` opens the options window. It's also linked from the game's Options › AddOns page.
- `/reverie preview` shows the overlay now. Press Escape to leave it.
- `/reverie stop` dismisses the overlay until the current trigger ends.
- `/reverie photo` takes a photo.
- `/reverie unlock` shows every text element with a dashed outline and its name, even ones you've switched off. Drag any of them with the mouse to place it freely. `/reverie lock` (or Escape) finishes. Unlocking isn't allowed in combat.
- `/reverie text <element> on` or `off` shows or hides an element.
- `/reverie text <element> anchor <position>` pins an element to one of nine positions: `TL`, `TC`, `TR` (top left, middle, right), `ML`, `MC`, `MR` (middle row) or `BL`, `BC`, `BR` (bottom row).
- `/reverie text <element> free` places an element freely, at its last free position.

Elements are `name`, `guild`, `realm`, `level`, `zone`, `subzone` and `away`.

## Options

The options window has a live preview and two tabs.

**Text**

- show or hide each text element: character name, guild, realm, level/race/class, zone, subzone and away timer
- pin each one to one of nine screen positions or place it freely
- choose what starts the overlay: flight paths, flying mount, going AFK
- turn the letterbox bars on or off, fade the text after 10 seconds, and show or hide your surname
- turn on a slow camera orbit and zoom out

Elements pinned to the same position stack in a fixed order (name, guild, realm, level, zone, subzone, away). Top and bottom positions sit just inside the letterbox bars when they're on. Free positions are saved as a share of the screen, so they stay in place if you change resolution or UI scale. The subzone hides itself when it's empty or the same as the zone, the guild line disappears if you're not in a guild, and the away timer only appears while the AFK trigger is on.

**Photo**

- shot types to save, with a preview of each look
- stamp: which lines to show (name, guild, zone, date) and which corner
- vignette strength
- frame guide: full, film 2.39:1, square or portrait 9:16 (a guide only; the saved file is always the full screen)
- camera: current, portrait (facing you), profile (side on) or wide (zoomed out)
- self-timer: off, 3, 5 or 10 seconds
- during the shot: hide nameplates, hide player names, hide addon extras
- file: JPG or PNG, and quality
- take automatically: level up, first visit to a zone, achievement, boss defeated

## Install

Install with the CurseForge app, or unzip the download into `World of Warcraft/_forever_/Interface/AddOns`. The folder must be named `Reverie`.

Settings are saved per account in `ReverieDB`. Settings from 0.1.x carry over automatically.
