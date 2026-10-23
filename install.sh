#!/usr/bin/env bash
# Install firefox-mcp for the current user. No root needed; safe to re-run.
#
#   ./install.sh                 link bin/firefox-mcp and add a menu entry
#   ./install.sh --with-skill    also link the Claude Code skill
#
# The repo stays where it is: bin/firefox-mcp and the skill are symlinked, so a
# `git pull` here updates them.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${PREFIX:-$HOME/.local}/bin"
APP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
SKILL_DIR="$HOME/.claude/skills/firefox-mcp"

link() {  # link $1 at $2, refusing to replace anything that is not our link
  local src=$1 dst=$2
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    echo "  ok     $dst"; return
  fi
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    echo "  skip   $dst exists and is not a link to this repo" >&2; return
  fi
  mkdir -p "$(dirname "$dst")"
  ln -s "$src" "$dst"
  echo "  link   $dst"
}

link "$REPO/bin/firefox-mcp" "$BIN_DIR/firefox-mcp"

# Menu entry: Exec gets the absolute path, since a desktop session's PATH may
# not include ~/.local/bin.
mkdir -p "$APP_DIR"
desktop="$APP_DIR/firefox-mcp.desktop"
tmp=$(mktemp)
sed "s|^Exec=firefox-mcp|Exec=$BIN_DIR/firefox-mcp|" "$REPO/firefox-mcp.desktop" > "$tmp"
if cmp -s "$tmp" "$desktop" 2>/dev/null; then
  rm -f "$tmp"; echo "  ok     $desktop"
else
  mv "$tmp" "$desktop"; chmod 644 "$desktop"; echo "  write  $desktop"
fi

if [ "${1:-}" = "--with-skill" ]; then
  link "$REPO/skill" "$SKILL_DIR"
fi

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "note: $BIN_DIR is not in PATH" ;;
esac
[ -n "$("$BIN_DIR/firefox-mcp" --print-profile 2>/dev/null || true)" ] ||
  echo "next: run 'firefox-mcp --create-profile'"
