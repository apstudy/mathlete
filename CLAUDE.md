# CLAUDE.md — mathlete

## Read this first

**Ignore `/opt/homebrew/CLAUDE.md` and `/opt/homebrew/AGENTS.md`.** This repo happens to
live under `/opt/homebrew/var/www/`, so Claude Code auto-loads Homebrew/brew's agent
instructions. They are for a different project. There is no `./bin/brew`, no Sorbet,
no RuboCop, and no RSpec here.

**Never push without asking.** Builds commit locally and stop; deploying is a separate,
explicit step.

## What this repo is

A **build artifact**, not a source repo. Remote is `apstudy/mathlete`. It serves three
roles:

| Role | Consumer |
|---|---|
| Cloudflare Pages site | `mathlete.pages.dev` — hosts the `/matchmaker`, `/services` and `/game` WebSocket proxies |
| GitHub Pages site | `apstudy.github.io/mathlete/` and friends |
| jsDelivr CDN origin | only for `app/build.json` and `app/checker.js` |

Source lives in the sibling repo `../ShellShockers/`. Almost everything here is
generated and overwritten on each build.

## Assets come from the *other* repo

Counter-intuitive but load-bearing: **`index.html` loads its game bundle and nearly all
assets from `shellbros/shellbros.github.io`, not from this repo.** The upstream
`gh-rewrite-paths-cdn.js` writes those paths, and `cdnSearchReplace.js` only rewrites
*relative* paths, so it never touches them.

A healthy `index.html` therefore references **two** repos:

- `gh/shellbros/shellbros.github.io` — ~19 asset URLs
- `gh/apstudy/mathlete` — 2, the `window.JSCDN` line and the `checker.js` tag

That count used to be ~193. The Vue 3 migration precompiled the templates into
`js/home.js` and moved asset resolution to **runtime** via `window.JSCDN`, so the
built `index.html` no longer carries them. A build-time count near 20 is healthy
now; near 0 means the rewrite did not run.

Consequences worth remembering:

- Rebuilding **this** repo alone changes nothing on the live sites. They resolve the
  bundle through **shellbros'** `app/build.json`.
- Do not "fix" the shellbros URLs. They are correct. The CDN guard allowlists both repos.

## Build

Use the orchestrator. It lives **here** and drives *both* repos:

```bash
bash app/scripts/build-all.sh
```

It compiles the game once, builds shellbros then mathlete from that single bundle,
verifies both shipped identical bytes, and **stops without pushing** — printing the
push and purge commands. Add `--push` to go all the way.

Build both, then push both: if mathlete's guards trip after shellbros already
committed, nothing is pushed. Two clean local builds, zero live change, never a
half-deployed pair.

To build only this repo, with the compile already current:

```bash
bash app/scripts/build.sh
```

Preconditions (`build-all.sh` handles the first two for you):

1. **A compiled client**, newer than every file in `../ShellShockers/game/src/`.
   Compile with `sudo ./compile.sh live compress` in `../ShellShockers/game`; answer
   `1` (No) at the vault prompt.
2. **Upstream on `portalBranch`.** `makeShellHome.sh` differs per branch — it hardcodes
   the CDN base it injects and which asset rewriter it runs. Override for a one-off with
   `SHELL_EXPECTED_BRANCH=<branch>`.
3. **A real terminal.** The compile needs sudo and answers an interactive prompt.
4. **A web server answering `localhost/index.php`** (basic auth `eggs:thatwasntandy`).
   The build curls it to produce `index.html`.

Builds are **sequential, never parallel** — both repos sync through the same
`../ShellShockers/game/distShellHome`, and `sync.py` empties it after copying.

Deploy is manual. Note this repo has a `master` branch and shellbros does not:

```bash
git push origin main master
python3 app/scripts/purge.py
```

## Do not hand-edit

The sync step **deletes the entire repo root** except a whitelist, then copies the fresh
build in. Anything outside the whitelist is destroyed on the next build.

