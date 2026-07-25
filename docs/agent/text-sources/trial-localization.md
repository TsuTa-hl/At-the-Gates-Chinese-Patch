# Fast-Fail Trial Localization

Use only when the user explicitly requests trial localization beyond the
safety-first path. Read `../trial-localization-state.json` before selecting a
batch.

- UI exact-catalog display candidates: start at 48, cap at 64.
- Common/Game/ElfTools display candidates: start at 8, cap at 16.
- Logic-sensitive or historically risky candidates: 1-4 only.
- Use exact catalog operands and real Chinese translations. Never create a
  trial original from review-table-normalized whitespace.
- Keep technical paths, IDs, enum keys, parser glue, faction names, dates,
  generated names, and diagnostics out of a batch.
- The trial runner may bisect a failing batch. Only recorded accepted entries
  become normal patch bindings; rejected entries remain in machine state.
- A smoke pass proves build/install/startup safety only. It does not prove
  wording, layout, hover coverage, fixed-save loading, or rich-text behavior.
