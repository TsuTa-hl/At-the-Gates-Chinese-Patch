# Managed Rewrite and Logic Risks

Read when changing any managed DLL/EXE rewrite, rich-text concept behavior, or
logic-sensitive display term.

## Common and Concept Terms

- Leave `translations\\hardcoded-common-offsets.json` and
  `Build-Patch.ps1 -PatchCommonConceptTerms` disabled by default.
- Broad Common concept replacements, including a direct `Turn` replacement,
  have caused startup failures even when their byte match was exact.
- For phrases such as `Cannot Learn Right Now`, keep the concept identifier
  unchanged and use a scoped dnlib display rewrite in
  `hardcoded-common-il-rewrite.json`; do not rewrite raw concept IDs or broad
  metadata offsets.

## UI DLL

- `Build-IlRewritePatch.ps1` is the preferred UI path: dnlib rewrites `ldstr`
  by `MethodToken + ILOffset + Original`, avoiding padding.
- Run the rewriter as `AtG.IlRewrite.dll` through `.tools\\dotnet\\dotnet.exe`.
  Do not invoke `AtG.IlRewrite.exe`; systems without a global .NET runtime can
  show an application-error dialog. `UseAppHost` stays false.
- The old `Build-IlStringPatch.ps1` `#US` fallback may only write a translation
  that fits the original heap entry.
- Keep byte/offset fallbacks until each migrated string has build, install,
  smoke, and target-UI coverage. Do not rewrite `ClanCard.AddActionButton`
  `Leave ` while its verified offset fallback still expects that original text.

## Game and ElfTools

- Game EXE rewrites are restricted to display-only `ldstr` fragments, currently
  static resource-requirement text in action-button tooltips. Every new entry
  needs fixed-save load and target UI coverage as well as smoke.
- ElfTools rewrites are restricted to display helpers such as hotkey tooltips,
  collapsible containers, dropdowns, and two-button dialogs. Do not broadly
  rewrite input handling, parser glue, diagnostics, resource IDs, or engine
  helpers.

## Logic-Sensitive Text

Treat faction names, date-banner terms, `Clan <Name>` notification prefixes,
and Common concept terms as unsafe for bulk replacement. Patch only in small
isolated changes with build, install, startup, and target-UI regression; roll
back immediately if navigation or startup fails.