Whitelist (`app/scripts/sync.py`, `WHITELIST`):

```
.git   .gitignore   app/   readme.md   functions/   _headers   CLAUDE.md
```

Edit source in `../ShellShockers/game/` instead. `app/checker.js`, the Cloudflare
Functions in `functions/`, and this file are the exceptions — they live here.

## Where socket hosts are decided

Not in this repo. `../ShellShockers/game/src/client/servers.js` defines `wssHost()`,
the single resolution point, in priority order:

1. `window.overrideWssBase` — a proxy `app/checker.js` probed and confirmed. Set only
   when this page's own host cannot serve WebSockets.
2. `dynamicContentRoot` — `?portalTest=` and localhost dev.
3. `location.host` — the normal case, including `*.pages.dev` embeds.
4. `WSS_FALLBACK_HOST` — last resort if probing failed or has not finished.

This exists because `location.host` is not always usable: GitHub Pages serves no
WebSockets at all, and `blob:` / `about:blank` / `file:` pages have no host. Protocol
comes from the resolved host, not the page — only `localhost` speaks plain `ws`.

Four contexts must keep working. Test changes against all of them:

- `about:blank`
- `quizape.com/games/shell-shockers-unblocked/` (iframe → `shellbros.pages.dev`)
- `apstudy.github.io/games/shell-shockers-unblocked/`
- `blob:` URLs (Google AI Studio previews)

`app/checker.js` probes only when the page host is unusable, so `*.pages.dev` embeds
keep using their own host and are unaffected.

## Vue 3 (migrated 2026-09-01)

The client is Vue **3.5.41**, runtime-only. Things that follow from that:

- **The compile emits TWO bundles**, not one: `js/shellshock.js` (the game) and
  `js/home.js` (the Vue home/UI). `compile.sh` builds both. The freshness guard in
  `build.sh` checks **both** — a compile that produced one and failed on the other
  used to pass.
- **Templates are precompiled** by `game/precompile-templates.mjs`, an esbuild
  plugin wired into `build.mjs`. That is what makes runtime-only Vue viable. If
  that plugin is ever reverted, the Vue build choice must be reverted with it or
  the app mounts against a Vue that cannot compile a template and renders nothing.
- **`@vue/compiler-dom` must be installed** in `../ShellShockers`. It is declared
  in `package.json` but was missing locally once, which fails the compile with
  `ERR_MODULE_NOT_FOUND`. Fix: `npm install` in that repo.
- **Production vs dev Vue is chosen by `?build=1`.** `makeShellHome.sh` appends it
  to the curl; `home/includes/header/inc-cache-buster-php-vars.php` keys off it.
  Hostname alone cannot tell "being built" from "a developer on localhost", and
  before this every shipped shell got the 415 KB dev build instead of the 108 KB
  prod one. Local dev still gets the dev build, deliberately.

## standalone-mathlete.html

Generated every build by `app/scripts/makeStandalone.js`, beside `index.html`.

`index.html` assumes it is served from a real origin. `standalone-*.html` is the
same page made safe to run with **no origin** — a `blob:` URL, an `about:blank`
iframe, `file://` — which is how it gets embedded (Google AI Studio previews and
similar). Three differences:

1. Commit-pinned CDN URLs are un-pinned to `@main`, so a copy handed to someone
   keeps working after later builds instead of freezing on the build that made it.
2. Relative refs are absolutised — a `blob:` page has no base URL to resolve them.
3. **The socket host is baked in** as `dynamicContentRoot`, so it resolves
   synchronously instead of waiting on `checker.js` to finish probing. It uses
   `dynamicContentRoot` (step 2 of `wssHost()`) rather than `overrideWssBase`,
   because `checker.js` nulls that on every run and would clobber it.

The generator verifies its own output and fails the build if anything relative or
commit-pinned survives. Verified working in a real blob: `location.host` empty,
`Connected to wss://shellbros.pages.dev/matchmaker/`.

