# XML, Managed Patching, and Rich Text

Use exact source evidence for XML, UI/Common/Game/ElfTools assemblies, and
runtime display maps.

## XML and Config

- Preserve stable IDs and XPath/node identity.
- Keep raw runtime tokens intact; do not turn `[FARMER:S]` or `[TIMBER]` into a
  concept link unless the source already models it as one.
- Only change the display portion of `[display|CONCEPT-KEY]` links. Preserve
  the key, color, hotkey, placeholder, and recursion structure.

## Managed Assemblies

- Prefer `MethodToken + ILOffset + Original` UI IL rewrites.
- A fallback byte or offset patch needs an exact original-byte check and a
  targeted regression. Never use a broad text search as an offset proof.
- `#US` heap patches cannot expand an entry. They must fail instead of padding
  or overwriting adjacent metadata.
- Common/Game/ElfTools edits are display-only and narrow by default. Read
  `../crash-risks.md` before changing lifecycle, settings, concepts, dates, or
  behavior-adjacent text.

## Composition

For a dynamic phrase, query `translations/composite-text-rules.json`. Generate
the temporary `Composite` CSV only when filtering or sorting its entry-point
columns helps. Reuse an existing Rule ID when it covers the same final display
boundary.
Do not reintroduce word-level `and/from/or/a` patches where a complete template
or final-display rule is available.
