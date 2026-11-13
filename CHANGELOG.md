**v0.2.0**

- Unlock mode: `/reverie unlock` shows every text element with a dashed outline and its name, ready to drag anywhere. Dropping one places it freely. `/reverie lock` or Escape finishes.
- New `/reverie text <element> on|off`, `anchor <TL..BR>` and `free` commands.
- Free positions are saved as a share of the screen, so they survive resolution and UI scale changes. 0.1.x settings carry over automatically.
- The away timer only shows while the AFK trigger is on.
- Text placement is worked out by tested layout code, and the overlay now sits on the game world frame.

**v0.1.1**

- The camera orbit is about a third slower.

**v0.1.0**

- First release, for WoW Forever.
- Letterbox bars and a title card (name, guild, realm, level/race/class, zone, subzone, away timer) on flight paths, flying mounts and while AFK.
- Hides the interface while the overlay is up, with an optional slow camera orbit and zoom out.
- Text fades after 10 seconds, Escape dismisses the overlay, and it never starts in combat and closes if combat begins.
- Options window (/reverie) with a live preview: show or hide each text element, place it on a 3x3 grid or freely, and toggle triggers, bars, fade and camera. Also listed in Settings > AddOns.
- "Show surname" option for Forever's two-part character names.
- Your own name above your character is hidden while the overlay is up, and restored afterwards.
