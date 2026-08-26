# roves-action

A single composite GitHub Action (`action.yml`) that builds
[Roves](https://github.com/DRincs-Productions/roves) — a customized Servo fork — and packages
a game's already-built web content into a native bundle, for any third-party game's own CI.
See `README.md` for what it actually does today and what it doesn't.

This repo mirrors the engine repo's own `.github/workflows/test.yml` (see this repo's own
README for that relationship) — it is a separate git repo, not a submodule, checked out as a
sibling of the engine repo (`../roves` from here) on this machine.

## CRITICAL: keep the pinned engine tag in `action.yml` current

There is no `roves-repo`/`roves-ref`/`roves-src-path` input anymore (removed — see the
"design notes" below for why) — this action always targets `DRincs-Productions/roves` at a
fixed tag, hardcoded as a literal string in two places in `action.yml`: the "Checkout Roves
engine source" step's `ref:`, and the "Download prebuilt shell" step's release-asset URL.
`grep -n 'v0\.' action.yml` finds both. Every consumer of this action builds against exactly
that tag — it is **not** something that updates itself when the engine cuts a new release.

This is the *other side* of an obligation already documented in the engine repo's own
`CLAUDE.md` ("Cutting a versioned release" → "sync the shell version in `roves-action` and
`roves-ui`"): every time a new engine tag is cut, both literal occurrences here (and the
version mentioned in `README.md`'s "Base mode" section) must be bumped to point at it, in a
real commit — not a drive-by edit, since this changes what every consumer of this action gets
on their next CI run. If you're working in this repo and notice the pinned tag isn't the
engine's latest release, that's exactly the kind of drift this note exists to catch — fix it
(a real commit, same care as any other default-changing change), don't assume someone else
owns it.

## CRITICAL: the "Fetch tests/wpt/tests/tools" step's hardcoded Servo tag

`action.yml`'s "Checkout Roves engine source" step is followed by a "Fetch
tests/wpt/tests/tools" step — a **third** hardcoded literal (`grep -n 'v0\.' action.yml` above
only finds two) fetching a small sparse-checkout of `tests/wpt/tests/tools/` from upstream
`servo/servo`, not from `DRincs-Productions/roves`. This is not optional cleanup: without it,
every `mach build`/`mach bundle` call in this action crashes immediately with
`ModuleNotFoundError: No module named 'localpaths'` — `mach`'s own command loader
unconditionally imports WPT test tooling that lives under `tests/wpt/`, a directory the engine
repo deliberately excludes from git (~1.3GB of WPT conformance tests). `mach bootstrap` has its
own fast path that skips this import, which is exactly why this went unnoticed for so long:
base mode's own "mach bootstrap" step is skipped too (`if: ... && advanced-mode == 'true'`),
so nothing in this action ever exercised the crashing path until
`.github/workflows/test.yml` (added to *this* repo, mirroring the engine's own rolling "test"
release) actually ran base mode end-to-end against a real game's content and hit it on every
platform. The engine repo's own `CLAUDE.md` had already predicted this exact gap ("mach needs
tests/wpt/tests/tools/ to exist, even for build/bundle" — "and so would roves-action") before
it was ever confirmed here.

The tag passed to `git fetch ... origin v<TAG>` in that step (currently `v0.4.0`) is the
**upstream Servo version** the pinned engine tag above is vendored from — see the engine
repo's own `CUSTOMIZATIONS.md` top-of-file baseline version, *not* the `DRincs-Productions/roves`
release tag (`v0.4.0`) tracked elsewhere in this file. These two versions move independently:
bumping the pinned engine tag above to a new roves release does **not** by itself mean this
Servo tag needs to change — only bump it when that new roves release was itself vendored from
a different upstream Servo version (a rare, bigger upgrade — see the engine repo's own
"Upgrading to a newer Servo version" section). Mirrors the identical workaround in the engine
repo's own `release.yml` (`SERVO_TAG` env there) — if that value there is ever bumped, check
whether this literal here needs to move too.

## `advanced-mode`: design notes

`action.yml` has two entirely different execution paths, both producing the same kind of
output (a bundled game, ready to zip). Base mode (the default) is deliberately the *easier,
safer* path — matching Packmaster's own settings surface — with source compilation demoted
to an explicit, named opt-in for the cases that genuinely need it:

