# Black-Box Tests

This file stores on-demand in-game baselines and UI-specific scenarios. Startup
and main-menu smoke coverage is handled by `tools\Test-GameLaunch.ps1`.
New-game and fixed-save coverage are explicit black-box baselines, not default
install smoke.

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
gate because default install smoke only proves startup and main-menu rendering.
Use this baseline explicitly when random new-game entry matters.

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
- For fixed-save baselines, open `读取存档` from the main menu. Do not use an
  in-game pause/main-loop load screen unless the scenario explicitly says it is
  testing that UI variant.
- Load the fixed save named by the scenario. Use `Quicksave.AtGSave` only when
  it exists and no scenario-specific save is recorded; the Religion screen
  scenario uses `v1.4.1   World [OAA-JUH]   游戏开始.AtGSave`.
- Confirm the game reaches the main loop, the process remains alive, and
  `Crash.AtGLog` does not receive a new timestamp.
- Use this same loaded state for failure reproduction and retesting. If a new
  random state exposes a new issue, save it first and record the save name and
  coordinates here before fixing.
- Latest passed evidence: `2026-06-29`, refreshed installed build, loaded
  `Quicksave.AtGSave`, screenshot `.tmp\after-load-quicksave-final2.png`,
  no `Crash.AtGLog` timestamp change.
- Latest passed evidence: `2026-07-02`, installed build loaded
  `Quicksave.AtGSave` from the main-menu load screen, not from the in-game
  pause/load UI. Scenario
  `load-save-main-loop-tile-tooltip-20260702` completed with 3 clicks,
  8 hovers, 9 screenshots, and contact sheet
  `.tmp\runs\20260702-221952-load-save-main-loop-tile-tooltip-20260702\contact.png`.
  Covered main-menu load hover, load-save row age, delete-old-saves hover,
  top main-loop strategic/note/religion/victory hovers, nested `[HOTKEY:F11]`
  tooltip, and the fixed stream/hill/grassland lower-right tile description.
- Latest repeated-load evidence: `2026-07-14`, `DynamicCjk` installed build,
  fixed save `v1.4.1   World [BVT-LCL]   游戏开始.AtGSave`. The harness loaded
  it once from the main menu and then reloaded the same save five times through
  the in-game pause menu without restarting the process. No crash or new
  `Crash.AtGLog` entry appeared. Evidence:
  `.tmp\runs\20260714-load-reload-memory-lifecycle-v4\run-summary.json` and
  `in-game-reload-memory-regression-20260712-main_loop_after_reload_1.png`.
  Private bytes rose from about 1.308 GiB to the first-reload peak of about
  1.412 GiB, then stabilized around 1.39 GiB; handles returned to 703.

### Religion Screen

- Load the scenario-specific save from the main-menu load screen, then click
  the top-right Religion icon in the main loop. Do not start a new game and do
  not use the in-game pause/load menu for this scenario.
- Verify the title and all three choices: `宗教`, `尼西亚基督教`, `阿里乌派基督教`,
  and `异教`. No original English labels, `RELIGION_*` IDs, raw `TEXT.*` keys,
  unresolved tags, or mojibake may appear.
- Close the panel and confirm the game process remains alive. The current
  scenario is `religion-screen-20260718`; its fixed save is
  `v1.4.1   World [OAA-JUH]   游戏开始.AtGSave`.
- Completed on `2026-07-18` after the refreshed build was installed. The main
  menu load path reached the main loop, the Religion panel was opened and
  visually checked, and no new crash log entry appeared. Evidence:
  `.tmp\runs\20260718-religion-screen-manual\religion-screen.png`.

## Completed / Deferred UI Tests By Interface

These scenarios are not permanent required tests. Run them when the touched code
or data affects the relevant UI, tooltip path, source file, DLL patch, font, or
layout behavior. If one fails, promote it to `Active Focus Tests` and follow the
automatic failure loop in `docs/agent/workflows/test-and-loop.md`.
Do not repeat a passed interface scenario unless the touched source, font,
config, DLL patch, save/load flow, or UI behavior can affect that interface.

