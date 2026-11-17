#!/bin/bash

# ============================================
# Build both shells from one compile
#
# The game compiles once, then both repos are built from that single bundle so
# they ship identical bytes. Nothing is pushed unless --push is passed: both
# builds are completed and verified first, so a failure in the second build
# never leaves the first one half-deployed.
#
# Order matters. shellbros is built first because it hosts the assets both live
# sites resolve through -- quizape.com and apstudy.github.io both read
# shellbros' build.json to decide which bundle to load.
# ============================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

MATHLETE="$ROOT/mathlete"
SHELLBROS="$ROOT/shellbros.github.io"
UPSTREAM="$ROOT/ShellShockers"
GAME="$UPSTREAM/game"

EXPECTED_BRANCH="${SHELL_EXPECTED_BRANCH:-portalBranch}"
BUILD_URL="${BUILD_URL:-localhost}"
DO_PUSH=0

for arg in "$@"; do
    case "$arg" in
        --push) DO_PUSH=1 ;;
        *) echo -e "${RED}Unknown argument: $arg${NC}"; echo "Usage: build-all.sh [--push]"; exit 1 ;;
    esac
done

banner() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    printf "${BLUE}║${NC}  %-36s ${BLUE}║${NC}\n" "$1"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""
}

echo -e "${CYAN}╔════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║       Build Both Shells                ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"

# ============================================
# Pre-flight
#
# Everything that can be checked without side effects is checked here, so a
# misconfiguration costs nothing instead of half a build.
# ============================================
banner "Pre-flight"

for d in "$MATHLETE" "$SHELLBROS" "$GAME"; do
    if [ ! -d "$d" ]; then
        echo -e "${RED}Error: not found: $d${NC}"
        exit 1
    fi
done
echo -e "${GREEN}Both repos and the game tree are present${NC}"

CURRENT_BRANCH="$(git -C "$UPSTREAM" branch --show-current)"
if [ "$CURRENT_BRANCH" != "$EXPECTED_BRANCH" ]; then
    echo -e "${RED}Error: ShellShockers is on '$CURRENT_BRANCH', expected '$EXPECTED_BRANCH'${NC}"
    echo -e "${YELLOW}Switch:${NC}   ${GREEN}git -C $UPSTREAM switch $EXPECTED_BRANCH${NC}"
    echo -e "${YELLOW}Override:${NC} ${GREEN}SHELL_EXPECTED_BRANCH=$CURRENT_BRANCH bash app/scripts/build-all.sh${NC}"
    exit 1
fi
echo -e "${GREEN}ShellShockers on $CURRENT_BRANCH${NC}"

# A dirty tree matters because each build.sh runs `git add -A`, so anything
# lying around gets swept into the build commit.
for repo in "$SHELLBROS" "$MATHLETE"; do
    if [ -n "$(git -C "$repo" status --porcelain)" ]; then
        echo -e "${YELLOW}Uncommitted changes in $(basename "$repo"):${NC}"
        git -C "$repo" status --short | sed 's/^/   /'
        echo -e "${YELLOW}These will be included in the BUILD commit.${NC}"
    fi
done

HTTP_CODE="$(curl -s -o /dev/null -w "%{http_code}" \
    -u eggs:thatwasntandy --max-time 10 "$BUILD_URL/index.php" || echo "000")"
if [ "$HTTP_CODE" != "200" ]; then
    echo -e "${RED}Error: $BUILD_URL/index.php returned $HTTP_CODE, expected 200${NC}"
    echo -e "${YELLOW}makeShellHome.sh curls this to generate index.html and will not${NC}"
    echo -e "${YELLOW}fail loudly if it cannot reach it. Start the local web server.${NC}"
    exit 1
fi
echo -e "${GREEN}$BUILD_URL/index.php returns 200${NC}"

# ============================================
# Compile once
#
# Both shells are built from this single bundle. Two separate compiles could
# drift if anything changed in between; one compile guarantees identical bytes.
# `sudo -v` primes credentials up front so there is exactly one prompt, and the
# `1` answers compile.sh's "Do items need to be vaulted?" with No.
# ============================================
banner "Compiling game (one sudo prompt)"

echo -e "${YELLOW}Priming sudo...${NC}"
sudo -v

cd "$GAME"
printf '1\n' | sudo ./compile.sh live compress
cd "$ROOT"

BUNDLE="$GAME/home/js/shellshock.js"
if [ ! -f "$BUNDLE" ]; then
    echo -e "${RED}Error: bundle missing after compile: $BUNDLE${NC}"
    exit 1
fi

STALE="$(find "$GAME/src" -type f -newer "$BUNDLE" | head -1)"
if [ -n "$STALE" ]; then
    echo -e "${RED}Error: bundle is still older than the source after compiling${NC}"
    echo -e "${YELLOW}Newer than the bundle:${NC} $STALE"
    exit 1
