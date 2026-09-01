#!/bin/bash

# ============================================
# Build Script
# Runs the complete build pipeline:
# 1. Syncs files from distShellHome
# 2. Updates WebSocket proxy allowlist
# 3. Transforms index.html for CDN delivery
# 4. Commits as "BUILD shell YYYY-MM-DD"
# 5. Updates build hash in CDN URLs
# 6. Commits as "UPDATE build YYYY-MM-DD"
# ============================================

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SYNC_SCRIPT="$SCRIPT_DIR/sync.py"
ALLOWLIST_SCRIPT="$SCRIPT_DIR/update-proxy-list.sh"
MAKESHELL_SCRIPT="$SCRIPT_DIR/makeShell.sh"
UPDATE_BUILD_SCRIPT="$SCRIPT_DIR/update-build.py"

# ISO date for commit messages
BUILD_DATE="$(date +%Y-%m-%d)"

echo -e "${CYAN}╔════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║         ShellShockers Build            ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"
echo ""

# ============================================
# Validation
# ============================================
echo -e "${YELLOW}Validating scripts...${NC}"

for script in "$SYNC_SCRIPT" "$ALLOWLIST_SCRIPT" "$MAKESHELL_SCRIPT" "$UPDATE_BUILD_SCRIPT"; do
    if [ ! -f "$script" ]; then
        echo -e "${RED}Error: $(basename "$script") not found at $script${NC}"
        exit 1
    fi
done

for cmd in python3 node git; do
    if ! command -v "$cmd" &> /dev/null; then
        echo -e "${RED}Error: $cmd is not installed${NC}"
        exit 1
    fi
done

echo -e "${GREEN}All scripts found${NC}"
echo -e "${GREEN}Dependencies available${NC}"
echo ""

# ============================================
# Validate upstream branch
#
# The ShellShockers branch determines which CDN base makeShellHome.sh injects
# and which asset rewriter it runs. Building from the wrong branch produces an
# index.html pointing at another repo's CDN paths, which the rest of this
# pipeline cannot detect or correct.
# ============================================
echo -e "${YELLOW}Validating upstream branch...${NC}"

GAME_REPO="$(cd "$REPO_ROOT/../ShellShockers" 2>/dev/null && pwd)"
EXPECTED_BRANCH="${SHELL_EXPECTED_BRANCH:-portalBranch}"

if [ -z "$GAME_REPO" ]; then
    echo -e "${RED}Error: ShellShockers repo not found beside $REPO_ROOT${NC}"
    exit 1
fi

CURRENT_BRANCH="$(git -C "$GAME_REPO" branch --show-current)"

if [ "$CURRENT_BRANCH" != "$EXPECTED_BRANCH" ]; then
    echo -e "${RED}Error: ShellShockers is on '$CURRENT_BRANCH', expected '$EXPECTED_BRANCH'${NC}"
    echo ""
    echo -e "${YELLOW}Switch branch:${NC}"
    echo -e "   ${GREEN}git -C $GAME_REPO switch $EXPECTED_BRANCH${NC}"
    echo ""
    echo -e "${YELLOW}Or build from the current branch on purpose:${NC}"
    echo -e "   ${GREEN}SHELL_EXPECTED_BRANCH=$CURRENT_BRANCH bash app/scripts/build.sh${NC}"
    exit 1
fi

echo -e "${GREEN}ShellShockers on $CURRENT_BRANCH${NC}"
echo ""

# ============================================
# Verify the compile already ran
#
# The compile is a prerequisite, not part of this build, and makeShellHome.sh has
# no `set -e` -- a skipped or failed compile leaves the previous bundle in place
# and the pipeline still reports success. Compare the bundle against the sources
# it is built from rather than trusting an exit code. Runs before sync so it
# fails without having wiped the repo.
# ============================================
echo -e "${YELLOW}Verifying compiled bundle is current...${NC}"

GAME_SRC="$GAME_REPO/game/src"

# compile.sh emits two bundles: shellshock.js (the game) and home.js (the Vue 3
# home/UI). Checking only one would pass a compile that produced that bundle and
# failed on the other.
GAME_BUNDLES="$GAME_REPO/game/home/js/shellshock.js $GAME_REPO/game/home/js/home.js"

