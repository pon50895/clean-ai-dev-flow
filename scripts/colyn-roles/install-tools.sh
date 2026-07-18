#!/usr/bin/env bash
#
# install-tools.sh — 一鍵檢查 + 安裝平行開發必備工具，已裝就跳過。
#
# 涵蓋：
#   1. gh           — GitHub CLI（PR / Issue / Run 操作；reviewer + supervisor 必裝）
#   2. colyn        — git worktree + tmux 編排（npm install -g colyn-cli）
#   3. gsd          — get-shit-done meta-prompting（npx get-shit-done-cc）
#   4. karpathy     — andrej-karpathy-skills 行為規範（plugin marketplace）
#   5. gitnexus     — codebase knowledge graph（npm install -g gitnexus）
#   6. codegraph    — code knowledge graph + MCP server（auto-wires into Claude Code）
#   7. gitleaks     — pre-commit secret scanner（installs hook + activates .githooks/）
#
# Note on permission interaction:
#   This script runs as a subprocess invoked via Bash(bash scripts/...:*). The
#   deny rules like Bash(npm install -g:*) / Bash(brew install:*) apply to
#   DIRECT Claude tool calls — they do NOT intercept commands inside this
#   subshell. That's intentional: the deny rules exist to stop ad-hoc installs
#   by the agent; explicit bootstrap via this script is the sanctioned path.
#
# 用法：
#   bash scripts/colyn-roles/install-tools.sh
#   FORCE_REINSTALL=1 bash scripts/colyn-roles/install-tools.sh   # 不管已裝強制重跑
#   DRY_RUN=1 bash scripts/colyn-roles/install-tools.sh           # 只檢查不安裝

set -euo pipefail

FORCE="${FORCE_REINSTALL:-0}"
DRY="${DRY_RUN:-0}"

run() {
  if [ "$DRY" = "1" ]; then
    echo "      [DRY] would run: $*"
  else
    echo "      [RUN] $*"
    eval "$@"
  fi
}

check_or_install() {
  local name="$1"
  local check_cmd="$2"   # 偵測指令：成功（exit 0）= 已裝
  local install_cmd="$3" # 安裝指令
  local installed=0

  if eval "$check_cmd" >/dev/null 2>&1; then
    installed=1
  fi

  if [ "$installed" = "1" ] && [ "$FORCE" != "1" ]; then
    echo "[$name] OK (already installed)"
    return 0
  fi

  if [ "$installed" = "1" ]; then
    echo "[$name] FORCE reinstall"
  else
    echo "[$name] missing → installing"
  fi
  run "$install_cmd"
  echo "[$name] done"
}

echo "=========================================="
echo " parallel-dev tools installer"
[ "$DRY" = "1" ] && echo " (DRY RUN: 不會真的裝)"
echo "=========================================="

# ----------------------------------------------------------------------------
# 1. gh (GitHub CLI) — supervisor / reviewer 跑 gh pr 必須先有
# 偵測：command -v gh && gh auth status (確認已登入；裝了沒登入也算缺)
# 安裝路徑分平台：mac=brew, linux=apt/yum, win=winget；無 brew 時 fallback 提示
# ----------------------------------------------------------------------------
gh_check() {
  command -v gh >/dev/null 2>&1 || return 1
  gh auth status >/dev/null 2>&1
}
gh_install_hint() {
  if [ "$(uname -s)" = "Darwin" ] && command -v brew >/dev/null 2>&1; then
    echo "brew install gh && gh auth login"
  elif command -v apt-get >/dev/null 2>&1; then
    echo "sudo apt install gh && gh auth login   # 或 see https://cli.github.com/manual/installation"
  else
    echo "see https://cli.github.com/manual/installation 然後 gh auth login"
  fi
}
if gh_check; then
  echo "[gh] OK (installed + authenticated)"
elif command -v gh >/dev/null 2>&1; then
  echo "[gh] installed but not authenticated → run: gh auth login"
