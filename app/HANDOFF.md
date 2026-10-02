# HANDOFF — 2026-09-02

Open work and live state. Standing context is in `CLAUDE.md` (this repo) and
`../shellbros.github.io/CLAUDE.md`. **Read those first** — this file only covers
what is unfinished.

## State at handoff

| Repo | Branch | Unpushed | Live |
|---|---|---|---|
| `ShellShockers` | `portalBranch` | 0 | — |
| `shellbros.github.io` | `main` | 1 | build **41** (`8555cdd`) |
| `mathlete` | `main` | 1 | build **51** (`df78f33`) |

The 1 unpushed commit in each shell is the `purge.py` rewrite plus its doc update.
It changes no served file — verify with `git show --stat HEAD` before pushing.

`mathlete` also has `standalone-mathlete.html` dirty. That is a build artifact;
the next build wipes and regenerates it. Do not commit it by hand.

**Never push without asking.**

---

## 1. FIXED IN SOURCE, NOT YET BUILT -- bare `img/...` paths off-origin

Fixed on `../ShellShockers` `portalBranch` in `183468859` (committed locally,
**not pushed**). Still needs a recompile and a rebuild of both shells before it
is live -- nothing has changed on the live sites yet.

Was: the bundle emitted relative `img/...` URLs, which resolve against the
host's document base off-origin and 404. Reported as broken grenade icons on a
third-party host.

The scope recorded here previously (44 literals / 26 files) was measured before
develop was merged into `portalBranch`; the real count at fix time was 147
occurrences across 39 files.

### What was done

`cdnPath()` prefixes `window.JSCDN` when set and returns the path untouched when
it is not, so shellshock.io, CrazyGames, local dev and server-side keep their
existing behaviour. It passes absolute URLs through unchanged and is idempotent.

Duplicated deliberately as `src/home/cdn.js` and `src/shared/cdn.js` -- `home.js`
is an esbuild ESM bundle, `shellshock.js` is concatenated by `compile.sh`, so
they cannot share a module. Change both or neither.

Applied at choke points, not at every literal:

| Choke point | Covers |
|---|---|
| `lazyLoadDirective` in `src/home/globals.js` | every `v-lazyload :data-src` image |
| `$cdn` on `globalProperties` | template `src=` / `href=` (49 sites) |
| `buttonIcon()` in `settings-gamepad-binder.js` | controller glyph HTML, rendered via `v-html` |

Left relative on purpose, so do not "finish" them: values prefixed downstream at
their binding or by the directive; `services/twitchStreamScraper.js:6`, which is
a filesystem path and not a URL; and `src/mapeditor/`, a separate bundle not
served on the portal.

Markup inside HTML comment blocks was also left alone. 17 candidate sites sit in
commented-out regions (the whole kotc instruction popup in `root/template.js`,
parts of `game-screen.js` and `equip-screen.js`); Vue strips comments, so those
never reach the DOM. Verified by running the precompiler on the pre-change file
and getting the same empty result.

### Verified

Both helpers agree on 20 shared cases; `cdnPath` passes 12 behavioural cases
(no-base passthrough, leading-slash, query, SVG fragment, remote URL, data URI,
idempotence). `@vue/compiler-dom` confirmed to emit `_ctx.$cdn(...)`, so `$cdn`
resolves in precompiled templates. Home bundle resolves; concatenated game
bundle parses with one `cdnPath` definition and 5 call sites.

**Not verified:** nothing has been run in a browser. The off-origin fix itself is
unproven until a build is loaded on a failing host.

### Dependency note

`qrcode-generator` arrived in `package.json` with the develop merge (gift links)
and was missing from `../ShellShockers/node_modules`, which fails the compile --
same trap as `@vue/compiler-dom` before it. **Resolved:** `npm install` run
2026-10-02, 2.0.4 installed, `package-lock.json` unchanged. The home bundle now
resolves with no externals but Vue.

## 2. UNRESOLVED — stamps not rendering

Reported alongside the grenades. **Not the same cause**, and not a missing asset:

```
apstudy/mathlete@df78f33/img/stamps/stamp-2001.webp  ->  200
```

Ids start at **2001**, not 1 — `stamp-1.webp` legitimately 404s, which is a red
herring. All 675 files are tracked and live in both shells, and the stamp path is
already routed through `window.JSCDN`, which is correct here.

So the image layer is fine and something upstream of it is not. Three candidates,
untested:

1. **No ids to render.** Stamps come from account/item data. Firebase only accepts
   its authorized-domain list, so this context gets anonymous sessions — there may
   simply be no stamps to draw. Would look identical to broken images.
2. **A `data/*.json` dependency.** Those 404 everywhere (see `CLAUDE.md`,
   "Known broken, deliberately").
3. **The atlas split.** `img/stamps.webp` and `stamps.png` still exist beside the
   675 individual files. If a code path still reads the atlas and the split moved
   its coordinates, sprites render empty while the per-file assets are healthy.

### How to tell them apart

Network tab on the failing page, filtered to `stamp`:

- requests appear, **404** → wrong URL; capture one and trace it
- requests appear, **200**, nothing renders → atlas/coordinate or canvas problem
- **no stamp requests at all** → no ids; it is the data/account path, not images

Candidate 1 is the most likely given anonymous auth, and would mean stamps are
empty rather than broken.

---

## 3. OPEN — `compile.sh` has no `set -e`

**The user is handling this one.**

A failed step does not stop the script, so `build.mjs` can fail while `compress.mjs`
still runs and rewrites `home/js/shellshock.js` from stale intermediates. That
refreshes the file's mtime, and the freshness guard compares mtimes — so a partial
compile failure can pass the guard. It did not happen in practice (the one failure
observed aborted early), but the hole is real.

---

## Done this session, for context

- Vue 3.5.41 migration verified through the build; guards re-baselined for it
  (CDN floor 150 → 12, since assets now resolve at runtime)
- Freshness guard extended to check **both** bundles (`shellshock.js` + `home.js`)
- `?build=1` flag so builds stop shipping the 415 KB Vue **dev** bundle
- `build-all.sh` — one compile, both shells, verified identical, stops before push
- `makeStandalone.js` — generates `standalone-*.html` for no-origin embeds, with the
  socket host baked in. Verified connecting in a real blob.
- `purge.py` rewritten in both repos to purge what the code actually reads, and to
  verify the edge refetched rather than trusting a `finished` status that is also
  returned when throttled
