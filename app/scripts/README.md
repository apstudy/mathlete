# Build Scripts

## What this repo is

`mathlete` is the **published shell** for the ShellShockers game — a static site
deployed on Cloudflare Pages, with `index.html` rewritten so every asset loads
from jsDelivr instead of this repo.

The game itself is **not** built here. It is built in the sibling repo
`../../../ShellShockers/game/` and copied in.

```
/opt/homebrew/var/www/shellshock/
├── ShellShockers/game/          ← game source; builds into distShellHome/
│   ├── compile.sh               ← compiles the game (needs sudo)
│   ├── makeShellhome.sh         ← runs compile.sh, then stages distShellHome/
│   └── distShellHome/           ← handoff folder (emptied after each sync)
└── mathlete/                    ← THIS repo (the published shell)
    └── app/scripts/             ← the build pipeline you are reading about
```

Deploy target: `git@github.com:apstudy/mathlete.git`
CDN: `https://cdn.jsdelivr.net/gh/apstudy/mathlete@<short-hash>/`

## Quick Start

```bash
bash app/scripts/build.sh          # run from the repo root
git push origin main master        # separate + deliberate; build.sh never pushes
python3 app/scripts/purge.py       # only AFTER the push
```

## Before you run it

`build.sh` will not work unattended. Check these first.

| Requirement | Why |
|---|---|
| **Interactive terminal** | Two prompts, see below |
| **sudo password** | `makeShellhome.sh` starts with `sudo ./compile.sh live compress` |
| Local web server on `localhost` serving `index.php` | `makeShellhome.sh` curls it to produce `index.html` |
| Sibling `ShellShockers/game/` repo present | Source of everything synced in |
| `python3`, `node`, `git` | Used throughout; `build.sh` validates these |
| Clean working tree | `build.sh` runs `git add -A` and commits everything present |

### Pre-flight check

Run from the repo root.

```bash
cd /opt/homebrew/var/www/shellshock/mathlete
```

Working tree must be clean — anything sitting here gets swept into the build commit.

```bash
git status --short
```

The web server must answer. `makeShellhome.sh` will not fail loudly if it can't
reach this.

```bash
curl -s -u eggs:thatwasntandy \
  -o /dev/null \
  -w "localhost: %{http_code}\n" \
  localhost/index.php
```

The sibling repo must be there.

```bash
ls ../ShellShockers/game/makeShellhome.sh
```

Want: no output from `git status`, `localhost: 200`, and the `ls` finding the file.

### Two interactive prompts

1. **sudo password** — from `sudo ./compile.sh live compress`.
2. **"Do items need to be vaulted?"** — `compile.sh` asks this whenever config is
   `live`. Answer `1` (No) to continue; `2` (Yes) exits the compile.

This is why an agent or CI job cannot run `build.sh` end to end. Run it yourself,
or run it under a terminal that can answer both prompts.

### ⚠️ Silent-stale-build trap

`makeShellhome.sh` has **no `set -e`**. If the `sudo` step fails, it prints an
error, keeps going, and rsyncs the *previous* `home/` output into
`distShellHome/`. `sync.py` sees exit code 0 and carries on. You get a build that
looks successful but ships stale code.