fi

echo ""
echo -e "${GREEN}Compile OK -- bundle is newer than every source file${NC}"

# ============================================
# Build both, sequentially
#
# Sequential is required, not stylistic: both repos sync through the same
# ShellShockers/game/distShellHome folder and sync.py empties it after copying,
# so concurrent builds would race on it.
# ============================================
banner "Building shellbros.github.io"
cd "$SHELLBROS"
bash app/scripts/build.sh

banner "Building mathlete"
cd "$MATHLETE"
bash app/scripts/build.sh

# ============================================
# Verify
# ============================================
banner "Verifying both builds"

SB_VERSION="$(python3 -c "import json;print(json.load(open('$SHELLBROS/app/build.json'))['build_version'])")"
SB_NUMBER="$(python3 -c "import json;print(json.load(open('$SHELLBROS/app/build.json'))['build_number'])")"
ML_VERSION="$(python3 -c "import json;print(json.load(open('$MATHLETE/app/build.json'))['build_version'])")"
ML_NUMBER="$(python3 -c "import json;print(json.load(open('$MATHLETE/app/build.json'))['build_number'])")"

# Both shells must carry the same bundle, since both were built from one compile.
SB_SUM="$(shasum "$SHELLBROS/js/shellshock.js" | cut -d' ' -f1)"
ML_SUM="$(shasum "$MATHLETE/js/shellshock.js" | cut -d' ' -f1)"
if [ "$SB_SUM" != "$ML_SUM" ]; then
    echo -e "${RED}Error: the two shells shipped different bundles${NC}"
    echo -e "   shellbros: $SB_SUM"
    echo -e "   mathlete:  $ML_SUM"
    exit 1
fi

echo -e "${GREEN}shellbros:${NC} $SB_VERSION (build $SB_NUMBER)"
echo -e "${GREEN}mathlete: ${NC} $ML_VERSION (build $ML_NUMBER)"
echo -e "${GREEN}Both shells carry the same bundle${NC} ${SB_SUM:0:12}"

# ============================================
# Push + purge
# ============================================
if [ "$DO_PUSH" -eq 0 ]; then
    banner "Built -- nothing pushed"
    echo -e "${YELLOW}Both builds are committed locally and verified. Nothing is live yet.${NC}"
    echo ""
    echo -e "${YELLOW}1. Push shellbros (no master branch in that repo):${NC}"
    echo -e "   ${GREEN}git -C $SHELLBROS push origin main${NC}"
    echo ""
    echo -e "${YELLOW}2. Push mathlete (jsDelivr also serves @master):${NC}"
    echo -e "   ${GREEN}git -C $MATHLETE push origin main master${NC}"
    echo ""
    echo -e "${YELLOW}3. Purge, then verify:${NC}"
    echo -e "   ${GREEN}cd $SHELLBROS && python3 app/scripts/purge.py${NC}"
    echo -e "   ${GREEN}cd $MATHLETE && python3 app/scripts/purge.py${NC}"
    echo ""
    echo -e "${YELLOW}Or re-run with --push to do all of the above:${NC}"
    echo -e "   ${GREEN}bash app/scripts/build-all.sh --push${NC}"
    exit 0
fi

banner "Pushing"
git -C "$SHELLBROS" push origin main
git -C "$MATHLETE" push origin main master

banner "Purging jsDelivr"
# Each purge.py covers its own repo. The unpinned build.json is purged explicitly
# because that is the URL checker.js and Loader.getBuildSha() actually fetch, and
# it is the only cached file standing between a push and the new bundle.
cd "$SHELLBROS" && python3 app/scripts/purge.py || true
cd "$MATHLETE" && python3 app/scripts/purge.py || true

for repo in "shellbros/shellbros.github.io" "apstudy/mathlete"; do
    printf "purge %s/app/build.json -> " "$repo"
    curl -s --max-time 20 "https://purge.jsdelivr.net/gh/$repo/app/build.json" \
        | python3 -c "import json,sys;print(json.load(sys.stdin).get('status','?'))" 2>/dev/null || echo "failed"
done

banner "Verifying what jsDelivr serves"
printf "shellbros -> "
curl -s --max-time 20 "https://cdn.jsdelivr.net/gh/shellbros/shellbros.github.io/app/build.json" \
    | tr -d ' \t\n' || true
echo "   (want $SB_VERSION)"
printf "mathlete  -> "
curl -s --max-time 20 "https://cdn.jsdelivr.net/gh/apstudy/mathlete/app/build.json" \
    | tr -d ' \t\n' || true
echo "   (want $ML_VERSION)"

echo ""
echo -e "${CYAN}Done.${NC}"
