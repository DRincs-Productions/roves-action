# roves-action

A single composite GitHub Action (`action.yml`) that builds
[Roves](https://github.com/DRincs-Productions/roves) — a customized Servo fork — and packages
a game's already-built web content into a native bundle, for any third-party game's own CI.
See `README.md` for what it actually does today and what it doesn't.

This repo mirrors the engine repo's own `.github/workflows/test.yml` (see this repo's own
README for that relationship) — it is a separate git repo, not a submodule, checked out as a
sibling of the engine repo (`../roves` from here) on this machine.

## CRITICAL: keep `roves-ref`'s default pinned to a real, current engine release

`action.yml`'s `roves-ref` input defaults to a specific engine tag (e.g. `'v0.2.0'`) — every
consumer of this action that doesn't override `roves-ref` explicitly builds against exactly
that tag. This is **not** something that updates itself when the engine cuts a new release.

This is the *other side* of an obligation already documented in the engine repo's own
`CLAUDE.md` ("Cutting a versioned release" → "sync the shell version in `roves-action` and
`roves-ui`"): every time a new engine tag is cut, `roves-ref`'s `default` here (and the
matching commented-out example in `README.md`'s usage block) must be bumped to point at it, in
a real commit — not a drive-by edit, since this changes what every consumer building without
an explicit `roves-ref` override gets on their next CI run. If you're working in this repo and
notice `roves-ref` pointing at a tag that isn't the engine's latest release, that's exactly the
kind of drift this note exists to catch — fix it (a real commit, same care as any other
default-changing change), don't assume someone else owns it.

## `use-prebuilt-shell`: design notes

`action.yml` has two entirely different execution paths, both producing the same kind of
output (a bundled game, ready to zip):

1. **Compile from source** (the default): checkout the engine at `roves-ref`, `mach
   bootstrap`, `mach build`, `mach bundle`. Slow, but every `mach build` flag (`features`,
   `target`, `media-stack`, sanitizers, ...) is available, since this path is the only one
   that actually compiles anything.
2. **`use-prebuilt-shell: 'true'`**: skip checkout-and-compile entirely. Download the exact
   same `roves_shell_<platform>[_steam].zip` release asset
   [Roves Packmaster](https://github.com/DRincs-Productions/roves-packmaster) itself downloads (see
   that repo's `src-tauri/src/shell.rs`), at the exact `roves-ref` tag, and run `mach bundle
   --bin <extracted binary>` against it — still needs a checkout of the engine's own
   `python`/`mach` tooling to actually run `mach bundle` (and a small, fast `cargo build` of
   `support/content-packer`, which `mach bundle` always does regardless of this flag, unless
   `content-compress: none`), but never compiles the engine itself. This is what makes it
   fast — no native toolchain (GStreamer, mozjs, ANGLE, ...) needs installing at all, since
   the downloaded shell already has all of that baked in.

**Every `mach build`-time input is deliberately incompatible with path 2, and validated as a
hard error, not silently ignored** (`action.yml`'s "Validate use-prebuilt-shell compatibility"
step, which runs first, before checkout, so an incompatible combination fails fast): `target`,
`media-stack`, every sanitizer/debug/`--use-crown`/`--coverage` flag,
`android`/`ohos`/`win-arm64`, `flavor`, `build-params`, `icon-png`/`icon-ico`, `bin`,
`nightly`, and `features` for anything other than `''`/`'steam'`. These flags exist purely to
control *how the engine compiles* — meaningless when nothing gets compiled — and a prebuilt
shell has exactly one fixed build configuration per platform (a `--release` build, the real
GStreamer media stack, no sanitizers). Silently ignoring one of these would be worse than
erroring: a consumer setting `features: 'some-experimental-flag'` alongside
`use-prebuilt-shell: 'true'` and getting a bundle that quietly doesn't have that feature is a
much worse failure mode than a clear error telling them why.

**Why there's no `media-stack: dummy`-equivalent variant for prebuilt mode**: `dummy` shows up
in this action's own example snippets for compile-from-source specifically to dodge a real CI
hang — `mach bootstrap`'s GStreamer MSI installer on Windows shells out via a UAC elevation
prompt that hangs forever with no interactive session (see the engine repo's own
`release.yml` comments on this same finding). Prebuilt mode never runs `mach bootstrap` at
all, so that hang can't happen there in the first place — the *only* remaining reason to want
a dummy-media prebuilt variant would be a genuinely silent game wanting a smaller download,
which isn't a case Packmaster itself supports either. Deliberately kept in parity with
Packmaster (only plain + `_steam` variants exist) rather than adding a third variant to the
engine's `release.yml` for a benefit nobody's asked for yet.

**If a new `mach build`/`mach bundle` flag is ever added to `action.yml`** (mirroring a new
engine flag — see the engine repo's own CLAUDE.md, which requires this action be kept in sync
with the engine's build/bundle CLI surface in the same turn as any such change there): decide
whether it's a build-time flag (add it to the "Validate use-prebuilt-shell compatibility"
step's incompatible list) or a bundle-time flag (works in both paths, no validation needed) —
don't assume; check whether it actually requires the engine to have just been compiled from
source, the same way every existing entry in that step's list does.
