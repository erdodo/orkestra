#!/usr/bin/env bash
# Orkestra — Mac/Linux'ta Windows exe cross-compile
# Kullanim: bash scripts/build-windows-exe.sh
# Cikti: agent/target/x86_64-pc-windows-gnu/release/agent.exe

set -euo pipefail

AGENT_DIR="$(cd "$(dirname "$0")/../agent" && pwd)"
TARGET="x86_64-pc-windows-gnu"
OUT="$AGENT_DIR/target/$TARGET/release/agent.exe"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }

echo ""
echo "=== Orkestra Windows EXE Build ==="
echo ""

# -- MinGW linker -------------------------------------------------------------
if [[ "$(uname)" == "Darwin" ]]; then
    if ! command -v x86_64-w64-mingw32-gcc &>/dev/null; then
        warn "mingw-w64 kuruluyor..."
        brew install mingw-w64
    fi
    info "MinGW: $(x86_64-w64-mingw32-gcc --version | head -1)"
else
    if ! command -v x86_64-w64-mingw32-gcc &>/dev/null; then
        warn "gcc-mingw-w64 kuruluyor..."
        sudo apt-get install -y gcc-mingw-w64-x86-64
    fi
    info "MinGW hazir"
fi

# -- Rust target --------------------------------------------------------------
source "$HOME/.cargo/env" 2>/dev/null || true
rustup target add "$TARGET" 2>/dev/null || true

# -- Build --------------------------------------------------------------------
info "Derleniyor: $TARGET"
cargo build --release --target "$TARGET" \
    --manifest-path "$AGENT_DIR/Cargo.toml"

info "Hazir: $OUT"
ls -lh "$OUT"

echo ""
echo "Dagitmak icin:"
echo "  cp $OUT /ortak/dizin/orkestra-agent.exe"
echo "  veya GitHub Release'e yukle: gh release upload <tag> $OUT"
