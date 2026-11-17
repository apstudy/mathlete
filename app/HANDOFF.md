# HANDOFF — 2026-11-17

Open work and live state. Standing context is in `CLAUDE.md` (this repo) and
`../shellbros.github.io/CLAUDE.md`. **Read those first** — this file only covers
what is unfinished.

## State at handoff

| Repo | Branch | Unpushed | Live |
|---|---|---|---|
| `ShellShockers` | `portalBranch` | 172 (local only) | — |
| `shellbros.github.io` | `main` | 3 | build **43** (`499c752`) |
| `mathlete` | `main` | 4 | build **53** (`cc01485`) |

Each shell's unpushed commits are the 2026-11-17 build (shellbros build 44,
mathlete build 54), a temporary branch-guard allowlist and its revert; mathlete
also has this file's updates. Built and checked, **not live** — see 1.

Local `portalBranch` now carries all of `origin/develop` (lazy skins + Turnstile)
and is **not pushed**: it exists only on this Mac.

**Never push without asking.**

---

## 1. READY, NOT LIVE — lazy skins + Turnstile build

Built 2026-11-17 from `3628ab014` (`portalBranch` + `testLazySkinsTurnstile`,
on a temporary branch). `origin/develop` was then merged into `portalBranch`
(`eb133c99c`); it added only `game/tools/turnstileFloodDev.cjs`, so `game/src`
and `game/home` are identical to what was built. Held back from going live.

Never build `develop` or a feature branch directly: they have none of the
portal code (`makeShellHome.sh`, `cdn.js`, `wssHost()`, `?build=1`). Merge them
into `portalBranch` instead. The one conflict last time was the language fetch
in `gameApp.js`: keep `window.JSCDN` and take `ClientVersion`.

### Checked and fine

- Game protocol unchanged, so the client can ship before or after the servers.
  The join start waits at most 3 s for skins (`JOIN_SKIN_WAIT_MS`).
- Lazy skins use relative `models/lazy/` URLs. Both shells ship that folder, so
  `pages.dev` and `github.io` resolve their own copy. Off-origin (blob, copies)
  the manifest 404s and the game falls back to the full load, by design.
- `?portalTest` lockdown does not affect the standalone pages: they bake
  `dynamicContentRoot` directly.
- Turnstile: the four unblock hostnames (`shellbros.pages.dev`,
  `mathlete.pages.dev`, `shellbros.github.io`, `apstudy.github.io`) were added
  to the `0x4AAAAAAFyfPJS0...` widget on 2026-11-17. Services picks the key by
  socket Origin and overrides the page's key, so no rebuild was needed.

### Before going live

- [ ] Admin, Badguys → Turnstile: last sync has no error and the widget lists
      the four hostnames.
- [ ] Rollback ready: `git revert` the two build commits in each shell, then
      push and purge. A real browser test before launch is not possible (a
      preview still reads the live `build.json`), so test right after.
- [ ] After launch, in a private window on `shellbros.pages.dev`: grenade icons
      show, skins load, and the `turnstileRequired` reply carries a `siteKey`.
      That also closes the img-path fix (`183468859`), live since build 53 but
      never verified in a browser.

### After launch: measure the Google Sites "Alt" button

Seen on `sites.google.com/view/classroom6x/shell-shockers`, which has two buttons:

| Button | Opens | Origin | Turnstile |
|---|---|---|---|
| FULLSCREEN | about:blank → iframe `apstudy.github.io/mathlete/` | `apstudy.github.io` | covered |
| FULLSCREEN (Alt) | `blob:` built from `bobydob/get@8a695dd/ss10.xml` | `<n>-atari-embeds.googleusercontent.com` | **not covered** |

`ss10.xml` is a frozen copy of `standalone-mathlete.html` that loads our `@main`
bundles but has no `TURNSTILE_SITEKEY`. In Block (or Auto during a swarm),
first-time players using Alt are refused. Existing players are unaffected.

No safe hostname fixes it: the `<n>` varies per site, `atari-embeds` does not
match it as a parent domain, and only `googleusercontent.com` would, which
lets any Google-hosted page use the key. Whether Turnstile runs inside a
`blob:` at all is also unknown. Do **not** exempt origins on the server: the
Origin header can be faked, so that would bypass the gate.

- [ ] After launch, check how much `googleusercontent.com` traffic shows in the
      no-key domain counts (`countNoKeyDomain`).
- [ ] If it is significant, add `googleusercontent.com` to a widget as a trial
      and test the Alt button in a private window. Keep it only if Turnstile
      works there.

### Other notes

- **The lazy-skins kill switch does not reach the shells.** They ship their own
  `models/lazy/manifest.json`. Set `"lazy": false` there in both shells, push and
  purge, and set `game/tools/lazySkinsSetting.json` too or the next build undoes it.
- **The shells bake Cloudflare's test key** (`1x00000000000000000000AA`), because
  the build curls `localhost`. Harmless for the four covered hosts, since services
  sends the real key. It should still be `''` or a real key.
- Standalone pages report Turnstile platform `poki` (`dynamicContentRoot` is
  set). That only skews counts.
- Frozen copies like `ss10.xml` run new `@main` bundles inside old HTML. A build
  that changes what the bundle expects from the page will break them, and we
  cannot update them.

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

## Done 2026-09-02, for context

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
