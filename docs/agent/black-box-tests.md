# Black-Box Tests

This file stores on-demand in-game baselines and UI-specific scenarios. Startup,
main-menu, and new-game smoke coverage is handled by
`tools\Test-GameLaunch.ps1`.

Machine-readable scenarios live in `docs/agent/black-box-scenarios.json`.
Use that file as the source of truth for repeatable coordinates, evidence
folders, and pass/defer status. This Markdown file explains policy and visual
standards.

## Full vs Incremental Tests

- `FullRegression` scenarios contain known, merged, and previously passed
  interface coverage. They are opt-in and should not be run by default.
- `Incremental` scenarios are for new issues supplied later as screenshots plus
  reproduction steps. Add the narrow failing path there first.
- After an incremental scenario passes on the latest installed build, merge it
  into the matching `FullRegression` interface scenario and deduplicate by
  interface plus point ID. Then remove it from `Incremental`.
- Default workflow should run only relevant incremental or active scenarios.
  Run full regression only when a touched source can affect many interfaces,
  before release packaging, or when the user explicitly requests it.

## Active Focus Tests

No UI scenario is permanently active. When a task targets a specific interface
or tooltip bug, move the matching scenario from below into this section for the
current work cycle. If an Active Focus Test fails, follow
`docs/agent/workflows/test-and-loop.md`; do not merely report the failure.
Remove the scenario from this section after it fully passes or is explicitly
deferred with a reason.

If continuing the recent localization work without a newer verified run, promote
the knowledge screen and clan screen scenarios first.

For hover-heavy cycles, default hover wait is 700-1500 ms and the hard cap is
3 seconds. Batch hovers within one already-open interface and capture cropped
tooltip/button regions when possible.

## Default In-Game Baseline

Run this baseline when a change affects in-game UI paths beyond smoke, hover
behavior, fixed saves, layout, or interface-specific text. It is not a global
gate because `Test-GameLaunch.ps1` already covers startup, main-menu, and a
basic new-game entry path.

- From the main menu, click `新游戏`.
- Select the default tribe.
- Select `普通` difficulty.
- Enter the main game loop.
- Confirm the HUD displays normally and no crash dialog appears.
- Confirm `Crash.AtGLog` does not receive a new timestamp during the sequence.
- Prefer a known test save or recorded World ID when available. If using a
  random start, record enough path/coordinates to reproduce the covered state.

## Fixed Save / Load Baseline

Run this baseline when a change affects fonts, large text corpora, map-loading
memory pressure, random terrain/clan state, notifications, tile hover, or
main-loop UI that depends on the current game state.

- Start from the main-menu `读取存档` screen.
- Load the current fixed local save, `Quicksave.AtGSave`, unless the Active
  Focus Test specifies another save.
- Confirm the game reaches the main loop, the process remains alive, and
  `Crash.AtGLog` does not receive a new timestamp.
- Use this same loaded state for failure reproduction and retesting. If a new
  random state exposes a new issue, save it first and record the save name and
  coordinates here before fixing.
- Latest passed evidence: `2026-06-29`, refreshed installed build, loaded
  `Quicksave.AtGSave`, screenshot `.tmp\after-load-quicksave-final2.png`,
  no `Crash.AtGLog` timestamp change.

## Completed / Deferred UI Tests By Interface

These scenarios are not permanent required tests. Run them when the touched code
or data affects the relevant UI, tooltip path, source file, DLL patch, font, or
layout behavior. If one fails, promote it to `Active Focus Tests` and follow the
automatic failure loop in `docs/agent/workflows/test-and-loop.md`.
Do not repeat a passed interface scenario unless the touched source, font,
config, DLL patch, save/load flow, or UI behavior can affect that interface.

### Top-Left Clan and Support Hover

- Hover the top-left clan/support area.
- No `TEXT.Name.Resource.*`, raw keys, mojibake, or unresolved tags should
  appear.
- Chinese resource names such as `布料` and `声望` should display.

### Knowledge Screen

