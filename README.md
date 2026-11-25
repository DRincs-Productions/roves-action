# Roves GitHub Action

Packages your already-built web game as a native app with
[Roves](https://github.com/DRincs-Productions/roves), for any game's own CI:

- **Desktop (Windows, macOS, Linux): the Roves CEF player, release v0.9.0.** The action
  downloads the prebuilt player for the runner's platform, verifies it, puts your game in its
  `game/` folder, applies your game's icon and zips the result. Nothing is compiled. The
  standard and Steam variants exist for every platform; Windows also has an opt-in
  MCP-enabled development package.
- **Android and iOS (experimental): the native WebView path** of the Roves engine at
  v0.7.15 (`mach bundle --android`, `support/ios/bundle.py`/`mach bundle --ios`), unchanged.

Upgrading from the Servo desktop shell (`advanced-mode`, `features`, `deb`/`msi`/`dmg`,
content packing, ...)? See [Migrating to the CEF player](#migrating-to-the-cef-player).

> **Pin status:** the desktop path downloads assets of the Roves **v0.9.0** release. Until
> that release is published, the desktop download fails with a clear error.

## What this action does *not* do

- **Build your game's web content.** That's your bundler's job (Vite, webpack, ...): run it
  in a step before this action, then point `content-dir` at the result (`index.html` at its
  root).
- **Upload anything.** It produces a zip on disk and exposes its path as `archive-path`;
  attaching it to a release, an artifact or a store upload is your workflow's job.
- **Sign or notarize.** The macOS `.app` is unsigned apart from the linker's ad-hoc
  signature and not notarized; the Windows `play.exe` is not code-signed.
- **Cross-build.** Each desktop platform is packaged on its own runner (`windows-latest`,
  `macos-latest`, `ubuntu-latest`), one job per platform.

## Example

Package all three desktop platforms and upload each as a workflow artifact:

```yml
name: bundle

on:
  push:
    branches: [main]

jobs:
  bundle:
    strategy:
      fail-fast: false
      matrix:
        include:
          - os: windows-latest
            name: my-game_windows
          - os: macos-latest
            name: my-game_macos
          - os: ubuntu-latest
            name: my-game_linux
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: '22'
      - run: npm ci && npm run build

      - name: package with Roves
        id: roves
        uses: DRincs-Productions/roves-action@v1
        with:
          content-dir: dist
          artifact-name: ${{ matrix.name }}

      - uses: actions/upload-artifact@v4
        with:
          name: ${{ matrix.name }}
          path: ${{ steps.roves.outputs.archive-path }}
```

## More examples

**Publish to a GitHub Release, with Steam builds too** — triggers on a version tag and
attaches a standard and a Steam zip per platform:

```yml
name: release

on:
  push:
    tags: ['v*']

permissions:
  contents: write

jobs:
  release:
    strategy:
      fail-fast: false
      matrix:
        os: [windows-latest, macos-latest, ubuntu-latest]
        steam: ['false', 'true']
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '22'
      - run: npm ci && npm run build

      - id: roves
        uses: DRincs-Productions/roves-action@v1
        with:
          content-dir: dist
          steam: ${{ matrix.steam }}
          artifact-name: my-game_${{ runner.os }}${{ matrix.steam == 'true' && '_steam' || '' }}

      - env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: gh release upload "${{ github.ref_name }}" "${{ steps.roves.outputs.archive-path }}"
```

**A custom game icon** — optional: an `icon.png` (or `icon.ico`/`favicon.ico`) at the root of
`content-dir` is picked up automatically, see [Project icon](#project-icon):

```yml
- uses: DRincs-Productions/roves-action@v1
  with:
    content-dir: dist
    icon-png: assets/icon.png
    icon-ico: assets/icon.ico # Windows play.exe; generated from icon-png when omitted
```

**A Windows playtest build an AI agent can drive** (never ship it to players, see
[Local MCP bridge](#local-mcp-bridge-enable-mcp)):

```yml
- uses: DRincs-Productions/roves-action@v1
  with:
    content-dir: dist
    enable-mcp: 'true'
    artifact-name: my-game_windows_mcp
```

**An Android APK** (any Linux runner, nothing compiled):

```yml
- uses: DRincs-Productions/roves-action@v1
  with:
    content-dir: dist
    android: 'true'
    artifact-name: my-game_android
```

## Usage

```yml
- uses: DRincs-Productions/roves-action@v1
  with:
    # ── Your game ────────────────────────────────────────────────────────────────
    # Path (relative to your repo root) to your already-built web content, index.html at
    # its root. On desktop it replaces the player's game/ folder.
    #
    # required
    content-dir: ''

    # Square PNG project icon (16-2048 px, at most 8 MiB). Desktop: window icon, macOS app
    # icon, and the source of play.exe's icon when icon-ico is unset. Android: launcher
    # icon. Not supported with ios.
    #
    # default: content-dir/icon.png, else the largest frame of the project ICO, else the
    # Roves icon -- see "Project icon"
    icon-png: ''

    # Project .ico. Windows: play.exe's icon. macOS/Linux: window icon source when there is
    # no PNG. Not supported with android or ios.
    #
    # default: an ICO generated from the resolved PNG, else content-dir/icon.ico or
    # favicon.ico, else the Roves icon
    icon-ico: ''

    # ── Desktop: the CEF player ──────────────────────────────────────────────────
    # Package the Steam variant (Steam redistributable next to the executable).
    #
    # default: false
    steam: false

    # Windows only: package the MCP-enabled development player. Never ship it to players.
    # Cannot be combined with steam.
    #
    # default: false
    enable-mcp: false

    # ── Android (engine v0.7.15) ─────────────────────────────────────────────────
    # Package a native Android WebView APK instead of a desktop package.
    #
    # default: false
    android: false

    # Run `mach bootstrap` first (Android only). 'false' if you provisioned it yourself.
    #
    # default: true
    bootstrap: true

    # Launcher label. Requires android.
    #
    # default: content-dir's manifest.webmanifest/manifest.json/site.webmanifest
    # `short_name` (falling back to `name`), or Roves' own default label
    android-app-name: ''

    # Locked screen orientation (web app manifest vocabulary: any, natural, landscape,
    # landscape-primary, landscape-secondary, portrait, portrait-primary,
    # portrait-secondary). Requires android.
    #
    # default: the manifest's `orientation`, or unlocked
    android-orientation: ''

    # Status bar color (e.g. "#ffffff"). Requires android.
    #
    # default: the manifest's `theme_color`, or the normal theme color
    android-theme-color: ''

    # A real, signed release .apk instead of the debug one. Requires android plus the four
    # inputs below; fails rather than falling back to a debug-signed build.
    #
    # default: false
    android-release: false

    # Base64-encoded release keystore (`base64 -w0 your.keystore`), typically a secret.
    android-keystore-base64: ''
    # The keystore's store password.
    android-keystore-password: ''
    # The signing key's alias inside the keystore.
    android-key-alias: ''
    # The signing key's own password.
    android-key-password: ''

    # ── iOS (engine v0.7.15, macOS runners only) ─────────────────────────────────
    # Package for iOS: by default the raw .xcodeproj (support/ios/bundle.py + XcodeGen) plus
    # an unsigned iOS Simulator build; with ios-release a signed .ipa.
    #
    # default: false
    ios: false

    # The app's display name. Requires ios.
    #
    # default: "Roves Game"
    ios-app-name: ''

    # The app's bundle identifier (e.g. com.example.mygame). Requires ios.
    #
    # default: "org.roves.game"
    ios-bundle-id: ''

    # Archive and export a signed .ipa through `mach bundle --ios --ios-release` (no raw
    # .xcodeproj in that mode). Requires ios plus the signing inputs below.
    #
    # default: false
    ios-release: false

    # Base64-encoded Apple Distribution certificate + private key (.p12) from your own Apple
    # Developer Program account -- Apple must countersign it, nothing here can produce one.
    ios-certificate-p12-base64: ''
    # The .p12's export password.
    ios-certificate-p12-password: ''
    # Base64-encoded .mobileprovision matching the certificate and bundle ID.
    ios-provisioning-profile-base64: ''
    # Your Apple Developer Program Team ID.
    ios-team-id: ''

    # ── Packaging ────────────────────────────────────────────────────────────────
    # Where the package is assembled, relative to your repo root (replaced if it exists);
    # renamed to artifact-name before zipping.
    #
    # default: roves-bundle-output
    output: ''

    # Base name for the zip and the folder inside it: "my-game" gives my-game.zip
    # containing my-game/.
    #
    # default: roves-game
    artifact-name: ''
```

## Outputs

| Name | Description |
| --- | --- |
| `bundle-dir` | Absolute path to the unzipped package folder (named `artifact-name`) |
| `archive-path` | Absolute path to `<artifact-name>.zip` |
| `mcp-enabled` | `'true'` when the package contains the local MCP bridge, else `'false'` |
| `icon-source` | Desktop: where the icons came from, e.g. `window project (game icon.png 512x512); executable project (ICO generated from game icon.png)` |

## Desktop: the CEF player

The desktop package is the Roves CEF player (Chromium Embedded Framework, SDL3, wgpu) built
and published by the engine's v0.9.0 release. The action picks the asset from the runner and
the inputs, downloads it from
`https://github.com/DRincs-Productions/roves/releases/download/v0.9.0/<asset>` and builds
your package from it:

| Runner | `steam` | `enable-mcp` | Release asset | Your zip contains |
| --- | --- | --- | --- | --- |
| Windows (x64) | `false` | `false` | `roves_shell_windows.zip` | `play.exe`, `play.dll`, `libcef.dll` and the CEF runtime, `game\`, `PROVENANCE.txt`, `SHA256SUMS.txt` |
| Windows (x64) | `true` | `false` | `roves_shell_windows_steam.zip` | the same plus `steam_api64.dll` |
| Windows (x64) | `false` | `true` | `roves_shell_windows_mcp.zip` | the same plus `mcp\` (development only) |
| macOS (arm64) | `false` | - | `roves_shell_macos.zip` | `roves-cef-macos-gate.app`, game in `Contents/Resources/game` |
| macOS (arm64) | `true` | - | `roves_shell_macos_steam.zip` | the same plus `Contents/MacOS/libsteam_api.dylib` |
| Linux (x64) | `false` | - | `roves_shell_linux.zip` | the executable, `libcef.so`, `chrome-sandbox`, `game/` |
| Linux (x64) | `true` | - | `roves_shell_linux_steam.zip` | the same plus `libsteam_api.so` |

What the action does with it:

1. **Verify.** Windows: every file against the package's own `SHA256SUMS.txt` (no file
   missing, changed or unlisted). macOS/Linux: the documented files are present (the `.app`'s
   executable, the CEF framework and icon; `libcef.so`, `chrome-sandbox` with its execute
   bit, `icudtl.dat`, `resources.pak`), and the Steam redistributable is present exactly when
   `steam` is `'true'`. A mismatch fails the run.
2. **Replace the game.** The sample game is removed and `content-dir` is copied into
   `game/` unchanged. The engine files are never modified, except for the icons below.
3. **Apply the project icon** ([Project icon](#project-icon)).
4. **Windows only:** drop the sample game's provenance, append a "game replaced" note to
   `PROVENANCE.txt` and regenerate `SHA256SUMS.txt` (`cef/assemble.ps1`).
5. **Zip** one named folder: `Compress-Archive` on Windows, `ditto` on macOS (keeps the
   framework symlinks), `zip -y` on Linux (keeps symlinks and execute bits).

**Linux sandbox.** Unzipping as a normal user keeps execute bits but not root ownership or the
setuid bit of `chrome-sandbox`. On hosts that restrict unprivileged user namespaces (Ubuntu
23.10+ by default) players or your installer must run
`sudo chown root:root chrome-sandbox && sudo chmod 4755 chrome-sandbox`, otherwise Chromium
stops with "No usable sandbox!". Run the executable from an X11 session or Xwayland, never as
root.

**macOS.** The `.app` is not notarized: Gatekeeper blocks a downloaded copy until the player
allows it, and an app launched from a quarantined location runs translocated. Signing and
notarizing before distribution is your release step.

### Project icon

Your game's icon comes first; the official Roves icon is the fallback. The rules are the
engine's and Roves Packmaster's: `cef/project_icon.py` is an identical copy of the engine's
`support/cef-netrender-probe/packaging/project_icon.py` (Pillow 11.3.0 pinned), and runs on
every desktop platform.

- **Window icon** (title bar, taskbar, Dock while running): `icon-png`, else
  `content-dir/icon.png`, else the largest frame of the project ICO (`icon-ico`, else
  `content-dir/icon.ico` or `favicon.ico`). With none, the package has no `icon.png` and the
  player shows the embedded Roves logo.
- **Windows `play.exe`** (Explorer, shortcuts): `icon-ico`, else an ICO generated from the
  PNG above, else `content-dir/icon.ico` or `favicon.ico`, else the Roves icon shipped in the
  package (`roves.ico`). Patched with electron/rcedit v2.0.0 (SHA-256 pinned).
- **macOS app icon** (Finder, Launchpad, the Dock before launch): the resolved window PNG
  converted to `.icns` with `sips`/`iconutil` (`cef/icns.sh`, an identical copy of the
  engine's `support/cef-macos-gate/packaging/icns.sh`), replacing the Roves `.icns` the
  `.app`'s `CFBundleIconFile` names. Without a project icon the Roves `.icns` stays.
- **Linux**: only the window icon (`icon.png` next to the executable); the package has no
  `.desktop` entry.

Limits: at most 8 MiB; PNG square, 16-2048 px; ICO valid with a square largest frame of at
least 16 px. An explicit `icon-png`/`icon-ico` that breaks them fails the run; an invalid file
found in `content-dir` is a warning and the next source is tried. The loading screen always
shows the Roves logo. The `icon-source` output reports what was used.

### Steam

`steam: 'true'` selects the Steam variant of the same player: the Steamworks redistributable
(`steam_api64.dll`, `libsteam_api.dylib` or `libsteam_api.so`) sits next to the executable and
the game reaches Steam through the Roves host API. The App ID comes from Steam's launch
environment (`SteamAppId`), else a development `steam_appid.txt` next to the executable (put
it in your package yourself for local testing; Steam itself does not need it). Steam missing
or not running is never fatal: the host API answers "unavailable" and the game plays as in
the standard package.

### Local MCP bridge (`enable-mcp`)

Windows only, default `'false'`. With `'true'` the action packages
`roves_shell_windows_mcp.zip`: an AI agent or IDE connected through MCP (Model Context
Protocol) can read the running game's state and console, run JavaScript in the page, click,
press keys and type — useful for automated playtests. The bridge listens only on a local
Windows named pipe protected by a per-session token, but any program running as the same
Windows user can control the game: **development only, never ship that package to players**.
The action requires a complete MCP package (`mcp\enabled`, `mcp\server.mjs`, `mcp\README.md`,
the MCP server dependency and the MCP section of `PROVENANCE.txt`) and never adds MCP files
itself. With `'false'` the output never contains `mcp\` (no activation marker, no server).
See `mcp\README.md` inside the package for connecting a client. `enable-mcp` with `steam`, or
on macOS/Linux, fails the run: no such package is published.

## Android and iOS

Both still use the engine's native WebView tooling at **v0.7.15** (a separate pin from the
desktop player): the action checks out that tag and runs `mach bundle --android`, or
`support/ios/bundle.py` + XcodeGen (`ios-release: 'false'`) / `mach bundle --ios --ios-release`.
Nothing is compiled. Android installs a JDK and the Android SDK itself; iOS needs a macOS
runner. `steam`, `enable-mcp` and `icon-ico` do not apply; iOS does not support
`icon-png` yet (add the icon in Xcode). Android release signing and iOS signing work as before
(see the `android-*` and `ios-*` inputs).

## Migrating to the CEF player

The desktop path no longer downloads the Servo shell (`roves_shell_<platform>.zip` of
v0.7.15) or compiles anything, so every input that configured `mach build` or the Servo
`mach bundle` for desktop is gone. Passing a removed input makes GitHub warn about an
unexpected input; it has no effect.

| Removed input | Replacement |
| --- | --- |
| `advanced-mode`, `release`, `dev`, `production`, `profile`, `target`, `media-stack`, `jobs`, `with-asan`, `with-tsan`, `with-debug-assertions`, `debug-mozjs`, `with-frame-pointer`, `use-crown`, `coverage`, `win-arm64`, `verbose`, `very-verbose`, `build-params`, `bin`, `nightly` | None: the desktop player is prebuilt, with one configuration per platform. |
| `features: steam` | `steam: 'true'` |
| `html-file`, `window-size`, `bundle-params` | None: the player always opens `game/index.html` in its own window. |
| `content-compress`, `content-compression-level`, `content-max-pack-size`, `content-exclude`, `content-boot-include` | None: `game/` holds your files as they are, served by the player. |
| `deb`, `msi`, `dmg`, `package-name`, `package-version` | None yet: the output is a portable zip on every platform. |
| `diagnostic-script` | None. |
| `flavor`, `no-package` | None: they only applied to `mach build`, which Android never ran. |

Other changes:

- `android: 'true'` and `ios: 'true'` no longer need `advanced-mode: 'true'`.
- `icon-png` is now the macOS app icon too, and `icon-ico` also feeds the window icon on
  macOS/Linux when there is no PNG; an explicit invalid icon now fails the run.
- New: `steam`, `enable-mcp`, and the `mcp-enabled`/`icon-source` outputs.
- The `cef-windows/` sub-action (packaging from an engine workflow artifact) was folded into
  this action; use the root action with the release asset instead.
- `@v0` keeps the Servo desktop shell at v0.7.15; the CEF player is `@v1`.

## Tips and Caveats

- Inputs tagged `[roves]` forward to the engine's `mach bundle` (mobile only); the desktop
  inputs are this action's own.
- `content-dir` must contain `index.html` at its root; the run fails early otherwise.
- `output`, when set, is deleted and recreated.
- This action does not set up Node/npm for you — building your game is your own step.

## Releasing this action

Push a `v<major>.<minor>.<patch>` tag (e.g. `v1.0.0`) — see
[`.github/workflows/release.yml`](.github/workflows/release.yml), which creates a GitHub
Release for that tag and force-moves the major-version tag (`v1`) to point at it, so consumers
pinning `uses: DRincs-Productions/roves-action@v1` automatically get every `1.x.y` update.

To also list a release on the [GitHub Marketplace](https://github.com/marketplace?type=actions):
open that release's **Edit release** page and check **"Publish this Action to the GitHub
Marketplace"** — a manual, web-UI-only step (requires org-owner permissions and 2FA on the
publishing account) that this workflow deliberately doesn't attempt to automate. GitHub
validates `action.yml`'s `name`/`description`/`icon`/`color` at that point (`description` in
particular has a hard 125-character limit) — fix and re-release if it flags anything.
