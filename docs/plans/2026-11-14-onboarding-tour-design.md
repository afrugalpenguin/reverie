# Onboarding tour: design

Issue #34. A hands-on walkthrough for people who have never used Reverie.

## Goal

A brand-new user learns what Reverie does by seeing it happen: the overlay, a photo, a photo key and
where the options live. It takes under a minute and can be skipped at any point.

## Who sees it, and when

- **Fresh installs** (no `ReverieDB`): the tour starts a couple of seconds after login, once per
  account. If the player is in combat, it waits until combat ends.
- **Existing users** (a save without `tourSeen`): no tour. One chat line at login: "New: /reverie
  tour shows you around." This happens once.
- **Replay** at any time with `/reverie tour` or the "Show the tour" button on Options › AddOns ›
  Reverie.
- Finishing, skipping or closing the tour with Escape marks it as seen. The current step isn't saved.
  A reload mid-tour starts it again from step 1 at the next login.

## The card

One frame in Reverie's style (`ns.UI`), about 380×200, near the top centre, parented to
`UIParent`. It has a step counter ("2 of 5"), a title, two or three short sentences, and these
buttons: Back, Skip tour and a main action button. Escape closes it, which counts as Skip.

## Steps

1. **Welcome.** What Reverie does, in one sentence. [Start]
2. **The overlay.** What starts it (flight paths, flying, AFK) and how Escape or moving brings the
   interface back. [Show me] runs `ns.Preview()`. When the interface returns: "That's the overlay.
   It starts on its own from now on." [Next]
3. **Take a photo.** Photo mode hides everything, counts down, and saves a clean screenshot.
   [Take a test photo] runs `ns.Photo.Take()`. Afterwards: where the Screenshots folder is. [Next]
4. **A photo key.** Embeds `ns.PhotoKeyButton`. Optional. [Next]
5. **Make it yours.** `/reverie` opens the options, and `/reverie tour` replays this tour.
   [Open options] or [Done].

## How the live steps work

The overlay and photo mode both hide `UIParent`, so the card disappears with the rest of the
interface and can never end up in a screenshot. When the interface comes back, the card's
`OnShow` moves a step that's waiting for its action on to its "done" text. Tour.lua doesn't hook
Core or Photo. If an action is refused (combat, no shot types ticked), the interface never hides and
the card stays where it is, with the game's usual refusal message in chat.

The action buttons are disabled in combat, with a short note explaining why.

## Saved state

- `ReverieDB.tourSeen` (boolean, account-wide). `Layout.Merge` fills it in when it's missing:
  `false` when there's no save, `true` for an existing save. An existing `true` or `false` is kept.
- `Layout.TourNews(saved)` is true only for an existing save that has no `tourSeen` yet. Core uses
  it to print the chat line.
- `ns.ResetSettings` keeps `tourSeen`, as it keeps `visited`.
- Downgrades: `Merge` passes unknown keys through and older versions ignore `tourSeen`, so it
  survives a round trip.

## Files

- `Tour.lua` (new, in the `.toc` after `PhotoOptions.lua`): the card, the steps and the navigation.
- `Layout.lua`: `tourSeen` in `Merge`, and `TourNews`.
- `Core.lua`: start the tour or print the chat line at login. Keep `tourSeen` on reset.
- `Slash.lua`: `/reverie tour`.
- `Options.lua`: a "Show the tour" button on the AddOns page.
- `README.md`: a "First time?" line.

## Testing

- Unit tests (`tests/run.lua`), written first: `Merge` with no save gives `tourSeen = false`;
  with an existing save that has no `tourSeen` it gives `true`; an existing `true` or `false` is
  kept; `TourNews` returns the right answer in each of those cases.
- In game: fresh profile, existing profile, Skip, Escape, combat (auto-start waits, buttons
  disabled), reload mid-tour, `/reverie tour`, Open options from step 5, a refused photo.