else
  echo "[gh] missing → install: $(gh_install_hint)"
fi

# ----------------------------------------------------------------------------
# 2. colyn
# ----------------------------------------------------------------------------
check_or_install "colyn" \
  "command -v colyn" \
  "npm install -g colyn-cli && colyn setup"

# ----------------------------------------------------------------------------
# 2. gsd (get-shit-done)
# 安裝後會落在 ~/.claude/commands/gsd/ 或 ~/.claude/skills/gsd-*/
# ----------------------------------------------------------------------------
check_or_install "gsd" \
  "[ -d \"$HOME/.claude/commands/gsd\" ] || ls $HOME/.claude/skills 2>/dev/null | grep -qiE '^gsd'" \
  "npx -y get-shit-done-cc@latest"

# ----------------------------------------------------------------------------
# 3. karpathy-guidelines (andrej-karpathy-skills)
# 安裝後會落在 ~/.claude/skills/karpathy-guidelines（plugin marketplace 路線）
# 自動安裝需在 Claude Code 內跑 /plugin 指令；shell 端只能下載 CLAUDE.md。
# ----------------------------------------------------------------------------
KARPATHY_SKILL="$HOME/.claude/skills/karpathy-guidelines"
KARPATHY_PLUGIN="$HOME/.claude/plugins/marketplaces/forrestchang"
if [ -d "$KARPATHY_SKILL" ] || [ -d "$KARPATHY_PLUGIN" ] && [ "$FORCE" != "1" ]; then
  echo "[karpathy] OK (already installed)"
else
  echo "[karpathy] missing → 需手動在 Claude Code session 內執行："
  echo "  /plugin marketplace add forrestchang/andrej-karpathy-skills"
  echo "  /plugin install andrej-karpathy-skills@karpathy-skills"
  echo ""
  echo "       或 fallback：直接下載 CLAUDE.md 到 /tmp 由你決定貼到哪"
  if [ "$DRY" != "1" ]; then
    curl -sL https://raw.githubusercontent.com/forrestchang/andrej-karpathy-skills/main/CLAUDE.md \
      -o /tmp/karpathy-CLAUDE.md \
      && echo "       已下載 → /tmp/karpathy-CLAUDE.md" \
      || echo "       下載失敗"
  fi
fi

# ----------------------------------------------------------------------------
# 4. gitnexus
# ----------------------------------------------------------------------------
check_or_install "gitnexus" \
  "command -v gitnexus" \
  "npm install -g gitnexus"

# 補：gitnexus setup（MCP for Claude Code）— 安裝後第一次跑要設定
if command -v gitnexus >/dev/null 2>&1; then
  if [ "$DRY" != "1" ]; then
    if [ ! -f "$HOME/.claude/mcp.json" ] && [ ! -f "$HOME/.claude.json" ]; then
      echo "[gitnexus] 第一次安裝需跑 \`npx gitnexus setup\` 設 MCP；改天順手跑就好。"
    fi
  fi
fi

# ----------------------------------------------------------------------------
# 5. codegraph — code knowledge graph + MCP server for Claude Code
# install path: GitHub release / brew (depends on platform); MCP auto-wire via
#   `codegraph install -y --target claude --location global` 寫到 ~/.claude.json
# 偵測：command -v codegraph + ~/.claude.json 內含 codegraph MCP server
# ----------------------------------------------------------------------------
codegraph_install_hint() {
  if command -v brew >/dev/null 2>&1; then
    echo "brew install codegraph    # 或 see https://github.com/yourorg/codegraph"
  elif command -v npm >/dev/null 2>&1; then
    echo "npm install -g @codegraph/cli    # 或 see GitHub release"
  else
    echo "see codegraph repo for install instructions"
  fi
}
if command -v codegraph >/dev/null 2>&1; then
  echo "[codegraph] OK (binary installed: $(command -v codegraph))"
  # 檢查 MCP 是否已 wire 進 Claude Code
  if [ -f "$HOME/.claude.json" ] && grep -q '"codegraph"' "$HOME/.claude.json" 2>/dev/null; then
    echo "[codegraph] MCP already wired into Claude Code"
  else
    echo "[codegraph] MCP 未設定 → 自動 wire 進 Claude Code（global）"
    run "codegraph install -y --target claude --location global"
    echo "[codegraph] 重啟 Claude Code session 才會吃到新 MCP server"
  fi
