#!/usr/bin/env bash
set -euo pipefail

# Worship Setlist -> Spotify: one-time prereq + config bootstrap.
# Safe to re-run. Does not touch an existing config.

CONFIG_DIR="$HOME/.config/worship-skill"
CONFIG_FILE="$CONFIG_DIR/config.json"
SKILL_DIR="$HOME/.claude/skills/worship-setlist-to-spotify"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

bold()  { printf '\033[1m%s\033[0m\n' "$*"; }
ok()    { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn()  { printf '  \033[33m!\033[0m %s\n' "$*"; }
fail()  { printf '  \033[31m✗\033[0m %s\n' "$*"; }

bold "1. Prerequisite check"

MISSING=0

if command -v node >/dev/null 2>&1; then
  NODE_MAJOR="$(node -v | sed 's/v\([0-9]*\).*/\1/')"
  if [ "$NODE_MAJOR" -ge 18 ]; then
    ok "node $(node -v)"
  else
    fail "node $(node -v) — need 18+"
    MISSING=1
  fi
else
  fail "node not found (macOS: brew install node • Linux: distro pkg manager • or use nvm)"
  MISSING=1
fi

if command -v npm >/dev/null 2>&1; then
  ok "npm $(npm -v)"
else
  fail "npm not found (ships with node)"
  MISSING=1
fi

if command -v git >/dev/null 2>&1; then
  ok "$(git --version)"
else
  fail "git not found (macOS: brew install git)"
  MISSING=1
fi

if [ "$MISSING" -ne 0 ]; then
  echo
  fail "Install missing prerequisites above, then re-run this script."
  exit 1
fi

echo
bold "2. Config directory"

mkdir -p "$CONFIG_DIR"
if [ -f "$CONFIG_FILE" ]; then
  ok "config already exists at $CONFIG_FILE (left untouched)"
else
  cp "$REPO_ROOT/config.example.json" "$CONFIG_FILE"
  ok "initialized $CONFIG_FILE from template"
fi

echo
bold "3. Skill registration"

mkdir -p "$SKILL_DIR"
if [ -L "$SKILL_DIR/SKILL.md" ]; then
  ok "SKILL.md already symlinked"
elif [ -e "$SKILL_DIR/SKILL.md" ]; then
  warn "$SKILL_DIR/SKILL.md exists and is not a symlink — leaving in place. Delete it manually if you want to track this repo as the source of truth."
else
  ln -s "$REPO_ROOT/SKILL.md" "$SKILL_DIR/SKILL.md"
  ok "symlinked SKILL.md into $SKILL_DIR"
fi

echo
bold "Prereqs OK. Remaining steps require browser/terminal work:"
cat <<'EOF'

  1. Clone + build the Spotify MCP server:
       git clone https://github.com/marcelmarais/spotify-mcp-server
       cd spotify-mcp-server && npm install && npm run build

  2. Create a Spotify developer app (developer.spotify.com/dashboard):
       Redirect URI: http://127.0.0.1:8888/callback
       Copy client ID + secret into spotify-mcp-server/spotify-config.json
       Run: npm run auth   (browser flow)

  3. Register the built MCP with Claude Code:
       claude mcp add spotify -- node /absolute/path/to/spotify-mcp-server/build/index.js

  4. Create a Planning Center Personal Access Token:
       api.planningcenteronline.com/oauth/applications -> Personal Access Tokens

  5. Open Claude Code and invoke the skill:
       Claude will pick up the partial config, prompt for the PCO PAT,
       fetch your service types, ask which playlist to use, and finish setup
       with a dry-run before the first real sync.

EOF