for GAME_BUNDLE in $GAME_BUNDLES; do
    if [ ! -f "$GAME_BUNDLE" ]; then
        echo -e "${RED}Error: compiled bundle not found at $GAME_BUNDLE${NC}"
        echo ""
        echo -e "${YELLOW}Recompile, then rebuild:${NC}"
        echo -e "   ${GREEN}cd $GAME_REPO/game${NC}"
        echo -e "   ${GREEN}sudo ./compile.sh live compress${NC}"
        exit 1
    fi

    STALE_SRC="$(find "$GAME_SRC" -type f -newer "$GAME_BUNDLE" | head -1)"

    if [ -n "$STALE_SRC" ]; then
        echo -e "${RED}Error: $(basename "$GAME_BUNDLE") is older than the game source${NC}"
        echo -e "${RED}The build would ship stale client code.${NC}"
        echo ""
        echo -e "${YELLOW}Newer than the bundle:${NC}"
        echo -e "   $STALE_SRC"
        echo ""
        echo -e "${YELLOW}Recompile, then rebuild:${NC}"
        echo -e "   ${GREEN}cd $GAME_REPO/game${NC}"
        echo -e "   ${GREEN}sudo ./compile.sh live compress${NC}"
        exit 1
    fi
done

echo -e "${GREEN}Both bundles are newer than all sources${NC}"
echo ""

# ============================================
# Step 1: Sync Files
# ============================================
echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Step 1: Syncing Files                ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

python3 "$SYNC_SCRIPT"
echo ""

# ============================================
# Step 2: Update Proxy Allowlist
# ============================================
echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Step 2: Updating Proxy Allowlist     ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

cd "$SCRIPT_DIR"
bash "$ALLOWLIST_SCRIPT"
cd "$REPO_ROOT"
echo ""

# ============================================
# Step 3: Transform index.html for CDN
# ============================================
echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Step 3: Transforming index.html      ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

SHORT_HASH="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
cd "$SCRIPT_DIR"
bash "$MAKESHELL_SCRIPT" "$SHORT_HASH"
cd "$REPO_ROOT"
echo ""

# ============================================
# Verify the rewritten CDN paths
#
# makeShell.sh only seds the JSCDN line and the checker.js tag, and
# cdnSearchReplace.js only rewrites *relative* paths. Absolute URLs injected by
# the upstream makeShellHome.sh therefore survive untouched, producing a build
# that completes cleanly while loading its assets from another repo. Validate the
# output here, before anything is committed.
# ============================================
echo -e "${YELLOW}Verifying CDN paths in index.html...${NC}"

# A finished index.html legitimately references TWO repos:
#   - shellbros: the asset paths, written by gh-rewrite-paths-cdn.js upstream.
#     Both live sites resolve the bundle through shellbros' build.json.
#   - apstudy/mathlete: the window.JSCDN line and the checker.js tag, which
#     makeShell.sh pins to this repo's own commit.
# Anything else means the rewrite pointed somewhere unintended.
ALLOWED_CDN_REPOS="gh/shellbros/shellbros.github.io gh/apstudy/mathlete"
# Re-baselined for the Vue 3 migration. Templates are precompiled into
# js/home.js and assets now resolve at RUNTIME via window.JSCDN, so the built
# index.html no longer carries ~193 rewritten URLs -- it carries ~17-19. A
# correct build measured 17 from gh-rewrite-paths-cdn.js plus the 2 makeShell.sh
# injects. The floor still catches the case it was written for: a rewrite that
# did not run at all lands at 0.
MIN_CDN_URLS="${MIN_CDN_URLS:-12}"

ALL_CDN_REPOS="$(grep -oE 'cdn\.jsdelivr\.net/gh/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+' "$REPO_ROOT/index.html" \
                 | sed 's|cdn\.jsdelivr\.net/||' | sort -u)"

FOREIGN_CDN=""
for repo in $ALL_CDN_REPOS; do
    case " $ALLOWED_CDN_REPOS " in
        *" $repo "*) ;;
        *) FOREIGN_CDN="$FOREIGN_CDN $repo" ;;
    esac
done
FOREIGN_CDN="$(echo $FOREIGN_CDN)"