- Click the top-right `未研究职业` button to open the knowledge screen.
- Hover all currently recorded knowledge-screen buttons/nodes:
  `01_huntsman 878,202`, `02_watchman 1148,202`,
  `03_feast_master 1416,202`, `04_archer 1684,202`,
  `05_honor 1280,303`, `06_hunter 1280,400`,
  `07_harvester 742,651`, `08_bread_maker 1014,651`,
  `09_winemaker 1282,651`, `10_beekeeper 1550,651`,
  `11_farmer 1822,651`, `12_agriculture 1280,752`,
  `13_reaper 1145,850`, `14_gatherer 1410,850`,
  `15_sledge_driver 744,1104`, `16_fisherman 1014,1104`,
  `17_meat_cutter 1280,1104`, `18_rancher 1550,1104`,
  `19_trapper 1815,1104`, `20_livestock 1280,1202`,
  `21_show_all 655,1296`, `22_close 1933,1296`.
- Also hover the currently recorded missed upgrade/status points:
  `23_turn_footer 1345,1300`, `24_hunter_node 1280,400`,
  `25_hunter_icon_1 1260,428`, `26_hunter_icon_2 1285,428`,
  `27_hunter_icon_3 1308,428`, `28_harvester_node 1145,850`,
  `29_harvester_icon_1 1115,878`, `30_harvester_icon_2 1142,878`,
  `31_harvester_icon_3 1170,878`, `32_gatherer_node 1410,850`,
  `33_gatherer_icon_1 1368,878`, `34_gatherer_icon_2 1394,878`,
  `35_gatherer_icon_3 1420,878`, `36_gatherer_icon_4 1446,878`,
  `37_gatherer_icon_5 1472,878`.
- Node labels and hover details must not expose `TEXT.Name.Profession.*`,
  `TEXT.Name.Discipline.*`, raw keys, mojibake, or unresolved tags.
- Profession, discipline, and status labels should display in Chinese, for
  example `采集者`, `农耕`, `当前无法学会`, and `已学会`.
- Discipline wrapper tooltips must not expose the English
  `Learning this Tech will allow...` description.
- Latest passed evidence: `2026-06-28`, latest installed build, 22 hovers at
  900 ms each, contact sheet
  `.tmp\knowledge-hover-regression3-crops-contact.png`.
- Additional latest passed evidence: `2026-06-29`, refreshed installed build
  loaded from `Quicksave.AtGSave`, 15 hovers at 1100 ms each for the missed
  turn footer, hunter, harvester, and gatherer upgrade/status points, contact
  sheet `.tmp\knowledge-new-hovers-final2\contact.png`. `Can Identify`,
  `Unidentified Deposits`, `Produces`, and raw profession keys were not visible
  in the checked tooltips. Rich-text concept links may still render with extra
  spacing around linked Chinese terms; track that as renderer polish, not a
  raw-key failure.

### Clan Screen

- Use a fixed save when testing random joined clans, clan traits, clan-card
  hovers, or clan-screen action availability. If a new random start exposes a
  clan-screen issue, save that state before fixing and record the save name,
  the three visible clan names, the six trait hover coordinates, button
  coordinates, and screenshot paths.
- Click the top-left `氏族` button.
- The clan screen opens and the game process remains alive.
- No `HE'S DEAD, JIM` crash dialog appears.
- No missing `ClanCard\农耕` or `ClanCard\冶金` asset crash appears.
- `Train Clan in Profession` displays as `训练氏族职业`.
- Hover each visible clan card and inspect the card tooltip.
- Hover the clan-screen action buttons: train profession, switch discipline,
  produce, ennoble clan, increase clan limit, declare kingdom, and close.
- Clan-card tooltips must not expose `TEXT.Name.Profession.*`, `NONE`,
  `Profession:`, `Discipline:`, `Family`, `Turns`, or English action sentence
  fragments when a safe display-only replacement exists.
- The screen title may retain generated faction names, but static labels,
  buttons, and tooltip prose should be Chinese wherever safely patchable.
