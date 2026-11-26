# roves-action

A single composite GitHub Action (`action.yml`) that packages a game's already-built web
content as a native [Roves](https://github.com/DRincs-Productions/roves) app for any
third-party game's own CI, by running the pinned `@drincs/roves-cli`
(`../roves-cli`, DRincs-Productions/roves-cli): the prebuilt CEF player on Windows/macOS/Linux (downloaded from an
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

## CRITICAL: keep the three pins in `action.yml` current

There is no `roves-repo`/`roves-ref` input: the action always uses fixed versions, hardcoded as
literals (`grep -n "v0\.\|ROVES_CLI_VERSION" action.yml` finds them; the header comment of
`action.yml` names all three):

- **ROVES CLI PIN** (`0.3.0`): `ROVES_CLI_VERSION` in the "Install roves-cli" step, the exact
  `@drincs/roves-cli` version that does all the packaging. Bump it (with the README intro and
  "Pin status") when a CLI release changes packaging behaviour this action should ship; the
  version must already be published on npm.
- **DESKTOP PLAYER PIN** (`v0.9.0`): the `--shell-version` argument of `roves bundle` in the
  "Package with roves-cli" step. Every desktop consumer gets exactly those
  `roves_shell_<platform>[_steam|_mcp].zip` assets. Bump it on every engine release that
  changes the desktop player, together with the README ("Pin status", the asset table and the
  intro). Until the pinned release exists, the desktop path (and this repo's desktop CI legs)
  fails at the download with a clear error.
- **MOBILE ENGINE PIN** (`v0.7.15`): the `ref:` of "Checkout Roves engine source (mobile)",
  passed to the CLI as `--engine-dir`. It must point at an engine tag that still has `mach
  bundle --android`/`--ios` and `support/ios/bundle.py`; do not move it without checking.

This is the other side of the engine's release obligation ("sync the shell version in
`roves-action` and `roves-packmaster`"): a new engine tag is invisible here until a real
commit bumps the matching pin. If you notice drift, fix it.

## Design notes

- **roves-cli does the packaging; this action prepares and maps.** Flow: validate inputs (the
  action's own error messages, kept for compatibility) -> resolve paths -> make sure Node.js
  >= 20.19 exists (the runner's, else setup-node 22) -> install the pinned CLI into
  `$RUNNER_TEMP/roves-cli` (never global) -> mobile only: install the toolchains -> run
  `roves bundle|android|ios --json` -> map the JSON to the outputs (`bundleDir`, `archivePath`,
  `mcpEnabled`, `iconSource`). No packaging logic lives here any more: verification, icons,
  Steam/MCP rules, zipping and the mach invocations are the CLI's (keep its README/skill as the
  reference). When the CLI gains or changes an option this action exposes, update the mapping
  in "Package with roves-cli".
- **Toolchains are this action's job**, the CLI only detects them: setup-java (Temurin 17), the
  Android SDK cmdline-tools revision 15859902 plus `platform-tools`, the newest
  `platforms;android-37*` and `build-tools;36.0.0` (mirrors the engine's `android.yml` at the
  mobile pin), setup-python, setup-uv, `brew install xcodegen`. `mach bootstrap` (unless
  `bootstrap: 'false'`, then `--no-bootstrap`) and the `rustup show` prefetch run inside
  `roves android`.
- **Secrets** reach the CLI only through its `ROVES_ANDROID_*` / `ROVES_IOS_*` environment
  variables, never on the command line; input values reach scripts through `env:`, never
  interpolated into `run:` text.
- **Paths**: "Resolve paths" emits native absolute paths (`pwd -W` gives `D:/a/...` in Git
  Bash on Windows). `output` only selects the parent folder where the CLI writes
  `<artifact-name>` and `<artifact-name>.zip`.
- **macOS layout** follows the CLI: `<artifact-name>.app` at the zip root (README "Migrating to
  roves-cli").
- **History**: the desktop path used to download the Servo shell (`roves_shell_*.zip` of
  v0.7.15) and run `mach bundle --bin`, with an opt-in `advanced-mode` compiling the engine
  from source; both were removed when the engine replaced the Servo desktop shell with the CEF
  player (README, "Migrating to the CEF player"). The CEF packaging then lived here as
  `cef/assemble.ps1`, `cef/assemble.sh`, `cef/project_icon.py` and `cef/icns.sh` until it moved
  to roves-cli (README, "Migrating to roves-cli").

## Android/iOS: design notes

**Android** (`android: 'true'`): checkout at the mobile pin, JDK + Android SDK (mirrors the
engine's `android.yml` at that tag), then `roves android --engine-dir roves-src`, which runs the
optional `mach bootstrap` and `mach bundle --android`. Nothing is cross-compiled. With
`android-release` the CLI decodes the keystore secret to a temp file and exports the four
`APK_SIGNING_*` variables the Gradle project reads.

**iOS** (`ios: 'true'`, macOS runners only, `roves ios`) has two modes: `ios-release: 'false'` runs the
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