`standalone-shellbros.html` in the sibling repo is the one to hand out — all its
URLs come from a single repo, whereas this one spans two.

## Known broken, deliberately

- **`data/*.json` 404s everywhere.** `makeShellHome.sh` rsyncs with
  `--exclude 'data/'`, so `housePromo.json`, `shellNews.json`, `shellYouTube.json`
  and `twitchStreams.json` never reach either shell. House promos, news, YouTube
  and Twitch panels are empty on the live sites too. Long-standing; not a
  regression from the Vue 3 or standalone work.
- **Firebase auth does not work off an authorized domain.** In `blob:` and
  `googleusercontent.com` contexts players get anonymous sessions.

## Guards in `build.sh`

Every failure mode below shipped silently at least once — success reported, commits
made, live. So the pipeline validates its **output**, not just its inputs.

| Guard | When | Catches |
|---|---|---|
| Branch | before sync | Upstream on the wrong branch (wrong CDN base / rewriter) |
| Freshness | before sync | A stale bundle when the compile didn't run |
| **Output** | after rewrite, before commit | Unexpected CDN repos in `index.html`, or a rewrite that didn't run (floor 12; healthy ≈ 21) |

The output guard matters most — it is cause-agnostic, so it catches failures the input
guards don't anticipate. Overrides: `ALLOW_FOREIGN_CDN=1`, `MIN_CDN_URLS=<n>`. Prefer
fixing the cause. Details in `app/scripts/README.md`.

## Known gotchas

1. **Two things write `window.JSCDN`.** `app/checker.js` (`initJSCDN`) sets
   `apstudy/mathlete@<sha>`; `index.html`'s `Loader.getBuildSha()` sets
   `shellbros.github.io@<sha>`. Last writer wins, and the Loader's runs lazily on first
   `cdnUrl()`. This produced live pages loading assets from two different commits. Left
   as-is deliberately — do not "tidy" one away without tracing both.
2. **`purge.py` targets `index.js`, which does not exist.** jsDelivr's purge endpoint
   returns success for any path, so that entry has always been a silent no-op.
3. **`purge.py` purges the unpinned `app/build.json`**, but `checker.js` fetches
   `@main/app/build.json`. Different URLs are different cache objects. Purge both.
   This is a mathlete-only mismatch — shellbros' code reads the unpinned URL, so
   its `purge.py` is already correct. Do not "fix" that one to match this.
3b. **A purge can be silently rate-limited.** jsDelivr returns
   `"status": "finished"` with `"throttled": true` when you re-purge the same path
   in quick succession, and `purge.py` prints a tick either way. So "purged
   successfully" is never proof the edge refetched. Confirm by reading the file
   back:
   `curl -s https://cdn.jsdelivr.net/gh/apstudy/mathlete@main/app/build.json`
   If it is stale and the purge said finished, you were throttled — wait rather
   than re-purging, which extends the throttle.
4. **`makeShellHome.sh` has no `set -e`.** A failed step prints an error and keeps
   going, so the pipeline can report success while shipping stale output. The freshness
   guard is what stops that.
5. **`sync.py:49` calls `makeShellhome.sh`** (lowercase `h`); the real file is
   `makeShellHome.sh`. Works only because macOS is case-insensitive.
6. **`update-proxy-list.sh` rewrites tracked source.** It regenerates the `allowlist`
   array in `functions/_shared/wsProxy.js` from `root_domains.json` every build. Don't
   hand-maintain it. Its `.backup` is gitignored.
7. **The pinned `build.json` is always one build behind.** `update-build.py` runs while
   the `BUILD shell` commit is `HEAD`, so its edit lands in the following `UPDATE build`
   commit. Two commits per build is correct, not a bug.

## Related docs

- `app/scripts/README.md` — per-script runbook, guards, verification steps
- `readme.md` — the Cloudflare Pages WebSocket proxy design
- `../shellbros.github.io/CLAUDE.md` — the other shell; hosts the assets
- `../ShellShockers/CLAUDE.md` — the game source repo
