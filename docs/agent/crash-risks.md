# Crash Risks and Rollback Index

Read this index only to classify a crash or risky edit. Read one linked topic
before changing the affected subsystem; do not load all three by default.

| Symptom or change | Read next |
| --- | --- |
| Startup failure, XML, working directory, settings, religion, ClanCard alias | [startup-and-content.md](crash-risks/startup-and-content.md) |
| Missing CJK glyph, icon corruption, font memory, device reset, in-game reload/OOM | [runtime-and-assets.md](crash-risks/runtime-and-assets.md) |
| Common/UI/Game/ElfTools rewrite, concept link, faction/date/notification term | [managed-rewrites.md](crash-risks/managed-rewrites.md) |

## Always Unsafe Until Isolated

- Do not broadly replace Common concept identifiers, faction names, date terms,
  or `Clan <Name>` notification prefixes.
- Keep the patch on a small reversible change. A new risky change requires
  build, install, smoke, and the target UI regression before it is retained.
- If the game crashes, preserve the textual crash summary first, then restore
  the last known-good artifact rather than stacking more speculative edits.

## Required Rollback Facts

- `DynamicCjk` is the default renderer. `MergedFonts` is rollback-only and
  must never replace original icon glyphs.
- ClanCard Chinese alias assets are generated build outputs and must remain
  available whenever translated discipline labels are installed.
- Patch outputs can remain memory-mapped briefly. Use the bounded copy helper,
  not a raw replacement copy.
