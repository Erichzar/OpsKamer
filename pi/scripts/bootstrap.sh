#!/usr/bin/env bash
# Bootstrap pi on macOS/Linux: installs pi, copies OpsKamer's pi config into ~/.pi/agent, optionally
# adds tokenjuice. Idempotent: safe to re-run; backs up anything it would overwrite. Never touches
# keys: model access is yours (see ../../docs/MODEL-ACCESS.md).
# An existing pi config is KEPT (your provider, models and settings stay as they are).
#   ./bootstrap.sh            interactive
#   ./bootstrap.sh --yes      answer yes to the optional steps
#   ./bootstrap.sh --force    replace an existing settings.json / semantic-grep.json (after a backup)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PI_AGENT="$HOME/.pi/agent"
STAMP="$(date +%Y%m%d-%H%M%S)"
YES=0; FORCE=0
for a in "$@"; do case "$a" in --yes) YES=1;; --force) FORCE=1;; esac; done

info() { printf '\033[36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33m!!  %s\033[0m\n' "$*"; }
confirm() { [ "$YES" = 1 ] && return 0; read -r -p "    $1 [Y/n] " a; case "$a" in [nN]*) return 1;; *) return 0;; esac; }

copy_with_backup() {
  local src="$1" dst="$2"
  if [ -f "$dst" ]; then
    if cmp -s "$src" "$dst"; then info "$(basename "$dst") already current"; return; fi
    if [ "$FORCE" != 1 ]; then info "kept your $(basename "$dst") (OpsKamer's version: $src; --force replaces yours after a backup)"; return; fi
    cp "$dst" "$dst.bak-$STAMP"
    warn "backed up existing $(basename "$dst") -> $(basename "$dst").bak-$STAMP"
  fi
  cp "$src" "$dst"
  info "installed $(basename "$dst")"
}

# --- 1. prerequisites -------------------------------------------------------
info "Checking prerequisites"
command -v node >/dev/null || { echo "Node.js 22.19 or newer is required: https://nodejs.org (macOS: brew install node)"; exit 1; }
NODE_VER="$(node --version | sed 's/^v//')"
NODE_MAJOR="${NODE_VER%%.*}"; NODE_REST="${NODE_VER#*.}"; NODE_MINOR="${NODE_REST%%.*}"
if [ "$NODE_MAJOR" -lt 22 ] || { [ "$NODE_MAJOR" -eq 22 ] && [ "$NODE_MINOR" -lt 19 ]; }; then
  echo "Node.js 22.19 or newer is required, found v$NODE_VER"; exit 1
fi

if ! command -v pi >/dev/null; then
  info "Installing pi (@earendil-works/pi-coding-agent) globally"
  npm install -g @earendil-works/pi-coding-agent
else
  info "pi already installed: $(pi --version)"
fi

# --- 2. pi config -----------------------------------------------------------
# settings.json and semantic-grep.json only. models.json is yours (it can hold provider keys), so it
# is never overwritten; pi/pi-config/models.local-example.json shows how to add a local server.
info "Installing pi config -> $PI_AGENT"
mkdir -p "$PI_AGENT"
for f in settings.json semantic-grep.json; do
  copy_with_backup "$REPO_ROOT/pi-config/$f" "$PI_AGENT/$f"
done

# --- 3. optional: tokenjuice (MIT, github.com/vincentkoc/tokenjuice) -------------------------------
# Compacts noisy shell output before it reaches the model. Installed by its own installer, not vendored.
if confirm "Install tokenjuice for pi (compacts long command output)?"; then
  npx --yes tokenjuice install pi
fi

# --- 4. next steps ----------------------------------------------------------
echo
info "Done. Next:"
cat <<'EOF'

  1. If pi has no model access yet, add your own (see docs/MODEL-ACCESS.md). For Anthropic, an API key
     in your shell profile (~/.zshrc on macOS):
       export ANTHROPIC_API_KEY="<your key>"
  2. Check it works:
       pi -p "Reply with exactly: PI OK"
  3. Skills: Mission Centre installs OpsKamer's skills into ~/.agents/skills on launch.
     Without Mission Centre, copy them yourself: cp -R skills/<name> ~/.agents/skills/

EOF
