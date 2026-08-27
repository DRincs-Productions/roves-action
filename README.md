# Roves GitHub Action

This GitHub Action packages your already-built web content, using
[Roves](https://github.com/DRincs-Productions/roves) — a customized Servo fork used as a
runtime for shipping web-based games as real native apps instead of as a browser tab — into a
double-click-ready native bundle for macOS, Linux, and Windows: `play.app` / `play` /
`play.exe`, or a `.deb` on Linux.

By default it downloads the same prebuilt shell
[Roves Packmaster](https://github.com/DRincs-Productions/roves-packmaster) itself uses and
packs your content into it — same settings surface as Packmaster, no native toolchain to
install, nothing compiled. Set `advanced-mode: 'true'` to instead check out and compile the
engine from source with `mach build` + `mach bundle` (see
[DRincs-Productions/roves](https://github.com/DRincs-Productions/roves)), mirroring that
repo's own
[`.github/workflows/test.yml`](https://github.com/DRincs-Productions/roves/blob/main/.github/workflows/test.yml)
— slower, but every `mach build` flag becomes available, at your own risk. See "Advanced
mode: compiling from source" below.

## What this action does *not* do

- **Build your game's own web content.** That's your bundler's job (Vite, webpack, whatever) —
  run it in a step before this action, then point `content-dir` at the result.
- **Upload anything anywhere.** This action produces a zipped bundle on disk and exposes its
  path as an output (`archive-path`) — attaching it to a release, a workflow artifact, an
  itch.io upload, etc. is your own workflow's job. See the examples below for both the
  "workflow artifact" and "GitHub Release" flavors.
- **Cross-compile for consoles.** Desktop (Windows/macOS/Linux) is the only thing that actually
  works today — run this action on `windows-latest`/`macos-latest`/`ubuntu-latest`, one job per
  platform. See [Supported platforms](https://github.com/DRincs-Productions/roves#supported-platforms)
  in the engine's own README.

## Example

The most common case: build for all three desktop platforms and upload each as a workflow
artifact.

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

      - name: build game content
        uses: actions/setup-node@v4
        with:
          node-version: '22'
      - run: npm install && npm run build

      - name: build & bundle with Roves
        id: roves
        uses: DRincs-Productions/roves-action@v0
        with:
          content-dir: dist
          artifact-name: ${{ matrix.name }}

      - uses: actions/upload-artifact@v4
        with:
          name: ${{ matrix.name }}
          path: ${{ steps.roves.outputs.archive-path }}
```

## More examples

**Publish to a GitHub Release instead of a workflow artifact** — triggers on a version tag,
builds all three platforms, and attaches each zip to a release for that tag:

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
      - run: npm install && npm run build

      - id: roves
        uses: DRincs-Productions/roves-action@v0
        with:
          content-dir: dist
          artifact-name: ${{ matrix.name }}

      - env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: gh release upload "${{ github.ref_name }}" "${{ steps.roves.outputs.archive-path }}"
```

**An installable package instead of the default portable binary** — `deb`/`msi`/`dmg` are
each specific to their own OS (see "Portable vs. installable packages" below), so a
multi-platform matrix picks the right one per `os`, plus content packing tuned for a
save-data folder that shouldn't be compressed:

```yml
- uses: DRincs-Productions/roves-action@v0
  with:
    content-dir: dist
    artifact-name: my-game_linux-deb
    deb: 'true' # msi: 'true' on windows-latest, dmg: 'true' on macos-latest
    package-name: my-game
    package-version: ${{ github.ref_name }}
    content-exclude: |
      saves/**
      local-data/**
```

**A custom game icon** — works in the default base mode, no `advanced-mode` needed:

```yml
- uses: DRincs-Productions/roves-action@v0
  with:
    content-dir: dist
    artifact-name: my-game_windows
    icon-png: assets/icon.png
    icon-ico: assets/icon.ico
```

## Usage

```yml
- uses: DRincs-Productions/roves-action@v0
  with:
    # Advanced mode, at your own risk: instead of downloading the same prebuilt shell
    # Packmaster itself downloads (the default -- same settings as Packmaster, nothing
    # compiled), check out the pinned engine tag's source and build it from source with
    # `mach build` + `mach bundle`. Slower, but every mach-build-time input below (features other
    # than 'steam', target, media-stack, sanitizers, bin, nightly, ...)
    # becomes available -- see "Advanced mode: compiling from source" below.
    #
    # default: false
    advanced-mode: false

    # Run `mach bootstrap` (installs the native build dependencies mach build/bundle need).
    # Set to 'false' only if you already provisioned them yourself in an earlier step (e.g.
    # to share a cache across multiple calls to this action). Ignored unless advanced-mode
    # is 'true' -- there's nothing to bootstrap for otherwise, since nothing gets compiled.
    #
    # default: true
    bootstrap: true

    # ── Your game's content ──────────────────────────────────────────────────────
    # Path (relative to your repo root) to your already-built web content, e.g. a
    # Vite/webpack dist/ folder. Roves doesn't know or care what produced it.
    #
    # required
    content-dir: ''

    # Path (relative to your repo root) to a window/taskbar icon (PNG). Works in either mode
    # -- mach bundle applies it after packaging, no compile needed. Not supported on macOS
    # yet (its own Dock/app icon has no runtime override).
    #
    # default: auto-detect -- an icon.png sitting directly in content-dir (many bundlers
    # already emit one there for their own PWA manifest), falling back to Roves' own
    # branding if there isn't one. Set explicitly to override either.
    icon-png: ''

    # Path (relative to your repo root) to a Windows .exe icon (multi-size .ico).
    # Windows-only; ignored on other platforms. Also works in either mode -- mach bundle
    # patches the bundled play.exe's icon resource in place via rcedit.
    #
    # default: auto-detect -- same as icon-png, but looks for icon.ico in content-dir
    icon-ico: ''

    # ── `mach build` — plain upstream Servo flags, none of these are Roves-specific ─
    # Every one of these needs advanced-mode: 'true' -- they only control how the engine
    # itself compiles, which only happens in that mode. See "Advanced mode: compiling from
    # source" below.

    # Optimized build ([servo] `--release`).
    #
    # default: false
    release: false

    # Debug build ([servo] `--dev`) — the implicit default if release/production/profile
    # are all left unset.
    #
    # default: false
    dev: false

    # Release build without debug assertions ([servo] `--prod`).
    #
    # default: false
    production: false

    # Build with a custom Cargo profile instead of dev/release/prod ([servo] `--profile`).
    #
    # default: unset
    profile: ''

    # Cross-compile target triple ([servo] `--target`). Native desktop builds should leave
    # this empty — see "What this action does not do" above.
    #
    # default: unset
    target: ''

    # Extra Cargo features, space-separated ([servo] `--features`), e.g. "steam".
    #
    # default: unset
    features: ''

    # Media backend ([servo] `--media-stack`, `gstreamer` or `dummy`). `dummy` avoids
    # needing GStreamer installed at all, at the cost of no audio/video playback.
    #
    # default: unset (mach's own default)
    media-stack: ''

    # Parallel build job count, forwarded to Cargo ([servo] `--jobs`).
    #
    # default: unset
    jobs: ''

    # Build with AddressSanitizer ([servo] `--with-asan`).
    #
    # default: false
    with-asan: false

    # Build with ThreadSanitizer ([servo] `--with-tsan`).
    #
    # default: false
    with-tsan: false

    # Keep debug assertions in an otherwise-release build ([servo] `--with-debug-assertions`).
    #
    # default: false
    with-debug-assertions: false

    # Build mozjs with debug assertions ([servo] `--debug-mozjs`).
    #
    # default: false
    debug-mozjs: false

    # Enable frame pointers, for the background hang monitor ([servo] `--with-frame-pointer`).
    #
    # default: false
    with-frame-pointer: false

    # Enable Servo's `crown` JS-GC lint tool ([servo] `--use-crown`).
    #
    # default: false
    use-crown: false

    # Build with code-coverage instrumentation ([servo] `--coverage`) — also affects which
    # binary `mach bundle` looks for.
    #
    # default: false
    coverage: false

    # Build for the default Android target ([servo] `--android`). Not a supported Roves
    # platform yet — see the engine README's platform table.
    #
    # default: false
    android: false

    # Build for the default OpenHarmony target ([servo] `--ohos`). Not a supported Roves
    # platform yet.
    #
    # default: false
    ohos: false

    # Use the arm64 Windows target instead of x64 ([servo] `--win-arm64`).
    #
    # default: false
    win-arm64: false

    # Gradle/Hvigor product flavor, Android/OpenHarmony packaging only ([servo] `--flavor`).
    #
    # default: unset
    flavor: ''

    # Verbose build output ([servo] `--verbose`).
    #
    # default: false
    verbose: false

    # Very verbose build output, also dumps build env vars ([servo] `--very-verbose`).
    #
    # default: false
    very-verbose: false

    # Android only: skip packaging into a .apk after building ([servo] `--no-package`).
    #
    # default: false
    no-package: false

    # Extra passthrough arguments appended verbatim to `mach build`, space-separated.
    #
    # default: unset
    build-params: ''

    # ── `mach bundle` — added by Roves, no upstream Servo equivalent ────────────────
    # Entry html file, relative to content-dir ([roves] `--html-file`). Defaults to
    # "index.html", not mach's own "dist/index.html" default — see "Tips and Caveats".
    #
    # default: index.html
    html-file: ''

    # Initial window size ([roves] `--window-size`).
    #
    # default: 1280x720
    window-size: ''

    # Where mach bundle writes the packaged game, relative to your repo root ([roves]
    # `--output`). Leave unset unless you specifically need to know the path before this
    # action's own `bundle-dir` output is available.
    #
    # default: an action-controlled path, exposed via the `bundle-dir` output
    output: ''

    # Pack content into tar+zstd archives, or copy it in as loose files ([roves]
    # `--content-compress`, `auto` or `none`).
    #
    # default: auto
    content-compress: ''

    # zstd compression level used by content-compress=auto ([roves]
    # `--content-compression-level`).
    #
    # default: 1
    content-compression-level: ''

    # Max size per content archive before splitting, e.g. 500M, 1G ([roves]
    # `--content-max-pack-size`).
    #
    # default: 500M
    content-max-pack-size: ''

    # Globs (relative to content-dir) of files to leave loose/uncompressed instead of
    # packing ([roves] `--content-exclude`, repeatable) — one per line for more than one.
    #
    # default: unset
    content-exclude: ''

    # Globs (relative to content-dir), one per line for more than one, of extra files to
    # force into the eager boot set ([roves] `--content-boot-include`, repeatable).
    #
    # default: unset
    content-boot-include: ''

    # Build an installable .deb instead of the default self-contained binary ([roves]
    # `--deb`). Linux only — see "Portable vs. installable packages" below.
    #
    # default: false
    deb: false

    # Build an installable .msi instead of the default self-contained play.exe bundle
    # ([roves] `--msi`). Windows only. Requires WiX's candle/light on PATH — see "Portable
    # vs. installable packages" below.
    #
    # default: false
    msi: false

    # Wrap the default play.app bundle in an installable .dmg disk image ([roves] `--dmg`).
    # macOS only.
    #
    # default: false
    dmg: false

    # Package name to use with deb/msi/dmg ([roves] `--package-name`). Ignored unless one of
    # those is true.
    #
    # default: roves
    package-name: ''

    # Package version to use with deb/msi/dmg ([roves] `--package-version`). Ignored unless
    # one of those is true. For msi specifically, must be 1-4 dot-separated integers
    # (0-65535 each, e.g. "1.2.3") — mach bundle errors clearly otherwise.
    #
    # default: 0.0.0
    package-version: ''

    # Ship a diagnose.bat/diagnose.sh alongside the bundle ([roves] `--diagnostic-script`,
    # portable/msi/dmg only, not deb) that launches the game from a console and prints its
    # exit code plus roves.log inline — for testers to run when a build appears to do
    # nothing. Off by default: a real release has no reason to carry this debug tooling
    # unasked.
    #
    # default: false
    diagnostic-script: false

    # Explicit path to the servoshell binary to bundle, bypassing auto-resolution from the
    # build-profile flags above ([servo] `--bin`). Needs advanced-mode: 'true' -- base mode
    # already points this at the downloaded prebuilt shell itself.
    #
    # default: unset
    bin: ''

    # Bundle a dated nightly build instead of a just-built binary ([servo] `--nightly`,
    # format YYYY-MM-DD). Needs advanced-mode: 'true', for the same reason as `bin` above.
    #
    # default: unset
    nightly: ''

    # Extra launch arguments baked into the bundle — passed to servoshell every time the
    # shipped game starts, space-separated.
    #
    # default: unset
    bundle-params: ''

    # ── Packaging — this action's own convention, not a mach flag ───────────────────
    # Base name for the zipped archive and the folder inside it, e.g. "my-game" produces
    # my-game.zip containing a my-game/ folder (never zipped at the archive root — see
    # "Tips and Caveats").
    #
    # default: roves-game
    artifact-name: ''
```

## Outputs

| Name | Description |
| --- | --- |
| `bundle-dir` | Absolute path to the unzipped bundle folder (named `artifact-name`) |
| `archive-path` | Absolute path to `<artifact-name>.zip` |

## Custom game icon

`icon-png` sets the window/taskbar icon; `icon-ico` (Windows only) sets the `.exe`'s own icon
resource — both applied by `mach bundle` itself, after packaging, in either mode (see
[CUSTOMIZATIONS.md]'s "Runtime + post-build game icon" entry for exactly how). Not supported
on macOS yet — its own Dock/app icon has no runtime override, and `mach bundle` prints a
warning and ignores `icon-png` there rather than failing the run.

Omit either and `mach bundle` auto-detects one instead: if `content-dir` itself contains an
`icon.png`/`icon.ico`, that's used automatically — many bundlers already emit one there for
their own PWA manifest, so a game that already has one gets its own icon for free, no input
needed (see [CUSTOMIZATIONS.md]'s 2026-08-27 entry). Falls back to Roves' own default
branding only if neither the input nor an auto-detected file exists.

[CUSTOMIZATIONS.md]: https://github.com/DRincs-Productions/roves/blob/main/CUSTOMIZATIONS.md

## Portable vs. installable packages

By default, on every platform, this action produces a **portable** bundle — no install step.
Each platform also has one installable alternative, each gated to its own OS the same way
`deb` already was:

| Platform (`runner.os`) | Portable (default) | Installable input |
| --- | --- | --- |
| `Linux` | `play` + `.so` deps, flat | `deb: 'true'` → a real `.deb` |
| `Windows` | `play.exe` + a few DLLs, GStreamer plugins in `lib/` | `msi: 'true'` → a real `.msi` (needs WiX's `candle`/`light` on `PATH` — see the `msi` input's own note and the "Add WiX Toolset to PATH" step this action runs for you when `msi: 'true'` on `windows-latest`) |
| `macOS` | `play.app` | `dmg: 'true'` → that same `.app`, wrapped in a `.dmg` |

`deb`/`msi`/`dmg` are each silently ignored on the OSes they don't apply to (see "Tips and
Caveats" below), so a single input set — including turning more than one on at once — can
stay the same across a matrix; only the one matching the current runner actually does
anything. `package-name`/`package-version` name and version whichever installable format
you asked for; they're ignored entirely when none of `deb`/`msi`/`dmg` are set.

## Content packing

By default, `mach bundle` doesn't ship `content-dir` as loose, individually browsable
files — it packs it into a handful of tar+zstd archives, extracted back by the engine
itself at launch (an eager "boot set" for the html file and whatever it directly
references, everything else lazily on first request). See
[DRincs-Productions/roves]'s own README, "Content packing & compression" section, for the
full design (why, the boot-set/lazy split, the archive layout) — these inputs are a direct
passthrough to the `mach bundle` flags documented there:

| Input | Description | Default |
| --- | --- | --- |
| `content-compress` | `auto` or `none` — pack `content-dir` into archives, or copy it in as loose, uncompressed files with none of the below. | `auto` |
| `content-compression-level` | zstd compression level used by `content-compress: 'auto'`. Low favors speed. | `1` |
| `content-max-pack-size` | Max size per content archive (e.g. `500M`, `1G`) before splitting into further parts. | `500M` |
| `content-exclude` | Globs (relative to `content-dir`) of files to leave loose/uncompressed instead of packing — one per line for more than one. | unset |
| `content-boot-include` | Globs (relative to `content-dir`), one per line for more than one, of extra files to force into the eager boot set. | unset |

[DRincs-Productions/roves]: https://github.com/DRincs-Productions/roves#content-packing--compression

## Base mode (the default)

By default (`advanced-mode: 'false'`, which you never need to set explicitly), this action
skips checking out and compiling the engine entirely — it downloads the same
`roves_shell_<platform>[_steam].zip` release asset
[Roves Packmaster](https://github.com/DRincs-Productions/roves-packmaster) itself downloads, at
this action's own pinned engine tag (hardcoded in `action.yml`, not a configurable input — see
"Releasing this action" below for how that pin gets bumped), and runs
`mach bundle --bin <the extracted binary>` against it. No Rust/native toolchain build of the
engine at all — just a download plus packing your content into it, which is what makes it
fast, and why it needs no `mach bootstrap` step either:

```yml
- uses: DRincs-Productions/roves-action@v0
  with:
    content-dir: dist
    artifact-name: my-game_windows
```

Every input that only exists to control *how the engine compiles* is incompatible with base
mode — a prebuilt shell has one fixed build configuration (a `--release` build, the real
GStreamer media stack, no sanitizers), so `features` (besides `'steam'`, the one published
variant), `target`, `media-stack`, every sanitizer/debug/`--use-crown`/`--coverage` flag,
`android`/`ohos`/`win-arm64`, `flavor`, `build-params`, `bin`, and
`nightly` all need `advanced-mode: 'true'` (see below) — setting any of them to a non-default
value in base mode fails the run with a clear error rather than silently ignoring your input.
Everything else — `content-dir`, `icon-png`/`icon-ico`, and all of `mach bundle`'s own inputs
(`html-file`, `content-compress`, `deb`/`msi`/`dmg`, `diagnostic-script`, ...) — works exactly
the same in either mode, since none of that is a build-time concern.

## Advanced mode: compiling from source

Set `advanced-mode: 'true'` to check out this action's pinned engine tag's source and build it
from source with `mach build` + `mach bundle` instead — mirroring the engine repo's own
[`.github/workflows/test.yml`](https://github.com/DRincs-Productions/roves/blob/main/.github/workflows/test.yml):

```yml
- uses: DRincs-Productions/roves-action@v0
  with:
    content-dir: dist
    artifact-name: my-game_windows
    advanced-mode: 'true'
    media-stack: dummy
```

This is slower (compiling Rust, with a large dependency graph, on every call) and needs
`mach bootstrap` to install the engine's own native build dependencies first (this action
does that for you, unless `bootstrap: 'false'`) — but every `mach build` flag becomes
available: cross-compile `target`, extra Cargo `features`, sanitizers, an explicit
`bin`/`nightly` to bundle instead of building, and so on (`icon-png`/`icon-ico` already work
the same in base mode — see above, nothing advanced-mode-specific about them anymore).
The engine tag itself is still this action's own pinned version — not something you can point
at an unreleased commit; if you need that, build against a fork of this action instead.

If your CI runs this often, either cache Cargo's registry/target directories yourself around
this action (e.g. `actions/cache` keyed on this action's own version + your lockfile — this
action doesn't do that for you, since the right cache key/scope depends on your own workflow),
or reconsider whether you actually need advanced mode at all for that particular run.

## Tips and Caveats

- Every input is tagged `[servo]` (plain upstream Servo — `mach build`, or `mach bundle`'s
  build-profile-selection flags, which exist purely to *locate* the binary `mach build`
  already produced) or `[roves]` (added by Roves — `mach bundle` doesn't exist upstream at
  all). Almost everything is optional; the one required input is `content-dir`.
- `html-file` defaults to `index.html`, not mach's own `dist/index.html` default: this action
  always passes `content-dir` as an absolute path pointing *directly* at your built output
  (e.g. the `dist/` folder itself, not its parent) — so the entry file is normally right at
  that root. Override `html-file` if your entry html lives deeper inside `content-dir`.
- `content-exclude`/`content-boot-include` are repeatable flags on the real `mach bundle` CLI;
  pass more than one glob as a YAML multi-line string (one per line), not a comma/space-
  separated list.
- If you set both `release` and `dev` (or any other mutually-exclusive pair mach itself
  rejects), that's forwarded to mach as-is and mach's own argument parser is what errors —
  this action does no validation of its own on top of mach's.
- `deb`/`msi`/`dmg` are each only honored on their own OS; setting any of them on the wrong
  runner is silently ignored rather than erroring, so a single input set (even with more
  than one turned on) can stay the same across a matrix — see "Portable vs. installable
  packages" above.
- This action does not set up Node/npm/etc. for you — building your game's own web content is
  entirely your own step, before calling this action.

## Releasing this action

Push a `v<major>.<minor>.<patch>` tag (e.g. `v0.1.3`) — see
[`.github/workflows/release.yml`](.github/workflows/release.yml), which creates a GitHub
Release for that tag and force-moves the major-version tag (`v0`) to point at it, so consumers
pinning `uses: DRincs-Productions/roves-action@v0` automatically get every `0.x.y` update.

To also list a release on the [GitHub Marketplace](https://github.com/marketplace?type=actions):
open that release's **Edit release** page and check **"Publish this Action to the GitHub
Marketplace"** — a manual, web-UI-only step (requires org-owner permissions and 2FA on the
publishing account) that this workflow deliberately doesn't attempt to automate. GitHub
validates `action.yml`'s `name`/`description`/`icon`/`color` at that point (`description` in
particular has a hard 125-character limit) — fix and re-release if it flags anything.
