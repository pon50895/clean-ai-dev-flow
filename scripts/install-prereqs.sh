#!/usr/bin/env bash
# install-prereqs.sh — clean-ai-dev-flow prerequisites installer (macOS, brew-first)
#
# Covers PREREQUISITES.md item 0-5 (Homebrew + tool binaries + hooks wiring).
# Item 6, 7 (ponytail plugin, karpathy-guidelines skill) are Claude Code
# session-level installs and are only printed as manual reminders at the end
# (item 7 ships a copy-ready file in dev-rule/templates/, see the printed hint).
#
# Usage: bash scripts/install-prereqs.sh   (run from repo root, or anywhere —
#        step 5 only applies if run inside a target project that has .githooks/)

set -euo pipefail

echo "== 0. Homebrew =="
if command -v brew >/dev/null 2>&1; then
  echo "[brew] OK: $(brew --version | head -1)"
else
  echo "[brew] not found -- installing (requires macOS Xcode Command Line Tools;"
  echo "        the installer will prompt for them if missing, and may ask for your password)..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Apple Silicon installs to /opt/homebrew, Intel to /usr/local — put the right one on PATH for this script.
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
  if ! command -v brew >/dev/null 2>&1; then
    echo "[brew] install finished but 'brew' still not on PATH in this shell."
    echo "       Open a new terminal (or run the 'eval \$(brew shellenv)' line the installer printed) and re-run this script."
    exit 1
  fi
  echo "[brew] OK: $(brew --version | head -1)"
fi

echo "== 1. node + npm =="
# ponytail: must precede Claude Code CLI — step 2 installs it via npm, which needs node on PATH first.
if command -v node >/dev/null 2>&1; then
  echo "[node] OK: $(node --version)"
else
  echo "[node] installing via brew..."
  brew install node
fi

echo "== 2. Claude Code CLI =="
if command -v claude >/dev/null 2>&1; then
  echo "[claude] OK: $(claude --version)"
else
  echo "[claude] installing via npm..."
  npm install -g @anthropic-ai/claude-code
fi

echo "== 3. gh (GitHub CLI) =="
if command -v gh >/dev/null 2>&1; then
  echo "[gh] OK: $(gh --version | head -1)"
else
  echo "[gh] installing via brew..."
  brew install gh
fi
if ! gh auth status >/dev/null 2>&1; then
  echo "[gh] not authenticated -- run 'gh auth login' manually after this script finishes."
fi

echo "== 4. git >= 2.30 =="
if command -v git >/dev/null 2>&1; then
  echo "[git] found: $(git --version)"
else
  echo "[git] installing via brew..."
  brew install git
fi

echo "== 5. git hooks wiring (run inside your target project) =="
if [ -d .githooks ]; then
  git config core.hooksPath .githooks
  chmod +x .githooks/pre-commit .githooks/pre-push 2>/dev/null || true
  echo "[hooks] core.hooksPath set to: $(git config core.hooksPath)"
else
  echo "[hooks] SKIPPED: no .githooks/ in current directory."
  echo "        copy it from clean-ai-dev-flow first, then re-run:"
  echo "        git config core.hooksPath .githooks"
fi

echo ""
echo "== manual steps remaining (interactive, inside a Claude Code session) =="
echo "  6. ponytail skill:            /plugin marketplace add DietrichGebert/ponytail  &&  /plugin install ponytail@ponytail"
echo "  7. karpathy-guidelines skill: mkdir -p ~/.claude/skills/karpathy-guidelines && cp dev-rule/templates/karpathy-guidelines-SKILL.md ~/.claude/skills/karpathy-guidelines/SKILL.md"
echo ""
echo "Verify everything: claude --version && gh auth status && node --version && git --version && git config core.hooksPath"
