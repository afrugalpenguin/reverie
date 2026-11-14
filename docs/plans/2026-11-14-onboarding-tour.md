# Onboarding Tour Implementation Plan

> **For the implementer:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** A five-step, hands-on tour card for first-time Reverie users, shown once per account on
fresh installs. Design: `docs/plans/2026-11-14-onboarding-tour-design.md`. Issue #34.

**Architecture:** The pure logic (whether to show the tour, and the chat line for upgraders) lives in
`Layout.lua` and is unit tested. A new `Tour.lua` owns the card. The card is a child of `UIParent`,
so the overlay and photo mode hide it with the rest of the interface. Its `OnShow` moves a step that
was waiting for its action on to that step's "done" text. Core, Slash and Options only call
`ns.Tour.Start` and `ns.Tour.AutoLater`.

**Tech Stack:** WoW Lua 5.1 addon (Forever client, `## Interface: 16001`), plain-Lua test runner
`tests/run.lua` (run in CI; this machine has no Lua interpreter), luacheck (`luacheck .`, available
locally).

**Branch:** `feature/onboarding-tour`. This repo is linked into the game's AddOns folder as
`AddOns\Reverie`, so the game runs this branch. Adding `Tour.lua` to the `.toc` needs one full game
restart; after that `/reload` is enough.

**Conventions:** commit subjects are `type(scope): description`, at most 72 characters, with a
required scope and no co-author lines. Code comments are plain prose. Chat messages start with
`|cfff2deaeReverie|r: `.

---

### Task 1: `tourSeen` in saved settings, and `TourNews`

**Files:**
- Modify: `Layout.lua` (`DEFAULTS`, which ends with `visited = {},`, and `Layout.Merge`)
- Test: `tests/run.lua` (append before the final `print(string.format(...))` line)

**Step 1: Write the failing tests**

Append to `tests/run.lua`, before `print(string.format("%d passed, %d failed", passed, failed))`:

```lua
-- Onboarding tour -----------------------------------------------------------------

test("Tour: a fresh install hasn't seen the tour", function()
  eq(L.Merge(nil).tourSeen, false)
  eq(L.Defaults().tourSeen, false)
end)

test("Tour: an existing save from before the tour counts as seen", function()
  eq(L.Merge({ version = 2 }).tourSeen, true)
  eq(L.Merge(v011Save()).tourSeen, true)
end)

test("Tour: a saved tourSeen is kept either way", function()
  eq(L.Merge({ version = 2, tourSeen = false }).tourSeen, false)
  eq(L.Merge({ version = 2, tourSeen = true }).tourSeen, true)
end)

test("Tour: a malformed tourSeen on an existing save counts as seen", function()
  eq(L.Merge({ version = 2, tourSeen = "yes" }).tourSeen, true)
end)

test("TourNews: only an existing save without tourSeen gets the chat line", function()
  eq(L.TourNews(nil), false, "fresh install gets the tour, not the line")
  eq(L.TourNews({ version = 2 }), true)
  eq(L.TourNews({ version = 2, tourSeen = true }), false)
  eq(L.TourNews({ version = 2, tourSeen = false }), false)
end)
```

(`v011Save` is already defined in `tests/run.lua`, line 82.)

**Step 2: Push and check the tests fail in CI**

```bash
git add tests/run.lua
git commit -m "test(tour): cover tourSeen and TourNews"
git push -u origin feature/onboarding-tour
gh run list --branch feature/onboarding-tour --limit 3
```

Expected: the `Tests` run fails. Read the log with `gh run view <id> --log-failed`. The new tests
should fail with `expected false, got nil`, and the `TourNews` test with an "attempt to call field
'TourNews'" error.

**Step 3: Implement**

In `Layout.lua`, add to `DEFAULTS` right after `visited = {},`:

```lua
  -- The onboarding tour has been finished or skipped (account-wide). Merge sets it to true for a
  -- save from before the tour, so only fresh installs see it.
  tourSeen = false,
```

In `Layout.Merge`, just before the final `return out`:

```lua
  -- No save means a fresh install, which gets the tour; an older save has already learnt its way.
  if type(out.tourSeen) ~= "boolean" then out.tourSeen = type(saved) == "table" end
```

After `Layout.Merge` (before the `Layout.Positions` comment block), add:

```lua
-- True for a save from before the tour existed: those players get a chat line about
-- /reverie tour instead of the tour itself. Call it with the save before Merge.
function Layout.TourNews(saved)
  return type(saved) == "table" and type(saved.tourSeen) ~= "boolean"
end
```