1. **Base mode** (`advanced-mode: 'false'`, the default, never needs setting explicitly):
   skip checkout-and-compile entirely. Download the exact same
   `roves_shell_<platform>[_steam].zip` release asset
   [Roves Packmaster](https://github.com/DRincs-Productions/roves-packmaster) itself downloads
   (see that repo's `src-tauri/src/shell.rs`), at this action's own pinned engine tag, and run
   `mach bundle --bin <extracted binary>` against it — still needs a checkout of the engine's
   own `python`/`mach` tooling to actually run `mach bundle` (and a small, fast `cargo build`
   of `support/content-packer`, which `mach bundle` always does regardless of this flag,
   unless `content-compress: none`), but never compiles the engine itself. This is what makes
   it fast — no native toolchain (GStreamer, mozjs, ANGLE, ...) needs installing at all, since
   the downloaded shell already has all of that baked in.
2. **`advanced-mode: 'true'`**: checkout the engine at that same pinned tag, `mach bootstrap`,
   `mach build`, `mach bundle`. Slow, but every `mach build` flag (`features`, `target`,
   `media-stack`, sanitizers, ...) is available, since this is the only path that actually
   compiles anything.

**Every `mach build`-time input is deliberately incompatible with base mode, and validated as
a hard error, not silently ignored** (`action.yml`'s "Validate base-mode compatibility"
step, which runs first, before checkout, so an incompatible combination fails fast): `target`,
`media-stack`, every sanitizer/debug/`--use-crown`/`--coverage` flag,
`android`/`ohos`/`win-arm64`, `flavor`, `build-params`, `bin`,
`nightly`, and `features` for anything other than `''`/`'steam'`. These flags exist purely to
control *how the engine compiles* — meaningless when nothing gets compiled — and a prebuilt
shell has exactly one fixed build configuration per platform (a `--release` build, the real
GStreamer media stack, no sanitizers). Silently ignoring one of these would be worse than
erroring: a consumer setting `features: 'some-experimental-flag'` in base mode and getting a
bundle that quietly doesn't have that feature is a much worse failure mode than a clear error
telling them why.

**`icon-png`/`icon-ico` are deliberately *not* on that incompatible list** — unlike every
other input above, they stopped being a `mach build`-time (compile-time) concern once the
engine's own `mach bundle` gained native `--icon-png`/`--icon-ico` support (see the engine
repo's own CUSTOMIZATIONS.md, "Runtime + post-build game icon" entry): a runtime file copy
for the window icon, an `rcedit`-based post-build patch for the Windows `.exe`'s own icon
resource, both applying identically whether `mach bundle` is packaging a freshly-compiled
binary or the prebuilt shell base mode downloads. Base mode's own "Resolve paths" step
resolves both to absolute paths and the "mach bundle" step forwards them unconditionally —
see that step's own comment for why no `runner.os`/`advanced-mode` gating is needed there.

**Why there's no `media-stack: dummy`-equivalent variant for base mode**: `dummy` shows up in
this action's own example snippets for `advanced-mode: 'true'` specifically to dodge a real CI
hang — `mach bootstrap`'s GStreamer MSI installer on Windows shells out via a UAC elevation
prompt that hangs forever with no interactive session (see the engine repo's own
`release.yml` comments on this same finding). Base mode never runs `mach bootstrap` at all, so
that hang can't happen there in the first place — the *only* remaining reason to want a
dummy-media base-mode variant would be a genuinely silent game wanting a smaller download,
which isn't a case Packmaster itself supports either. Deliberately kept in parity with
Packmaster (only plain + `_steam` variants exist) rather than adding a third variant to the
engine's `release.yml` for a benefit nobody's asked for yet.

**If a new `mach build`/`mach bundle` flag is ever added to `action.yml`** (mirroring a new
engine flag — see the engine repo's own CLAUDE.md, which requires this action be kept in sync
with the engine's build/bundle CLI surface in the same turn as any such change there): decide
whether it's a build-time flag (add it to the "Validate base-mode compatibility" step's
incompatible list) or a bundle-time flag (works in both paths, no validation needed) — don't
assume; check whether it actually requires the engine to have just been compiled from source,
the same way every existing entry in that step's list does.

**This inverted the action's original default** (compile-from-source, with the prebuilt path
as an opt-in called `use-prebuilt-shell`) — base mode is now the default and source
compilation is the named, opt-in `advanced-mode`, on the reasoning that most consumers want
the same easy, fast path Packmaster itself offers, and should have to deliberately reach for
the slower, riskier one rather than get it by default. Done before this action had any
published tag, so no real consumer was ever broken by the flip.

**`roves-repo`/`roves-ref`/`roves-src-path` were later removed as inputs entirely** — this
action now only ever targets `DRincs-Productions/roves` at its own pinned tag (see the
"CRITICAL" section above), a hardcoded literal instead of an overridable default. Two real
capabilities were deliberately given up by this: a consumer can no longer point at a fork
(`roves-repo`) or, in `advanced-mode: 'true'`, at an unreleased branch/sha (`roves-ref`) to
test against engine changes ahead of a release. Neither had a known real consumer at the time
of removal (same "no published tag yet" reasoning as the base/advanced-mode flip above) — if
that need resurfaces, the input would have to come back rather than being worked around, since
there's no other way to point this action at something other than its own pinned tag.
