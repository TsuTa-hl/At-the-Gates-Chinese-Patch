# Runtime and Resource Diagnostics

Read this file only for performance, memory, network, window-capture, or
runtime-renderer investigations.

- Use `tools\Measure-AtGResourceUsage.ps1` for process memory, handle, and
  network-adjacent telemetry. Keep a compact JSON/text summary, not raw traces.
- Treat the 32-bit game, the desktop client, and build tools as separate
  processes. Do not attribute desktop-app memory use to the game without a
  measured process identity.
- DynamicCjk has an 8-page 1024x1024 RGBA atlas limit (32 MiB). Missing glyphs
  must create a RuntimeText diagnostic rather than a SpriteFont crash.
- Browser or network capture is opt-in. Avoid repeated downloads, restore, or
  large screenshot uploads when a local structured result is sufficient.