**Step 4: Lint, push and check the tests pass in CI**

```bash
luacheck .
git add Layout.lua
git commit -m "feat(tour): remember whether the tour has been seen"
git push
gh run list --branch feature/onboarding-tour --limit 3
```

Expected: luacheck reports `0 warnings / 0 errors`. The `Tests` and `Luacheck` runs pass.

---

### Task 2: The tour card (`Tour.lua`)

**Files:**
- Create: `Tour.lua`
- Modify: `Reverie_Camelot.toc` (add `Tour.lua` after `PhotoOptions.lua`)

There's no unit test here because it's all frame code. Test it by hand in Task 5.

**Step 1: Create `Tour.lua`**

```lua
-- Onboarding tour: a small card that walks a new player through the overlay, a photo, the photo
-- key and the options. Shown once per account on a fresh install; /reverie tour replays it.
-- The card is a child of UIParent, so the overlay and photo mode hide it with the rest of the
-- interface (it can never end up in a photo). When the interface comes back, a step that was
-- waiting on its action moves on to its "done" text.
local _, ns = ...

local Tour = {}
ns.Tour = Tour

local PREFIX = "|cfff2deaeReverie|r: "
local AUTO_DELAY = 3 -- seconds after login, so the loading screen and login chat are out of the way

local STEPS = {
  { title = "Welcome to Reverie",
    body = "Reverie hides your interface while you travel or step away, so you can just enjoy "
      .. "the view. It also takes clean screenshots of it.",
    next = "Start" },
  { title = "The overlay",
    body = "When you take a flight path, fly your mount or go AFK, your interface fades away and "
      .. "cinema bars appear. Press Escape or move to bring it back.",
    action = "Show me",
    run = function()
      ns.Preview()
      return ns.state.active
    end,
    doneBody = "That's the overlay. From now on it starts by itself." },
  { title = "Take a photo",
    body = "Photo mode hides everything, counts down, and saves a clean screenshot.",
    action = "Take a test photo",
    run = function()
      ns.Photo.Take()
      return ns.Photo.IsRunning()
    end,
    doneBody = "Photos are saved to the Screenshots folder inside your World of Warcraft "
      .. "_forever_ folder." },
  { title = "A photo key",
    body = "Pick a key to take photos with. This is optional; you can always do it later.",
    key = true },
  { title = "Make it yours",
    body = "Type /reverie any time to choose what shows, where it goes and what starts the "
      .. "overlay. /reverie tour shows this tour again.",
    next = "Done" },
}

local UI
local card, counter, title, body, note, keyButton, back, skip, action
local index = 1
local waiting = false -- the step's action started; it's done when the interface comes back
local done = false    -- the step's action has finished, so it shows doneBody and Next

local function Render()
  local s = STEPS[index]
  counter:SetText(index .. " of " .. #STEPS)
  title:SetText(s.title)
  body:SetText(done and s.doneBody or s.body)
  keyButton:SetShown(s.key == true)
  back:SetShown(index > 1)
  skip.label:SetText(index == #STEPS and "Open options" or "Skip tour")

  local pending = s.run and not done
  action.label:SetText(pending and s.action or s.next or "Next")
  local blocked = pending and InCombatLockdown()
  action:SetEnabled(not blocked)
  action:SetAlpha(blocked and 0.5 or 1)
  note:SetShown(blocked and true or false)
end

local function Go(i)
  index, waiting, done = i, false, false
  Render()
end

local function Finish()
  ns.settings.tourSeen = true
  waiting, done = false, false
  card:Hide()
end

local function Create()
  if card then return end
  UI = ns.UI
  local C = UI.C

  card = UI.Box(UIParent, C.bg, C.border)
  card:SetSize(400, 210)
  card:SetPoint("TOP", UIParent, "TOP", 0, -120)
  card:SetFrameStrata("DIALOG")
  card:EnableMouse(true)
  card:Hide()

  counter = UI.Text(card, 11, C.muted)
  counter:SetPoint("TOPLEFT", 18, -16)
  title = UI.Text(card, 20, C.title, UI.TITLE_FONT)
  title:SetPoint("TOPLEFT", 18, -34)
  body = UI.Text(card, 13, C.text)
  body:SetPoint("TOPLEFT", 18, -68)
  body:SetWidth(364)
  body:SetSpacing(3)

  keyButton = UI.Button(card, 260, 26, "", 12)
  keyButton:SetPoint("TOPLEFT", 18, -120)
  ns.PhotoKeyButton(keyButton, function(text, listening)
    keyButton.label:SetText(text)
    UI.SetActive(keyButton, listening)
  end)

  note = UI.Text(card, 11, C.muted)
  note:SetPoint("BOTTOMLEFT", 18, 52)
  note:SetText("Not in combat. Try again when combat ends.")

  back = UI.Button(card, 80, 26, "Back", 12)
  back:SetPoint("BOTTOMLEFT", 18, 16)
  back:SetScript("OnClick", function() Go(index - 1) end)

  action = UI.Button(card, 150, 26, "", 12)
  action:SetPoint("BOTTOMRIGHT", -18, 16)
  UI.SetActive(action, true)
  action:SetScript("OnClick", function()
    local s = STEPS[index]
    if s.run and not done then
      -- Not waiting if it was refused (combat, no shot types ticked): the interface never hid.
      waiting = s.run() and true or false
      return
    end
    if index == #STEPS then return Finish() end
    Go(index + 1)
  end)

  skip = UI.Button(card, 110, 26, "", 12)
  skip:SetPoint("RIGHT", action, "LEFT", -8, 0)
  UI.SetActive(skip, false)
  skip:SetScript("OnClick", function()
    local last = index == #STEPS
    Finish()
    if last then ns.ShowOptions() end
  end)

  -- The interface came back after the overlay or a photo: that step is done.
  card:SetScript("OnShow", function()
    if waiting then
      waiting, done = false, true
    end
    Render()
  end)

  -- Escape closes the tour (counts as skipping it); every other key passes through. Same pattern
  -- as the overlay and photo mode, so Escape there never reaches this card.
  card:EnableKeyboard(true)
  card:SetPropagateKeyboardInput(true)
  card:SetScript("OnKeyDown", function(self, key)
    if InCombatLockdown() then return end
    if key == "ESCAPE" then
      self:SetPropagateKeyboardInput(false)
      Finish()
    else
      self:SetPropagateKeyboardInput(true)
    end
  end)

  card:RegisterEvent("PLAYER_REGEN_DISABLED")
  card:RegisterEvent("PLAYER_REGEN_ENABLED")
  card:SetScript("OnEvent", Render)
end

-- /reverie tour and the "Show the tour" button: start from the first step.
function Tour.Start()
  if InCombatLockdown() then
    print(PREFIX .. "the tour can start after combat.")
    return
  end
  Create()
  card:SetPropagateKeyboardInput(true)
  Go(1)
  card:Show()
end

-- At login: start the tour if it hasn't been seen, once combat allows.
local waitFrame
function Tour.Auto()
  if not ns.settings or ns.settings.tourSeen then return end
  if card and card:IsShown() then return end
  if InCombatLockdown() then
    waitFrame = waitFrame or CreateFrame("Frame")
    waitFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    waitFrame:SetScript("OnEvent", function(self)
      self:UnregisterEvent("PLAYER_REGEN_ENABLED")
      Tour.Auto()
    end)
    return
  end
  Tour.Start()
end

function Tour.AutoLater()
  C_Timer.After(AUTO_DELAY, Tour.Auto)
end
```