### Cross-Interface Font Calibration

- Completed on `2026-07-16` for the default `DynamicCjk` renderer. Chinese
  glyphs use a 1.15 raster scale plus per-size vertical baseline offsets; Latin
  characters, numbers, hotkey glyphs, and private-use icons remain on the
  original SpriteFont path.
- Original/localized visual comparisons covered the main menu, load screen,
  main-loop HUD, knowledge screen, and clan list. The localized help screen was
  also checked for clipping and alignment; its direct original help capture was
  unavailable, so its mapped font families were cross-checked through the
  other original interfaces rather than claimed as a one-to-one help pair.
- Evidence is under `.tmp\font-compare`, including
  `original-clean-main.png`, `original-clean-load.png`,
  `original-fixed-save-main-loop.png`, `original-knowledge-screen.png`,
  `original-clan-list.png`, `localized-main-baseline.png`,
  `localized-load-baseline.png`, `localized-fixed-save-baseline.png`, and the
  `localized-baseline-run` / `localized-clan-list-corrected` scenario folders.
- Result: the checked Chinese text is no longer generally smaller or visibly
  lower than the original UI text, and no checked button, row, title, tooltip,
  or HUD label clipped after calibration.

### In-Game Reload Memory Regression

- Load the fixed save from the main menu, then open the pause menu with
  `Escape`, choose `读取存档`, and load the promoted first row again.
- Repeat the pause-menu reload five times in the same game process. A fresh
  process per repetition is not equivalent and must not be used for this test.
- After every reload, wait for a `World Screen - Children Initialized` marker
  written after that reload began, then verify the process remains alive.
- Record private bytes, working set, virtual bytes, and handle count before and
  after each repetition. The test fails on a crash, OOM, new crash log, or
  sustained monotonic growth across later repetitions.
- Completed on `2026-07-14` with the `BVT-LCL` fixed save and five successful
  reloads. This scenario now belongs to `FullRegression` and is skipped by
  default. Rerun it only when load lifecycle, runtime renderer resources,
  Game/ElfTools rewrites, font strategy, or save-loading behavior changes.

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
- Detail panels for learned or unavailable professions must verify status lines
  as well as hover text. The Hunter panel must not show mixed lines such as
  `Cannot 研究.` or `Already 已学会.`; these lines are assembled from Game EXE
  static-check prefixes plus localized `[Study|STUDY]` / `[Learned|LEARN]`
  concept tags.
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
- Latest random-trait hover evidence: `2026-07-16`, `DynamicCjk` installed
  build, fixed save `v1.4.1   World [BVT-LCL]   游戏开始.AtGSave`, opened from
  the top-left clan button. The six trait hovers for Landbert, Adelhard, and
  Aland were captured from `.tmp\runs\20260716-clan-traits-fixed-save`.
  The harness timed out on the first hover stabilization, but the captured
  tooltip was visually checked and localized. The remaining five points passed
  the automated hover capture. Previously exposed composed fragments including
  `engage in`, `Brawls`, `commit Theft`, `Max`, `forced into a`, and
  `outside of` were fixed through runtime rich-text plain-node fragments.

- Latest random-new-start trait sweep: `2026-07-17`, `DynamicCjk` installed
  build, scenario `clan-screen-new-game-traits`, three consecutive new-game
  starts. Each run opened the clan screen from the top-left clan button and
  hovered the two visible trait icons on each of the three generated clan
  cards. All 18 hover points passed the automated expected-text check; contact
  sheets were visually reviewed and did not show raw `TEXT.*`, plural suffix
  keys, or safely patchable English trait prose. Evidence folders:
  `.tmp\runs\20260717-171115-clan-traits-newgame-1`,
  `.tmp\runs\20260717-171115-clan-traits-newgame-2`, and
  `.tmp\runs\20260717-171115-clan-traits-newgame-3`. The right-side
  `Clan <Name>` join-notification prefix remains an accepted generated-name
  residual and is outside this trait-hover scenario.