# Total jsDelivr references, not per-repo: the asset paths are unpinned, so
# counting "repo@" occurrences would read near zero on a perfectly good build.
CDN_COUNT="$(grep -oE 'cdn\.jsdelivr\.net/gh/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+' "$REPO_ROOT/index.html" | wc -l | tr -d ' ')"

if [ -n "$ALLOW_FOREIGN_CDN" ]; then
    echo -e "${YELLOW}ALLOW_FOREIGN_CDN set -- skipping CDN validation${NC}"
    if [ -n "$FOREIGN_CDN" ]; then
        echo -e "${YELLOW}Allowed foreign CDN repos:${NC}"
        printf "   %s\n" $FOREIGN_CDN
    fi
else
    if [ -n "$FOREIGN_CDN" ]; then
        echo -e "${RED}Error: index.html references unexpected CDN repos:${NC}"
        printf "   ${RED}%s${NC}\n" $FOREIGN_CDN
        echo ""
        echo -e "${YELLOW}These are injected by makeShellHome.sh on branch '$CURRENT_BRANCH'${NC}"
        echo -e "${YELLOW}and cannot be corrected downstream. Assets will 404 unless that${NC}"
        echo -e "${YELLOW}repo mirrors them.${NC}"
        echo ""
        echo -e "${YELLOW}Build anyway:${NC}"
        echo -e "   ${GREEN}ALLOW_FOREIGN_CDN=1 bash app/scripts/build.sh${NC}"
        exit 1
    fi

    if [ "$CDN_COUNT" -lt "$MIN_CDN_URLS" ]; then
        echo -e "${RED}Error: only $CDN_COUNT CDN URLs in index.html${NC}"
        echo -e "${RED}Expected at least $MIN_CDN_URLS -- the asset rewrite did not run.${NC}"
        echo ""
        echo -e "${YELLOW}Override the floor if this is expected:${NC}"
        echo -e "   ${GREEN}MIN_CDN_URLS=$CDN_COUNT bash app/scripts/build.sh${NC}"
        exit 1
    fi

    echo -e "${GREEN}$CDN_COUNT CDN URLs, all from expected repos${NC}"
fi
echo ""

# ============================================
# Generate standalone.html
#
# index.html assumes it is served from this repo's own origin. standalone.html
# is the same page made safe to run with no origin at all (blob:, about:blank,
# file:), where relative paths cannot resolve and commit-pinned URLs freeze on
# the build that produced them. Runs after the CDN guard so it only ever derives
# from an index.html that already passed validation, and it verifies its own
# output -- a failure here stops the build.
# ============================================
echo -e "${YELLOW}Generating standalone.html...${NC}"
node "$SCRIPT_DIR/makeStandalone.js"
echo ""

# ============================================
# Step 4: Commit "BUILD shell"
# ============================================
echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Step 4: Committing BUILD shell       ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

cd "$REPO_ROOT"
git add -A
if git diff --cached --quiet; then
    echo -e "${YELLOW}No changes to commit, skipping BUILD commit${NC}"
else
    git commit -m "BUILD shell $BUILD_DATE"
fi
echo ""

# ============================================
# Step 5: Update build hash
# ============================================
echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Step 5: Updating build hash          ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

python3 "$UPDATE_BUILD_SCRIPT"
echo ""

# ============================================
# Step 6: Commit "UPDATE build"
# ============================================
echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Step 6: Committing UPDATE build      ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

cd "$REPO_ROOT"
git add -A
if git diff --cached --quiet; then
    echo -e "${YELLOW}No changes to commit, skipping UPDATE commit${NC}"
else
    git commit -m "UPDATE build $BUILD_DATE"
fi
echo ""

# ============================================
# Step 7: Sync master branch
# ============================================
echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Step 7: Syncing master to main       ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

git branch -f master main
echo -e "${GREEN}master branch updated to match main${NC}"
echo ""

# ============================================
# Build Complete
# ============================================
echo -e "${CYAN}╔════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║         Build Complete!                ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo -e "   ${BLUE}1.${NC} Push to deploy:"
echo -e "      ${GREEN}git push origin main master${NC}"
echo ""
echo -e "   ${BLUE}2.${NC} Purge jsDelivr cache:"
echo -e "      ${GREEN}python3 app/scripts/purge.py${NC}"