**Step 2: Add to the `.toc`**

In `Reverie_Camelot.toc`, add a line `Tour.lua` right after `PhotoOptions.lua`.

**Step 3: Lint**

Run `luacheck .`. Expected: `0 warnings / 0 errors`. (`UIParent`, `CreateFrame`, `C_Timer` and
`InCombatLockdown` are already in `.luacheckrc`.)

**Step 4: Commit**

```bash
git add Tour.lua Reverie_Camelot.toc
git commit -m "feat(tour): add the onboarding tour card"
```

---

### Task 3: Start it at login, keep it on reset, and the chat line

**Files:**
- Modify: `Core.lua` (`ns.ResetSettings`, the `ADDON_LOADED` and `PLAYER_LOGIN` branches)

**Step 1: Keep `tourSeen` on reset**

In `ns.ResetSettings`, update the comment and add the saved value:

```lua
function ns.ResetSettings()
  -- Not settings, so a reset keeps them: CVars still waiting to be put back, zones visited, and
  -- whether the tour has been seen.
  local restore = ns.settings and ns.settings.restore
  local visited = ns.settings and ns.settings.visited
  local tourSeen = ns.settings and ns.settings.tourSeen
  ns.settings = Layout.Defaults()
  ns.settings.restore = restore
  ns.settings.visited = visited or ns.settings.visited
  if tourSeen ~= nil then ns.settings.tourSeen = tourSeen end
  ReverieDB = ns.settings
  ns.Refresh()
end
```

**Step 2: Work out the chat line before merging**

