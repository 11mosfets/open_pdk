#!/usr/bin/env bash
set -euo pipefail

LIBRELANE_REF="${LIBRELANE_REF:-main}"
FAULT_VERSION="${FAULT_VERSION:-}"

OS="$(uname -s)"
ARCH="$(uname -m)"
echo "==> Detected: $OS / $ARCH"

if ! command -v nix >/dev/null 2>&1; then
  echo "==> Installing Nix..."
  sh <(curl -L https://nixos.org/nix/install) --daemon
  . /etc/bashrc 2>/dev/null || true
  . "$HOME/.nix-profile/etc/profile.d/nix.sh" 2>/dev/null || true
else
  echo "==> Nix already present, skipping."
fi

LIBRELANE_DIR="$HOME/librelane"
if [ ! -d "$LIBRELANE_DIR" ]; then
  echo "==> Cloning LibreLane @ $LIBRELANE_REF"
  git clone https://github.com/librelane/librelane.git "$LIBRELANE_DIR"
  (cd "$LIBRELANE_DIR" && git checkout "$LIBRELANE_REF")
else
  echo "==> LibreLane already cloned at $LIBRELANE_DIR, skipping."
fi

echo "==> Priming nix-shell (first run pulls FOSSi binary cache, ~10 min - can be much longer on a cache miss, e.g. KLayout's Qt bindings compiling from source)..."
(
  cd "$LIBRELANE_DIR"
  nix-shell --run "ciel enable sky130A || echo '!! ciel enable failed - check manually'"
)

if ! command -v swift >/dev/null 2>&1; then
  echo "==> Installing Swift via swiftly..."
  if [ "$OS" = "Darwin" ]; then
    curl -O https://download.swift.org/swiftly/darwin/swiftly.pkg
    installer -pkg swiftly.pkg -target CurrentUserHomeDirectory
    ~/.swiftly/bin/swiftly init --quiet-shell-followup --assume-yes
    SWIFTLY_ENV="${SWIFTLY_HOME_DIR:-$HOME/.swiftly}/env.sh"
  elif [ "$OS" = "Linux" ]; then
    curl -O "https://download.swift.org/swiftly/linux/swiftly-${ARCH}.tar.gz"
    tar zxf "swiftly-${ARCH}.tar.gz"
    ./swiftly init --quiet-shell-followup --assume-yes
    SWIFTLY_ENV="${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/env.sh"
  else
    echo "!! Unsupported OS for Swift install: $OS - install manually."
    SWIFTLY_ENV=""
  fi

  if [ -n "$SWIFTLY_ENV" ]; then
    . "$SWIFTLY_ENV"
    SHELL_RC="$HOME/.bashrc"
    [ "$(basename "${SHELL:-bash}")" = "zsh" ] && SHELL_RC="$HOME/.zshrc"
    if ! grep -qxF ". \"$SWIFTLY_ENV\"" "$SHELL_RC" 2>/dev/null; then
      echo ". \"$SWIFTLY_ENV\"" >> "$SHELL_RC"
      echo "==> Added swiftly env sourcing to $SHELL_RC"
    fi
  fi
  hash -r
else
  echo "==> Swift already present, skipping."
fi

if [ "$OS" = "Linux" ]; then
  echo "==> Installing Linux build deps (needs sudo)..."
  sudo apt-get update -y
  sudo apt-get install -y build-essential autoconf gperf flex bison git jq pipx
elif [ "$OS" = "Darwin" ]; then
  echo "==> Checking Xcode Command Line Tools..."
  xcode-select -p >/dev/null 2>&1 || xcode-select --install
  if command -v brew >/dev/null 2>&1; then
    brew install autoconf gperf flex bison jq pipx
  else
    echo "!! Homebrew not found - install autoconf/gperf/flex/bison/jq/pipx manually."
  fi
fi

command -v pipx >/dev/null 2>&1 && pipx ensurepath >/dev/null 2>&1 || true

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

echo "==> Installing Fault via pipx..."
if [ -n "$FAULT_VERSION" ]; then
  pipx install "fault-dft==${FAULT_VERSION}"
else
  pipx install fault-dft
fi

echo "==> Installing pyverilog at the system level (Fault's subprocess needs it there, not in the pipx venv)..."
if [ "$OS" = "Linux" ]; then
  pip3 install pyverilog --break-system-packages
else
  pip3 install pyverilog --break-system-packages 2>/dev/null || pip3 install pyverilog
fi

cat <<'DONE_MSG'

============================================================
 Setup complete.

 Next steps:
   cd ~/librelane && nix-shell
   ciel enable sky130A
   fault --version
   iverilog -V

 If a fresh terminal can't find `swift` or `nix-shell`, that's a
 stale-session issue - reconnect and try again before assuming
 something's broken.
============================================================
DONE_MSG