- Latest action-button hover evidence: `2026-06-29`, refreshed installed build,
  loaded from `Quicksave.AtGSave`, clan screen opened with three visible clans
  `Keil`, `Edelbert`, and `Roehl`. Tested train profession, switch discipline,
  produce, ennoble clan, increase clan limit, declare kingdom, and close at
  900 ms routine hover waits, with 1500 ms retry for declare kingdom and close.
  Evidence folder: `.tmp\clan-button-hover-final`; contact sheet:
  `.tmp\clan-button-hover-final\contact.png`. No raw key, mojibake,
  `Ennoble`, `You lack sufficient`, or safely patchable English appeared in
  the checked button tooltips. Close shows only hotkey markers. Timing:
  build `7.98s` with font cache hit, install `0.8s`, smoke `11.21s`, UI hover
  sweep `26.4s` plus retry `5.78s`.

### Main-Loop Button Hover Sweep

- In the main game loop, hover every visible command button and sidebar button
  before ending the test cycle.
- Cover at least top-left menu/help icons, clan/support/resource buttons,
  top-right task buttons, right-side notification buttons, clan portrait
  buttons, and selected unit command buttons such as pack up, fortify, move,
  skip, leave, and profession/clan action buttons when visible.
- Tooltips must not show raw `TEXT.*` keys, enum names, mojibake, unresolved
  tags, or safely replaceable English UI text.
- Generated names, hotkey markers, `Clan <Name>` prefixes, and known
  logic-sensitive Common concept remnants are acceptable only while tracked in
  the agent docs.
- Do not wait more than 3 seconds for a hover tooltip. If a tooltip does not
  appear, record the coordinate and continue rather than stalling the sweep.
- Latest partial sweep evidence: `2026-06-29`, refreshed installed build
  loaded from `Quicksave.AtGSave`, 19 visible main-loop button/sidebar hovers
  at 900 ms each, contact sheet
  `.tmp\main-loop-button-hovers-final2\contact.png`. The sweep found the
  top-left system menu tooltip in English and it was fixed through UI IL
  rewrite. Targeted retest evidence:
  `.tmp\main-loop-system-menu-final3.png`.
- Deferred within this interface: selected unit command buttons were not
  visible in the current `Quicksave.AtGSave` state after selecting the nearby
  map object. Do not mark unit commands completed until a fixed save exposes
  buttons such as pack up, fortify, move, skip, leave, or profession/clan
  actions and those hover tooltips are visually checked.

### Main-Loop Tile Hover Sweep

- Use a fixed save when checking tile click or hover text. If a new random map
  exposes a tile issue, save that state before fixing and record the save name,
  tile/object type, click or hover coordinates, left-bottom panel screenshot,
  and lower-right tooltip screenshot.
- In the main game loop, hover all visibly distinct tile/object types in the
  current viewport and inspect the tooltip that appears in the lower-right
  corner.
- Cover at least selected clan/settlement tile, coast/water, open land, forest,
  hill/mountain, visible resource/deposit markers, unknown question markers,
  and any animals, structures, or camps visible in the generated start.
- Lower-right tooltips must not show raw `TEXT.*` keys, enum names, mojibake,
  unresolved tags, or safely replaceable English phrases.
- If a generated start lacks one listed type, record the missing type and cover
  another visible distinct tile instead of rerolling indefinitely.
- Use lower-right tooltip crops instead of repeated full-window screenshots
  once window capture integrity is established.

### Extended Coverage

- Cover main-menu hovers, difficulty screen, HUD, knowledge screen, pause menu,
  top task buttons, notification buttons, and resource-bar hovers when relevant.
- If entering the main game loop, use a fixed operation count or fixed time
  budget and then exit.
- Record UI test duration and the number of clicks, hovers, and screenshots
  when comparing workflow bottlenecks.
- Avoid clicking external webpages, challenge login, or forum links.

## Shared Visual Standards

- Button text should be centered.
- Chinese text should not contain artificial spaces between characters.
- Same-class buttons should have consistent spacing.
- Long tooltip text should wrap inside its panel without overlap.
- Text must not obscure icons, preceding text, or following text.
- Use cropped screenshots for button strips, tooltip panels, and lower-right
  tile tooltip regions. Use contact sheets when reviewing several crops.