Above `local events = CreateFrame("Frame")`, add `local tourNews = false`. In the `ADDON_LOADED`
branch, before `ns.settings = Layout.Merge(ReverieDB)`:

```lua
    tourNews = Layout.TourNews(ReverieDB)
```

**Step 3: Start the tour or print the line at login**

In the `PLAYER_LOGIN` branch, after `ns.Triggers.Begin()`:

```lua
    if tourNews then
      print("|cfff2deaeReverie|r: new: /reverie tour shows you around.")
    end
    ns.Tour.AutoLater()
```

(`Tour.Auto` does nothing once `tourSeen` is true. An upgrader's `tourSeen` was set to true by
Merge, so they get only the line.)

**Step 4: Lint and commit**

```bash
luacheck .
git add Core.lua
git commit -m "feat(tour): start the tour on first login"
```

Expected: `0 warnings / 0 errors`.

---

### Task 4: `/reverie tour` and the AddOns page button

**Files:**
- Modify: `Slash.lua` (the `SlashCmdList.REVERIE` if-chain)
- Modify: `Options.lua` (`ns.RegisterSettingsCategory`)

**Step 1: Slash command**

In `Slash.lua`, add before the final `else`:

```lua
  elseif sub == "tour" then
    ns.Tour.Start()
```

Update the header comment to `-- /reverie: options, preview, stop, photo, tour, unlock/lock, and
per-element text settings.`

**Step 2: AddOns page button**

In `Options.lua` `ns.RegisterSettingsCategory`, pull the two lines that close the game's options out
of the `open` button into a local helper. Then add a "Show the tour" button under the key button.
Define the helper at the top of the function, before `open` is created:

```lua
  local function CloseGameOptions()
    if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
    if InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then HideUIPanel(InterfaceOptionsFrame) end
  end
```

Change the `open` button's OnClick to:

```lua
  open:SetScript("OnClick", function()
    CloseGameOptions()
    ns.ShowOptions()
  end)
```

After `ns.PhotoKeyButton(key, ...)`:

```lua
  local tour = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  tour:SetSize(200, 26)
  tour:SetPoint("TOPLEFT", key, "BOTTOMLEFT", 0, -12)
  tour:SetText("Show the tour")
  tour:SetScript("OnClick", function()
    CloseGameOptions()
    ns.Tour.Start()
  end)
```

**Step 3: Lint and commit**

```bash
luacheck .
git add Slash.lua Options.lua
git commit -m "feat(tour): replay the tour from /reverie tour and options"
```

---

### Task 5: README, then test in game

**Files:**
- Modify: `README.md`

**Step 1: README**

After the opening paragraph (`For WoW Forever.`), add:

```markdown
First time? A short tour shows you around on your first login. Replay it any time with `/reverie tour` or from Options › AddOns › Reverie.
```

In the Commands list, after the `/reverie photo` bullet:

```markdown
- `/reverie tour` shows the onboarding tour again.
```

Commit and push:

```bash
git add README.md
git commit -m "docs(tour): mention the onboarding tour"
git push
```

**Step 2: In-game checklist (the user does these)**

Do a full game restart, because the `.toc` changed. Then check:

1. **Existing profile:** login prints `new: /reverie tour shows you around.` and no card appears.
   `/reload` prints nothing.
2. `/reverie tour`: the card shows step 1 of 5. Back is hidden on step 1.
3. Step 2, **Show me**: the interface and card disappear and the overlay shows. Press Escape. The
   interface returns and the card shows "That's the overlay..." with Next.
4. Step 3, **Take a test photo**: the countdown and photo happen, and the card isn't in the saved
   screenshot. Afterwards the card shows the Screenshots text.
5. Step 3 with every shot type unticked: the refusal message appears in chat, the card stays, and
   the button still says "Take a test photo".
6. Step 4: the key button sets a key, and Escape on the key button only cancels listening.
7. Step 5, **Open options**: the card closes and the Reverie window opens.
8. Escape on the card closes it. Skip closes it.
9. **Fresh profile:** log out, rename `WTF\Account\<ACCOUNT>\SavedVariables\Reverie.lua`, log in.
   The tour appears after about 3 seconds. Finish it, `/reload`, and it doesn't appear again. Put
   the old file back afterwards.
10. **Combat:** with the tour open, enter combat. The action button greys out and the note shows.
    Leaving combat restores both. `/reverie tour` in combat prints "the tour can start after
    combat."
11. **Reset:** reset settings in the options. The tour doesn't come back at the next login.

**Step 3: When the checklist passes**

Use superpowers:finishing-a-development-branch and open a PR with `Closes #34`.
