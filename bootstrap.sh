#!/usr/bin/env bash
# ============================================================
# DFT Project Environment Bootstrap
# Reproducible setup for: LibreLane + Sky130 + Fault (ATPG)
# Works on: macOS (Intel/Apple Silicon) and Linux (x86_64/aarch64)
#
# Usage:   ./bootstrap.sh
# Safe to re-run — every step checks before acting.
# ============================================================

set -euo pipefail

# ---- Pin versions here for true reproducibility ------------
# Leave as-is for your first run. Once you've confirmed a
# combination works end-to-end, fill these in so every future
# machine gets the EXACT same environment, not "whatever main
# happens to be that day."
LIBRELANE_REF="${LIBRELANE_REF:-main}"    # e.g. "3.0.0" once verified
FAULT_VERSION="${FAULT_VERSION:-}"        # e.g. "0.9.0" — empty = latest

OS="$(uname -s)"
ARCH="$(uname -m)"
echo "==> Detected: $OS / $ARCH"

# ------------------------------------------------------------
# 1. Nix — LibreLane's own recommended install path
# ------------------------------------------------------------
if ! command -v nix >/dev/null 2>&1; then
  echo "==> Installing Nix..."
  sh <(curl -L https://nixos.org/nix/install) --daemon
  # shellcheck disable=SC1091
  . /etc/bashrc 2>/dev/null || true
  . "$HOME/.nix-profile/etc/profile.d/nix.sh" 2>/dev/null || true
else
  echo "==> Nix already present, skipping."
fi

# ------------------------------------------------------------
# 2. LibreLane (pinned ref)
# ------------------------------------------------------------
LIBRELANE_DIR="$HOME/librelane"
if [ ! -d "$LIBRELANE_DIR" ]; then
  echo "==> Cloning LibreLane @ $LIBRELANE_REF"
  git clone https://github.com/librelane/librelane.git "$LIBRELANE_DIR"
  (cd "$LIBRELANE_DIR" && git checkout "$LIBRELANE_REF")
else
  echo "==> LibreLane already cloned at $LIBRELANE_DIR, skipping."
fi

# ------------------------------------------------------------
# 3. Prime the nix-shell + enable Sky130 via ciel
# ------------------------------------------------------------
echo "==> Priming nix-shell (first run pulls FOSSi binary cache, ~10 min)..."
(
  cd "$LIBRELANE_DIR"
  nix-shell --run "ciel enable sky130A || echo '!! ciel enable failed - check manually'"
)

# ------------------------------------------------------------
# 4. Swift via swiftly — SAME installer on macOS and Linux, so
#    the Swift version is identical everywhere instead of
#    whatever each OS's package manager happens to ship.
# ------------------------------------------------------------
if ! command -v swift >/dev/null 2>&1; then
  echo "==> Installing Swift via swiftly..."
  if [ "$OS" = "Darwin" ]; then
    curl -O https://download.swift.org/swiftly/darwin/swiftly.pkg
    installer -pkg swiftly.pkg -target CurrentUserHomeDirectory
    ~/.swiftly/bin/swiftly init --quiet-shell-followup --assume-yes
    # shellcheck disable=SC1091
    . "${SWIFTLY_HOME_DIR:-$HOME/.swiftly}/env.sh"
  elif [ "$OS" = "Linux" ]; then
    curl -O "https://download.swift.org/swiftly/linux/swiftly-${ARCH}.tar.gz"
    tar zxf "swiftly-${ARCH}.tar.gz"
    ./swiftly init --quiet-shell-followup --assume-yes
    # shellcheck disable=SC1091
    . "${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/env.sh"
  else
    echo "!! Unsupported OS for Swift install: $OS — install manually."
  fi
  hash -r
else
  echo "==> Swift already present, skipping."
fi

# ------------------------------------------------------------
# 5. OS-level build deps for Icarus Verilog dev branch
#    (Fault needs this — stable Icarus doesn't work per its docs)
# ------------------------------------------------------------
if [ "$OS" = "Linux" ]; then
  echo "==> Installing Linux build deps (needs sudo)..."
  sudo apt-get update -y
  sudo apt-get install -y build-essential autoconf gperf flex bison git jq
elif [ "$OS" = "Darwin" ]; then
  echo "==> Checking Xcode Command Line Tools..."
  xcode-select -p >/dev/null 2>&1 || xcode-select --install
  if command -v brew >/dev/null 2>&1; then
    brew install autoconf gperf flex bison jq
  else
    echo "!! Homebrew not found — install autoconf/gperf/flex/bison/jq manually."
  fi
fi

# ------------------------------------------------------------
# 6. Icarus Verilog — development branch (Fault requirement)
# ------------------------------------------------------------
IVERILOG_DIR="$HOME/iverilog-dev"
if [ ! -d "$IVERILOG_DIR" ]; then
  echo "==> Building Icarus Verilog (development branch)..."
  git clone https://github.com/steveicarus/iverilog.git "$IVERILOG_DIR"
  (
    cd "$IVERILOG_DIR"
    sh ./autoconf.sh
    ./configure
    NPROC="$(command -v nproc >/dev/null 2>&1 && nproc || sysctl -n hw.ncpu)"
    make -j"$NPROC"
    sudo make install
  )
else
  echo "==> Icarus Verilog dev checkout already present, skipping build."
fi

# ------------------------------------------------------------
# 7. Fault (ATPG + scan stitching + JTAG)
# ------------------------------------------------------------
echo "==> Installing Fault..."
if [ -n "$FAULT_VERSION" ]; then
  python3 -m pip install --user -U "fault-dft==${FAULT_VERSION}"
else
  python3 -m pip install --user -U fault-dft
fi

# ------------------------------------------------------------
# Done
# ------------------------------------------------------------
cat <<'EOF'

============================================================
 Setup complete.

 Next steps:
   cd ~/librelane && nix-shell
   # inside the shell:
   ciel enable sky130A     # if step 3 didn't already succeed
   fault --version         # sanity-check ATPG tool
   iverilog -V             # sanity-check dev Icarus build

 To pin this exact environment for future machines: once
 everything above checks out, edit LIBRELANE_REF and
 FAULT_VERSION at the top of this script and commit the
 change. Every machine you run it on after that gets the
 identical setup, not just "whatever main happens to be."
============================================================
EOF
