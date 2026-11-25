# roves-action

A single composite GitHub Action (`action.yml`) that packages a game's already-built web
content as a native [Roves](https://github.com/DRincs-Productions/roves) app for any
third-party game's own CI: the prebuilt CEF player on Windows/macOS/Linux (downloaded from an
engine release, nothing compiled), and the engine's native WebView tooling for Android/iOS.
See `README.md` for what it does today and what it doesn't.

It is a separate git repo, checked out next to the engine (`../roves`) or as a submodule of
it on this machine.

## Standing authorization: autonomous CI/push, and GitHub PAT usage

The user has given standing permission to push and run/watch CI
autonomously across this whole ecosystem (this repo, `../roves`, `../roves-packmaster`/Packmaster,
and the rest) without stopping to ask first — see `../roves/AGENTS.md`'s "Standing
authorization: autonomous CI/push/release loop" section for the full detail (report honestly
if asked directly whether something's done; don't claim it prematurely, and this doesn't
cover genuinely destructive actions outside the normal build/test/release loop).

When the user shares a GitHub PAT for reading Actions logs/annotations: it's **read-only** —
a write call like re-running failed jobs will 403 by design, use a real `git push` (or an
empty commit, `git commit --allow-empty`, when retrying after a transient flake with no real
code change) instead. Never persist it to a file or commit; re-export it fresh in every
command that needs it (env vars don't survive across separate tool calls here); if it starts
401ing, say so and ask for a fresh one. Full detail in `../roves/AGENTS.md`.

## CRITICAL: keep the two pinned engine tags in `action.yml` current

There is no `roves-repo`/`roves-ref` input: the action always targets
`DRincs-Productions/roves` at fixed tags, hardcoded as literals (`grep -n 'v0\.' action.yml`
finds them; the header comment of `action.yml` names both):

- **DESKTOP PLAYER PIN** (`v0.9.0`): the release URL in the "Download the CEF player
  (desktop)" step. Every desktop consumer gets exactly those `roves_shell_<platform>[_steam|_mcp].zip`
  assets. Bump it on every engine release that changes the desktop player, together with the
  README ("Pin status", the asset table and the intro). Until the pinned release exists, the
  desktop path (and this repo's desktop CI legs) fails at the download with a clear error.
- **MOBILE ENGINE PIN** (`v0.7.15`): the `ref:` of "Checkout Roves engine source (mobile)".
  It must point at an engine tag that still has `mach bundle --android`/`--ios` and
  `support/ios/bundle.py`; the CEF-era engine has no mach desktop packaging, so do not move
  this pin to a newer tag without checking that tooling still exists there.

This is the other side of the engine's release obligation ("sync the shell version in
`roves-action` and `roves-packmaster`"): a new engine tag is invisible here until a real
commit bumps the matching pin. If you notice drift, fix it.

## Desktop: design notes

- **One flow for all desktop platforms**: validate -> resolve paths -> download the pinned
  asset -> resolve the project icon -> assemble -> zip. Nothing is compiled and there are no
  build-configuration inputs: each platform has one prebuilt configuration, selected only by
  `steam` and (Windows) `enable-mcp`. Invalid combinations (`enable-mcp` with `steam` or off
  Windows, desktop inputs with `android`/`ios`) are hard errors in "Validate inputs", never
  silently ignored.
- **`cef/assemble.ps1`** (Windows) verifies the asset against its own `SHA256SUMS.txt`, checks
  MCP completeness, copies the package without the sample game, its provenance, its
  `icon.png` and (unless `enable-mcp`) `mcp\`, patches `play.exe`'s icon with rcedit, and
  rewrites `PROVENANCE.txt`/`SHA256SUMS.txt`. Kept in step with Roves Packmaster's
  `src-tauri/src/cef_player.rs`.
- **`cef/assemble.sh`** (macOS/Linux) checks the documented files (no checksum list is
  published for those assets), the Steam redistributable exactly when `steam`, copies the
  player with `ditto`/`cp -a` (symlinks and modes kept), replaces `game/` and applies the
  window icon (and on macOS the `.icns` named by `CFBundleIconFile`). It must stay bash
  3.2-compatible (macOS system bash): no `mapfile`, no empty arrays under `set -u`.
- **Identical copies of engine scripts**: `cef/project_icon.py` =
  `support/cef-netrender-probe/packaging/project_icon.py`, `cef/icns.sh` =
  `support/cef-macos-gate/packaging/icns.sh`. Do not edit them here; change the engine's copy
  and copy it back (the engine's `test_project_icon.py` runs against this copy unchanged).
  Pillow 11.3.0 and electron/rcedit v2.0.0 (SHA-256) are pinned as in the engine workflow.
- **Icon precedence** is the engine's and Packmaster's: game icon first (explicit input, then
  `icon.png`/`icon.ico`/`favicon.ico` in `content-dir`), Roves icon as the fallback
  (`roves.ico` in the Windows package; the base `.icns` on macOS; the embedded logo for the
  window icon when the package has no `icon.png`).
- **Zipping** keeps what each platform needs: `Compress-Archive` on Windows, `ditto -c -k
  --keepParent` on macOS (framework symlinks), `zip -qry` on Linux (symlinks; Info-ZIP stores
  the modes). The root-owned setuid bit of `chrome-sandbox` cannot survive a zip; the README
  tells users how to restore it.
- **Paths**: "Resolve paths" emits native absolute paths (`pwd -W` gives `D:/a/...` in Git
  Bash on Windows) so bash, pwsh, python and mach can all consume them. Input values reach
  scripts through `env:`, never interpolated into `run:` text.
- **History**: the desktop path used to download the Servo shell (`roves_shell_*.zip` of
  v0.7.15) and run `mach bundle --bin`, with an opt-in `advanced-mode` compiling the engine
  from source; both and all their `[servo]`/desktop `mach bundle` inputs were removed when the
  engine replaced the Servo desktop shell with the CEF player (README, "Migrating to the CEF
  player"). The experimental `cef-windows/` sub-action (packaging from a
  `cef-netrender-probe.yml` workflow artifact) was folded into the root action at the same
  time: it was never on `main`, and the release asset makes the artifact/token/run-id path
  unnecessary.

## Android/iOS: design notes

**Android** (`android: 'true'`): checkout at the mobile pin, JDK + Android SDK (mirrors the
engine's `android.yml` at that tag), optional `mach bootstrap`, then `mach bundle --android`.
Nothing is cross-compiled. `android-release` decodes the keystore secret to a temp file and
exports the four `APK_SIGNING_*` variables the Gradle project reads.

**iOS** (`ios: 'true'`, macOS runners only) has two modes: `ios-release: 'false'` runs the
engine's `support/ios/bundle.py` + XcodeGen and builds an unsigned Simulator `.app` into a
scratch `derivedDataPath` (only the `.app` is copied next to the raw `.xcodeproj`); a real
device always needs a signing identity. `ios-release: 'true'` goes through `mach bundle
--ios --ios-release` and returns a signed `.ipa`. `icon-png`/`icon-ico` are rejected with
`ios` (no icon override there yet).

**Android and iOS signing are NOT symmetric**, despite looking alike: an Android keystore is
self-signed by design, so `android-keystore-base64` can be a complete self-generated identity
(this repo's CI generates one per run). An Apple Distribution certificate must be
countersigned by Apple through a real Apple Developer Program account; neither this action
nor CI can manufacture one. Keep that in mind before "simplifying" the two to look alike.
