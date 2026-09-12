# dft-env

One-command environment setup for the scan-insertion + ATPG DFT project:
**LibreLane + OpenROAD's `dft` module + Sky130 + Fault**.

Works identically on macOS (Intel/Apple Silicon) and Linux (x86_64/aarch64) —
this VPS, your home Ubuntu server, or your Mac.

## Usage on a new machine

```bash
git clone <your-repo-url> dft-env
cd dft-env
./bootstrap.sh
```

That's it. The script is idempotent — safe to re-run if it fails partway
through (e.g. network hiccup), it skips anything already installed.

## What it installs

1. **Nix** — LibreLane's own recommended install path, gives you
   reproducible builds of the whole EDA toolchain (Yosys, OpenROAD, Magic,
   Netgen, KLayout) pinned together.
2. **LibreLane** — cloned to `~/librelane`, checked out at `LIBRELANE_REF`.
3. **Sky130 PDK** — enabled via `ciel` inside the nix-shell.
4. **Swift** — via `swiftly`, the *same* installer on both macOS and Linux,
   so you get an identical Swift version everywhere instead of whatever
   each OS's package manager happens to ship.
5. **Icarus Verilog (dev branch)** — built from source. Fault specifically
   needs this; the stable release doesn't work per Fault's own docs.
6. **Fault** — the ATPG + scan-stitching + JTAG tool, via pip.

## Making this fully pinned (do this once you have a working run)

Right now `LIBRELANE_REF` defaults to `main` and `FAULT_VERSION` defaults to
latest — good enough to get started, but "main" drifts over time. Once
you've gotten a complete run working on one machine:

1. Note the LibreLane git tag/commit and Fault version that worked.
2. Edit the two variables at the top of `bootstrap.sh`.
3. Commit that change.

From then on, every machine you bootstrap gets the *exact* same tool
versions — that's the actual point of using Nix here, not just "a package
manager."

## After bootstrapping

```bash
cd ~/librelane
nix-shell
# inside the shell:
ciel enable sky130A     # if it didn't already succeed during bootstrap
fault --version
iverilog -V
```

Run the bundled `spm` example through LibreLane's Classic flow before
touching your own design, to confirm the install actually works.

## Known rough edges

- **Linux Icarus Verilog build** needs `build-essential autoconf gperf flex
  bison` — the script installs these via `apt-get` with `sudo`, so you'll
  be prompted for your password on Linux.
- **macOS build deps** go through Homebrew if present; if you don't have
  Homebrew, the script will tell you what to install manually.
- **First `nix-shell` invocation** pulls the FOSSi binary cache and can
  take ~10 minutes. Every invocation after that is fast.

## Real issues hit and fixed (from a live Ubuntu 24.04 VPS run)

- **PEP 668 blocks plain `pip install`.** Ubuntu 24.04's system Python refuses unmanaged installs. Fixed by switching Fault's install to `pipx`, which isolates it into its own venv.
- **Fault's pyverilog dependency has to live at the *system* Python level, not inside the pipx venv.** Fault's Swift binary spawns a fresh `python3` subprocess by searching PATH rather than reusing pipx's isolated interpreter — that subprocess resolves to the system Python, which never sees anything injected into the pipx venv. Fixed with `pip3 install pyverilog --break-system-packages` at the system level. Low-risk since pyverilog is pure-Python with no compiled deps to conflict with anything apt/brew manages.
- **Swiftly's env sourcing didn't persist across sessions.** The script originally only sourced `env.sh` within its own process. Fixed by also appending that `source` line to `~/.bashrc`/`~/.zshrc`.
- **`nix-shell` or `swift` "not found" right after install, in the same terminal.** Not a broken install — it's a stale shell session that predates the PATH changes. Reconnect / open a new terminal and it resolves.
