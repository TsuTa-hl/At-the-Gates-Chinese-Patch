# Localization Safety Registry

`translations/localization-safety-registry.json` is the compact record of
historical localization safety decisions. It is not a patch source.

- Active translation maps and exact SQLite occurrence records remain the only
  patch operands.
- The registry retains accepted-coverage totals, rejected exact operands,
  stable locator forms, and reusable risk reasons.
- Exploratory batch localization is retired. New work follows the safety-first
  source priority and must have a display-specific regression before mapping.
- Never reconstruct a retired batch from user review output or add a broad
  replacement just to match the historical count.