Always confirm the compile really ran before trusting a build — see
[Verifying a build](#verifying-a-build).

## What `build.sh` does

| Step | Action | Notes |
|---|---|---|
| 1 | `sync.py` | Runs upstream `makeShellhome.sh`, wipes this repo (except the whitelist), copies `distShellHome/` in, then empties `distShellHome/` |
| 2 | `update-proxy-list.sh` | Rewrites the `allowlist` array in `functions/_shared/wsProxy.js` from `root_domains.json` |
| 3 | `makeShell.sh <short-hash>` | Rewrites `index.html` for CDN delivery |
| 4 | `git commit -m "BUILD shell YYYY-MM-DD"` | Skipped if nothing changed |
| 5 | `update-build.py` | Points CDN URLs and `build.json` at the commit from step 4 |
| 6 | `git commit -m "UPDATE build YYYY-MM-DD"` | Skipped if nothing changed |
| 7 | `git branch -f master main` | jsDelivr also serves `@master`; keeps it in step |

**Two commits per build is expected.** Step 3 cannot know the hash of the commit
it is part of, so step 5 goes back and fixes the URLs afterwards. `build.json`'s
`build_version` therefore always names the *previous* commit (the `BUILD shell`
one), not `HEAD`.

Order matters: step 1 delivers `root_domains.json`, which step 2 consumes.

### What survives the sync

`sync.py` deletes everything in the repo root except this whitelist:

```
.git  .gitignore  app  readme.md  functions  _headers
```

Anything else you add at the repo root **will be deleted** on the next build.
Put it in `app/` or `functions/`, or add it to `WHITELIST` in `sync.py`.

## Verifying a build

Nothing in the pipeline fails loudly on a stale compile, so check by hand:

**1. Did the game actually recompile?** The bundle should be minutes old.

```bash
ls -la ../ShellShockers/game/home/js/shellshock.js
```

Nothing in the game source should be newer than that bundle. If this lists any
file, the compile did **not** pick up your latest changes — suspect the `sudo`
step.

```bash
cd ../ShellShockers/game
```

```bash
find src -type f -newer home/js/shellshock.js
```

```bash
cd ../../mathlete
```

**2. Did this repo get two fresh commits?** Both dated today.

```bash
git log -2 --format='%h %ad %s' --date=iso
```

**3. Do `build.json` and `index.html` agree?** Both must name the **`BUILD shell`
commit** — the older of the two, *not* `HEAD`. `update-build.py` runs while that
commit is `HEAD`, and the `UPDATE build` commit is created afterwards. That is
also the commit holding the assets jsDelivr will serve, so it is the correct
target.

`build_version` should be the `BUILD shell` hash, and `build_number` should have
gone up by one.

```bash
cat app/build.json
```

The CDN hash should be a single value — the same `BUILD shell` hash.

```bash
grep -o 'apstudy/mathlete@[a-f0-9]*' index.html | sort -u
```

**4. Is `master` level with `main`?** Both hashes should match, and nothing
should be unpushed yet.

```bash
git rev-parse main master
```

```bash
git log origin/main..main --oneline
```

## After a successful build

```bash
git push origin main master
python3 app/scripts/purge.py
```

Both branches must go up — jsDelivr resolves `@master` as well as the pinned
hash. Purge **after** pushing, or jsDelivr re-caches the old files.

## Manual workflow

Equivalent to `build.sh`, if you need to run a step at a time. Steps 2–3 must run
from `app/scripts/` — they use relative paths.

```bash
python3 app/scripts/sync.py

cd app/scripts
bash update-proxy-list.sh
bash makeShell.sh "$(git rev-parse --short HEAD)"
cd ../..

git add -A
git commit -m "BUILD shell $(date +%F)"

python3 app/scripts/update-build.py

git add -A
git commit -m "UPDATE build $(date +%F)"

git branch -f master main
```

## Script reference

### `build.sh`
The whole pipeline (steps 1–7). Validates dependencies, `set -e`, commits but
**never pushes**. Prints push + purge reminders at the end.

### `sync.py`
Runs upstream `makeShellhome.sh`, then cleans this repo (minus the whitelist),
copies `distShellHome/` in, and empties `distShellHome/`.

Flags: `--dry-run`, `--url <url>` (default `localhost`, passed to
`makeShellhome.sh` as the host it curls `index.php` from).

An empty `distShellHome/` is normal between builds — it is a handoff folder, not
an artifact store.

### `update-proxy-list.sh`
Replaces the `allowlist` array in `functions/_shared/wsProxy.js` with
`domains` from `root_domains.json`. Backs up to `wsProxy.js.backup`
(gitignored). Run from `app/scripts/`.

### `makeShell.sh <short-hash>`
Prepares `index.html` for CDN delivery:
- Injects `window.JSCDN` + the `app/checker.js` tag, or updates the hash if already there
- Strips `<title>`, `<script type="application/ld+json">`, and all `<meta>` tags
  except charset, viewport, facebook-domain-verification, theme-color, background-color
- Patches `Loader` to read `sha` *or* `build_version` from `build.json`
- Calls `cdnSearchReplace.js` to rewrite asset paths

Run from `app/scripts/`. Uses BSD `sed -i ''` — macOS only.

### `update-build.py`
Run **after** the `BUILD shell` commit. Rewrites every
`apstudy/mathlete@<hash>/` URL in `index.html` to the current short hash, sets
`build.json`'s `build_version`, and increments `build_number`. Idempotent.

Flag: `--dry-run`.

### `cdnSearchReplace.js`
Called by `makeShell.sh`. Rewrites relative asset paths (js, css, json, images,
audio, video, fonts, models) in `index.html` to CDN URLs. Zero dependencies.

### `purge.py`
Purges the jsDelivr cache for `app/build.json`, `app/checker.js`, and
`index.js`. Run **after** pushing. Exits non-zero if any purge fails.

## Related pipeline

`ShellShockers/game/makeCrazy.sh` builds `distCrazyGames/` — the CrazyGames
distribution. It is a **separate** target and does not touch this repo. Building
one does not build the other.
