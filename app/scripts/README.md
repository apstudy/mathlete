# Build Scripts

## Quick Start

Run the full build pipeline:

```
bash build.sh
```

This runs all steps below automatically, including git commits. Afterwards, push and purge:

```
git push origin main
python3 purge.py
```

## Manual Workflow

```
1. python sync.py
2. bash makeShell.sh $(git rev-parse --short HEAD)
3. git add -A && git commit -m "BUILD shell YYYY-MM-DD"
4. python update-build.py
5. git add -A && git commit -m "UPDATE build YYYY-MM-DD"
```

## Scripts

### `build.sh`
Runs the full build pipeline (steps 1-5 above) in one command. Prints push + purge reminders when done.

### `sync.py`
Syncs game files from `ShellShockers/game/distShellHome/` into the repo. Runs the upstream `makeShellhome.sh` build first, then cleans and copies files over.

Supports `--dry-run` and `--url <url>`.

### `makeShell.sh <short-hash>`
Prepares `index.html` for CDN delivery:
- Injects `window.JSCDN` and `checker.js` script tags
- Strips unwanted meta tags, `<title>`, and `<script type="application/ld+json">`
- Rewrites asset paths to use jsDelivr CDN via `cdnSearchReplace.js`

Run from the `app/scripts/` directory.

### `update-build.py`
Updates the commit hash after committing:
- Replaces the old hash with the new hash in all CDN URLs in `index.html`
- Updates `build.json` with the new hash and increments the build number

Supports `--dry-run` to preview changes.

### `cdnSearchReplace.js`
Called by `makeShell.sh`. Rewrites relative asset paths (js, css, images, etc.) to CDN URLs in `index.html`.

### `purge.py`
Purges jsDelivr cache for `build.json`, `checker.js`, and `index.js`. Run **after** pushing to GitHub.
