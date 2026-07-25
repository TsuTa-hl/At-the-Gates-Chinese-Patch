# Startup and Content Risks

Read when changing XML output, launch behavior, settings descriptions,
religion configuration, or ClanCard assets.

## XML and Startup

- `English.xml` must not have an XML declaration. `Build-ChineseXml.ps1` keeps
  `OmitXmlDeclaration = true`; the generated file must begin with `<english>`.
- A silent exit can bypass the crash dialog and leave `Crash.AtGLog` unchanged.
  When that happens, treat Windows Application/.NET Runtime events for `At The
  Gates.exe` as the authoritative evidence. An isolated `c00000fd` WER during
  randomized new-game generation is retryable only when the same patched build
  then passes repeat smoke runs.
- Do not translate `UserSetting_*` descriptions or warning strings through a
  path that writes them as comments to `Settings\\Settings.xml`. Non-ASCII
  comment content has made that file invalid. `SettingsErrorSeen=True` from
  `Test-GameLaunch.ps1` is a smoke failure.

## Launch Environment

Starting `At The Gates.exe` without its game directory as the working directory
can fail in `AtTheGatesCommon.ns_GlobalSystems.Log`. Use the launch procedure
in [../operations/game-automation.md](../operations/game-automation.md).

## ClanCard Asset Aliases

Translated discipline names may become ClanCard asset-path components, for
example `Images\\Interface\\ScreenSpecific\\ClanCard\\冶金\\PortraitBackground_2`.

- Keep the Chinese alias-copy logic in `tools\\Build-Patch.ps1`.
- Keep generated aliases for `农耕`, `冶金`, `工艺`, `探索`, `畜牧`, and `荣誉`.
- Removing an alias can crash the clan screen with a missing
  `PortraitBackground_*.xnb` error.
- In PowerShell 5.1, do not rely on raw Chinese path literals under an ANSI
  fallback. Derive the component from Unicode code points or from the generated
  alias list and verify the final `Test-Path` result.

## Religion Configuration

- Religion `name` and `adjective` are display-safe only when patched through a
  stable religion ID. Leave `RELIGION_*` IDs and description placeholders
  unchanged unless a dedicated source/UI regression proves them safe.
- The fixed-save Religion screen has already opened with Chinese religion names
  under `DynamicCjk`; do not reintroduce a merged-font dependency for it.
