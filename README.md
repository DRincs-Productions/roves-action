# Roves GitHub Action

This GitHub Action builds [Roves](https://github.com/DRincs-Productions/roves) — a customized
Servo fork used as a runtime for shipping web-based games as real native apps instead of as a
browser tab — from source, and packages your already-built web content into a double-click-
ready native bundle for macOS, Linux, and Windows: `play.app` / `play` / `play.exe`, or a
`.deb` on Linux.

By default it runs `mach build` + `mach bundle` (see
[DRincs-Productions/roves](https://github.com/DRincs-Productions/roves)) against a pinned
checkout of the engine, mirroring that repo's own
[`.github/workflows/test.yml`](https://github.com/DRincs-Productions/roves/blob/main/.github/workflows/test.yml)
— generalized so any game's own CI can call it instead of reimplementing that pipeline. Set
`use-prebuilt-shell: 'true'` to skip compiling the engine altogether and download the same
prebuilt shell Packmaster itself uses instead — see "Prebuilt shell mode" below.

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
        uses: DRincs-Productions/roves-action@v1
        with:
          roves-ref: v0.2.1 # defaults to the latest release tag anyway — see that input's own note below
          content-dir: dist
          artifact-name: ${{ matrix.name }}
          release: 'true'
          media-stack: dummy

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
        uses: DRincs-Productions/roves-action@v1
        with:
          content-dir: dist
          artifact-name: ${{ matrix.name }}
          release: 'true'
          media-stack: dummy

      - env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: gh release upload "${{ github.ref_name }}" "${{ steps.roves.outputs.archive-path }}"
```

**An installable package instead of the default portable binary** — `deb`/`msi`/`dmg` are
each specific to their own OS (see "Portable vs. installable packages" below), so a
multi-platform matrix picks the right one per `os`, plus a custom icon and content packing
tuned for a save-data folder that shouldn't be compressed:

```yml
- uses: DRincs-Productions/roves-action@v1
  with:
    content-dir: dist
    artifact-name: my-game_linux-deb
    deb: 'true' # msi: 'true' on windows-latest, dmg: 'true' on macos-latest
    package-name: my-game
    package-version: ${{ github.ref_name }}
    icon-png: assets/icon.png
    content-exclude: |
      saves/**
      local-data/**
```

## Usage

```yml
- uses: DRincs-Productions/roves-action@v1
  with:
    # ── Engine checkout ──────────────────────────────────────────────────────────
    # The Roves engine repo to check out and build. Override only for a fork.
    #
    # default: DRincs-Productions/roves
    roves-repo: ''

    # Git ref (branch/tag/sha) of roves-repo to build against. Defaults to the latest
    # versioned Roves release tag — override to pin to a different tag/branch/sha (e.g.
    # 'main' to track the latest unreleased commit instead, at the cost of this action's
    # behavior possibly changing under you between runs).
    #
    # default: v0.2.1
    roves-ref: ''

    # Where to check out roves-repo, relative to your own repo root.
    #
    # default: roves-src
    roves-src-path: ''

    # Run `mach bootstrap` (installs the native build dependencies mach build/bundle need).
    # Set to 'false' only if you already provisioned them yourself in an earlier step (e.g.
    # to share a cache across multiple calls to this action).
    #
    # default: true
    bootstrap: true

    # Skip checking out and compiling the engine from source entirely -- download the same
    # prebuilt shell Packmaster itself downloads, at the exact roves-ref tag, instead. Much
    # faster, at the cost of every mach-build-time input below (features other than 'steam',
    # target, media-stack, sanitizers, icon-png/icon-ico, bin, nightly, ...) no longer being
    # configurable -- see "Prebuilt shell mode" below before turning this on.
    #
    # default: false
    use-prebuilt-shell: false

    # ── Your game's content ──────────────────────────────────────────────────────
    # Path (relative to your repo root) to your already-built web content, e.g. a
    # Vite/webpack dist/ folder. Roves doesn't know or care what produced it.
    #
    # required
    content-dir: ''

    # Path (relative to your repo root) to a window/taskbar icon (PNG). See "Known
    # limitation: game icon" below before relying on this.
    #
    # default: unset (keeps Roves' own default branding)
    icon-png: ''

    # Path (relative to your repo root) to a Windows .exe icon (multi-size .ico).
    # Windows-only; ignored on other platforms. Same caveat as icon-png.
    #
    # default: unset
    icon-ico: ''

    # ── `mach build` — plain upstream Servo flags, none of these are Roves-specific ─
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
    # build-profile flags above ([servo] `--bin`).
    #
    # default: unset
    bin: ''

    # Bundle a dated nightly build instead of a just-built binary ([servo] `--nightly`,
    # format YYYY-MM-DD).
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

## Known limitation: game icon

Roves' window/taskbar/`.exe`-icon fallback
([`ports/servoshell/build.rs`](https://github.com/DRincs-Productions/roves/blob/main/ports/servoshell/build.rs))
is currently hardcoded to look for `test-page/public/icon.png`/`icon.ico` *inside the engine
checkout* — a leftover of Roves' own test fixture, not yet a generic per-game mechanism (see
[CUSTOMIZATIONS.md]'s "Game-supplied icon" entry). The `icon-png`/`icon-ico` inputs work around
this by copying your files into that exact hardcoded path before `mach build` runs — it works
today, but is fragile against a future Roves refactor of that fallback path. Omit both to keep
Roves' own default branding instead.

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

## Prebuilt shell mode

`use-prebuilt-shell: 'true'` skips checking out and compiling the engine entirely — it
downloads the same `roves_shell_<platform>[_steam].zip` release asset
[Roves Packmaster](https://github.com/DRincs-Productions/roves-ui) itself downloads, at the
exact `roves-ref` tag, and runs `mach bundle --bin <the extracted binary>` against it. No
Rust/native toolchain build of the engine at all — just a download plus packing your content
into it, which is what makes it fast:

```yml
- uses: DRincs-Productions/roves-action@v1
  with:
    content-dir: dist
    artifact-name: my-game_windows
    use-prebuilt-shell: 'true'
```

This trades away every input that only exists to control *how the engine compiles* — a
prebuilt shell has one fixed build configuration (a `--release` build, the real GStreamer
media stack, no sanitizers), so `features` (besides `'steam'`, the one published variant),
`target`, `media-stack`, every sanitizer/debug/`--use-crown`/`--coverage` flag,
`android`/`ohos`/`win-arm64`, `flavor`, `build-params`, `icon-png`/`icon-ico`, `bin`, and
`nightly` are all incompatible with it — setting any of them to a non-default value together
with `use-prebuilt-shell: 'true'` fails the run with a clear error rather than silently
ignoring your input. Everything else — `content-dir` and all of `mach bundle`'s own inputs
(`html-file`, `content-compress`, `deb`/`msi`/`dmg`, `diagnostic-script`, ...) — works exactly
the same either way, since none of that is a build-time concern.

`roves-ref` has to stay an exact published release tag for this to work (the default already
is one) — `main` or any other unreleased ref has no published shell asset to download.

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
- By default, `mach build` really does compile the engine from source on every call to this
  action, which is slow (Rust, and a large dependency graph). If your CI runs this often,
  either turn on `use-prebuilt-shell` (see below) or cache Cargo's registry/target
  directories yourself around this action (e.g. `actions/cache` keyed on `roves-ref` + your
  lockfile) — this action doesn't do the latter for you, since the right cache key/scope
  depends on your own workflow.
- This action does not set up Node/npm/etc. for you — building your game's own web content is
  entirely your own step, before calling this action.

## Releasing this action

See [`.github/workflows/release.yml`](.github/workflows/release.yml) and the "Releasing"
section of the repo's contributor docs for how new versions of *this action itself* get
published and how the `v1`-style major tag stays up to date.
