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

## 1. OPEN BUG — bare `img/…` paths break off-origin

**Confirmed.** Reported as broken grenade icons on a third-party host.

The host serves the page from its own jsDelivr repo (`bobydob/get`, unrelated to
us), so the document's base URL is theirs. Any **relative** URL the bundle emits
resolves into that repo, which has none of our assets.

```
built:    <img src="img/ico_grenadeEmpty.webp?v=1">        (src/home/components/game/game-screen.js:182)
resolves: cdn.jsdelivr.net/gh/bobydob/get@8a695dd3…/img/…  -> 404
```

Verified the asset itself is fine — `@df78f33/img/ico_grenadeEmpty.webp` is **200**.
The path is the problem, not the file.

`makeStandalone.js` cannot fix this: it only rewrites the static HTML, and these
literals live inside compiled Vue templates and imperative JS in the bundle.

### Scope

**44 distinct bare `img/…` literals across 26 files** in `../ShellShockers/game/src/`:

```
src/home/components/{home,equip,shared,game}/*.js
src/home/root/{computed,store-methods,vue-data,template}.js
src/client/{clientGame,clientMetaGame,playerChallenges}.js
src/mapeditor/main.js
src/services/twitchStreamScraper.js
```

Re-list with:

```bash
grep -rlE "['\"\`]img/[A-Za-z0-9_./{}$-]+['\"\`]" ../ShellShockers/game/src/
```

### The fix pattern

Already proven in `src/client/playerActor.js:27` (the stamps commit, `11263e881`):

```js
let baseUrl = (typeof window !== 'undefined' && window.JSCDN) ? window.JSCDN : '';
img.src = baseUrl + 'img/ico_grenadeEmpty.webp?v=1';
```

`window.JSCDN` was **verified correct** on the failing host
(`https://cdn.jsdelivr.net/gh/apstudy/mathlete@df78f33/`), so prefixing genuinely
resolves these. That was checked before committing to this approach — if JSCDN had
been wrong or empty, prefixing would have moved 44 broken URLs to a new wrong base
and fixed nothing.

Needs a recompile and a rebuild of both shells. Touches shared game source, so it
ships to every target including CrazyGames.

---

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
