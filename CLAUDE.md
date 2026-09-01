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

- `gh/shellbros/shellbros.github.io` — ~193 asset URLs
- `gh/apstudy/mathlete` — exactly 2, the `window.JSCDN` line and the `checker.js` tag

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

## Guards in `build.sh`

Every failure mode below shipped silently at least once — success reported, commits
made, live. So the pipeline validates its **output**, not just its inputs.

| Guard | When | Catches |
|---|---|---|
| Branch | before sync | Upstream on the wrong branch (wrong CDN base / rewriter) |
| Freshness | before sync | A stale bundle when the compile didn't run |
| **Output** | after rewrite, before commit | Unexpected CDN repos in `index.html`, or a rewrite that didn't run (floor 150; healthy ≈ 195) |

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