else
  echo "[codegraph] missing → install: $(codegraph_install_hint)"
  echo "           裝完再跑一次本腳本,會自動 wire MCP"
fi

# ----------------------------------------------------------------------------
# 7. gitleaks — pre-commit secret scanner
# 偵測：command -v gitleaks + .git/config 的 core.hooksPath 指向 .githooks
# install path: brew (mac) / package manager / GitHub release
# ----------------------------------------------------------------------------
gitleaks_install_hint() {
  if command -v brew >/dev/null 2>&1; then
    echo "brew install gitleaks"
  elif command -v apt-get >/dev/null 2>&1; then
    echo "see https://github.com/gitleaks/gitleaks/releases (apt has no official package)"
  else
    echo "see https://github.com/gitleaks/gitleaks#installing"
  fi
}

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOKS_DIR="$PROJECT_ROOT/.githooks"
CURRENT_HOOKS_PATH=$(git -C "$PROJECT_ROOT" config --local --get core.hooksPath 2>/dev/null || echo "")

if command -v gitleaks >/dev/null 2>&1; then
  echo "[gitleaks] OK (binary installed: $(command -v gitleaks))"
else
  echo "[gitleaks] missing → install: $(gitleaks_install_hint)"
  echo "           裝完再跑一次本腳本,會自動 wire .githooks/"
fi

# Wire the pre-commit hook even if gitleaks isn't yet installed —
# the hook self-checks and gracefully no-ops if the binary is missing.
if [ -d "$HOOKS_DIR" ]; then
  if [ "$CURRENT_HOOKS_PATH" = ".githooks" ]; then
    echo "[gitleaks] core.hooksPath already set to .githooks"
  else
    echo "[gitleaks] wiring core.hooksPath → .githooks"
    if [ "$DRY" = "1" ]; then
      echo "      [DRY] would run: git -C $PROJECT_ROOT config --local core.hooksPath .githooks"
    else
      git -C "$PROJECT_ROOT" config --local core.hooksPath .githooks
      # Ensure hook is executable (chmod +x might be lost across machines)
      chmod +x "$HOOKS_DIR/pre-commit" 2>/dev/null || true
      echo "      [OK] activated"
    fi
  fi
else
  echo "[gitleaks] WARN: $HOOKS_DIR not found — repo missing .githooks/ dir, skipping wire"
fi

echo ""
echo "=========================================="
echo " summary"
echo "=========================================="
for t in gh colyn gsd karpathy gitnexus codegraph gitleaks; do
  case "$t" in
    gh)        cmd="command -v gh && gh auth status" ;;
    colyn)     cmd="command -v colyn" ;;
    gitnexus)  cmd="command -v gitnexus" ;;
    codegraph) cmd="command -v codegraph && grep -q '\"codegraph\"' \"$HOME/.claude.json\" 2>/dev/null" ;;
    gitleaks)  cmd="command -v gitleaks && [ \"\$(git -C \"$PROJECT_ROOT\" config --local --get core.hooksPath 2>/dev/null)\" = \".githooks\" ]" ;;
    gsd)       cmd="[ -d \"$HOME/.claude/commands/gsd\" ] || ls $HOME/.claude/skills 2>/dev/null | grep -qiE '^gsd'" ;;
    karpathy)  cmd="[ -d \"$HOME/.claude/skills/karpathy-guidelines\" ]" ;;
  esac
  if eval "$cmd" >/dev/null 2>&1; then
    echo "  [OK] $t"
  else
    echo "  [MISSING] $t"
  fi
done