### Clan List

- Open the clan list from the top-right clan-list button.
- At 2560x1440 the verified clan-list button center is approximately
  `1985,25`. The earlier `2020,25` setup coordinate opens diplomacy and must not
  be reused for this scenario.
- Test the first row of header hovers only unless a task explicitly asks for
  deeper nested hovers.
- Current tracked header points are the user-scoped 7 icon columns and 3 word
  columns: clan name, profession, level, families, supply, damage, upgrades,
  mood, command, and distance.
- For nested tooltips, only the `Level` secondary tooltip is currently tracked.
  Do not recursively inspect every nested concept in this scenario by default.
- The first-level header tooltips must not expose `[Clan|CLAN]`,
  `[Discipline|DISCIPLINE]`, `[Level|LEVEL]`, `[Upgrades|UPGRADES]`, or other
  safely patchable English concept display text.
- 2026-07-10 static fix: header labels and first-level header tooltips were
  patched through
  `AtTheGatesUI.ns_InGame.ns_Popups.ClanListEntry.BuildPanel_TitleRowContents`.
  The `Level` secondary tooltip was patched through
  `AtTheGatesCommon.ns_UI.Concepts`.
- 2026-07-10 focused fixed-save regression passed from the main-menu load
  path: the `Upgrades` primary tooltip renders `[升级|UPGRADE]` as highlighted
  Chinese without exposing markup, and hovering `等级` in the `Level` primary
  tooltip opens a Chinese secondary tooltip without an `invalid CONCEPT` error.
  Evidence: `.tmp/runs/richtext-clan-list-upgrades-primary.png` and
  `.tmp/runs/richtext-clan-list-level-nested.png`.

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
- Latest targeted evidence: `2026-07-02`, main-menu loaded
  `Quicksave.AtGSave`, scenario
  `load-save-main-loop-tile-tooltip-20260702`, contact sheet
  `.tmp\runs\20260702-221952-load-save-main-loop-tile-tooltip-20260702\contact.png`.
  Strategic view, note mode, religion, victory progress, and nested hotkey
  tooltip hovers displayed Chinese. The nested `[HOTKEY:F11]` tooltip is
  supplied by `ElfTools.Inputs.Hotkey.BuildTooltip` and patched through
  `translations\hardcoded-elftools-il-rewrite.json`.
- Deferred within this interface: selected unit command buttons were not
  visible in the current `Quicksave.AtGSave` state after selecting the nearby
  map object. Do not mark unit commands completed until a fixed save exposes
  buttons such as pack up, fortify, move, skip, leave, or profession/clan
  actions and those hover tooltips are visually checked.
- 2026-07-09 targeted static regression: selected settlement/unit command
  sources for Pack Up, movement points, Skip, terrain aliases, and Food
  consumer plural suffix were patched and covered by
  `Test-HoverLocalizationRegressions.ps1`,
  `Test-GeneratedTextAliases.ps1`, and install smoke. This does not replace a
  visual fixed-save selected-command hover sweep.
- 2026-07-10 targeted static fix: the selected settlement information panel
  uses `STRUCTURE_SETTLEMENT` from `Content\Config\OnMap\Structures.xml`, now
  patched through `translations\config-node-onmap-strings.json`. Reopen the
  selected settlement panel and Pack Up hover on the latest installed build
  before marking this completed.

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
- Latest targeted evidence: `2026-07-02`, fixed-save tile
  `stream/hill/grassland` click in scenario
  `load-save-main-loop-tile-tooltip-20260702`; lower-right crop showed Chinese
  terrain/resource text and no visible `TEXT.*`, `next`, or safely
  replaceable English fragments.
- 2026-07-10 static fix: terrain description aliases in
  `patch\Content\Text\English.xml` now use localized `全部` for the previously
  visible lower-right tooltip `all` fragment. The user planned to test this
  visually, so do not mark it completed from static evidence alone.

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
