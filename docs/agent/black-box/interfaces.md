# Interface Test Coverage

Use the scenario registry for coordinates, setup state, and machine IDs. This
file defines what to inspect and when a surface may be considered covered.

## Main Menu, Load, and Reload

- Main-menu smoke verifies a complete window and no new crash/log event.
- Fixed-save scenarios load from the main-menu load panel, not from the pause
  menu, unless the in-game reload path is the case under test.
- The load panel must localize its buttons/tooltips and may retain World IDs,
  versions, and generated save labels.
- The in-game reload lifecycle case reloads the same fixed save repeatedly in
  one process. It is FullRegression only when renderer, load lifecycle,
  Game/ElfTools rewrite, or save behavior changes.

## Knowledge Screen

- Open the knowledge screen and test visible nodes, status lines, upgrade
  icons, footer, show-all, and close controls selected by the scenario.
- Verify raw profession/discipline keys, `Cannot`/`Already` fragment mixing,
  unlocalized requirements, and broken rich-text links are absent.
- Nested concept hovers must retain a highlighted display term and a valid
  second-level tooltip when one exists.

## Clan Screen and Traits

- Open the clan screen from the main loop and test action buttons, card details,
  and all visible trait icons.
- Scope includes 92 personality and 14 non-personality traits. A trait is
  passed only when its own name and effect/description are visibly confirmed.
- Do not count a portrait, card body, notification, or clan detail card as a
  trait result. Record the actual trait ID and save before repair when random
  discovery exposes a defect.

## Clan List

- Test the first-row header hovers for the scoped text and icon columns.
- Test only the Level secondary tooltip by default; deeper nested paths require
  an explicit request.
- Concept links such as Clan, Discipline, Level, and Upgrades must show
  localized display text while retaining their valid concept keys.

## Main Loop and Terrain

- Test affected HUD, system, action, resource, notification, and selected-unit
  controls. Do not sweep unrelated passed controls by default.
- For a selected settlement/unit, inspect Pack Up, movement, skip, and any
  currently visible action that the change can affect.
- Terrain tests click/hover each distinct visible object needed by the active
  scenario and inspect the lower-right description and left-side detail panel.
- Random terrain, clans, notifications, and commands must use a saved state for
  repair/retest; never reroll while chasing one defect.

## Help and Religion

- Help tests cover only the requested article/page sequence; `Escape` can
  close an article, then the help panel, then open a pause menu if overused.
- Religion tests use the designated fixed save and inspect the title and each
  listed option. Preserve logic IDs while localizing stable display names.

## Completion Evidence

Record scenario ID, setup/save, target points, visible result, crash-log state,
timing, and any limitation. Keep screenshots only until this text record is in
the cleanup handoff.
