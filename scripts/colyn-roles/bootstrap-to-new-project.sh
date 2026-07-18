#!/usr/bin/env bash
#
# bootstrap-to-new-project.sh — 把 clean-ai-dev-flow 的三層架構一鍵套到新專案。
#
# 自動做：
#   1. 複製 dev-rule/ + scripts/colyn-roles/ 到 <target-dir>
#   2. 把 sample/.claude.local.json 內的 MY-NEW-PROJECT / your-name 佔位符
#      自動替換成 <target-dir> 的絕對路徑
#   3. 驗證沒有殘留佔位符
#
# 可選做（INIT_REPO=1）：
#   4. git init + 建 main 分支
#   5. mkdir .planning/
#   6. 寫 CLAUDE.md placeholder（業務語境留白）
#
# 用法：
#   bash scripts/colyn-roles/bootstrap-to-new-project.sh <target-dir>
#
# 環境變數：
#   DRY=1        只 show 要做什麼，不真寫
#   FORCE=1      target 內已有 dev-rule/ 或 scripts/ 也覆蓋（先備份）
#   INIT_REPO=1  順便幫 target git init + 建 main 分支 + .planning/ + CLAUDE.md placeholder
#
# 範例：
#   bash scripts/colyn-roles/bootstrap-to-new-project.sh ~/Desktop/my-saas
#   DRY=1 bash scripts/colyn-roles/bootstrap-to-new-project.sh ~/Desktop/my-saas
#   INIT_REPO=1 bash scripts/colyn-roles/bootstrap-to-new-project.sh ~/Desktop/empty-dir

set -euo pipefail

# ----------------------------------------------------------------------------
# args + env
# ----------------------------------------------------------------------------
TARGET_RAW="${1:-}"
if [ -z "$TARGET_RAW" ]; then
  cat <<'USAGE'
Usage: bash bootstrap-to-new-project.sh <target-dir>

Env:
  DRY=1        只 show 要做什麼，不真寫
  FORCE=1      target 內已有 dev-rule/ 或 scripts/ 也覆蓋（先備份）
  INIT_REPO=1  順便 git init + 建 main + .planning/ + CLAUDE.md placeholder

Example:
  bash bootstrap-to-new-project.sh ~/Desktop/my-saas
  INIT_REPO=1 bash bootstrap-to-new-project.sh ~/Desktop/empty-dir
USAGE
  exit 2
fi

DRY="${DRY:-0}"
FORCE="${FORCE:-0}"
INIT_REPO="${INIT_REPO:-0}"

# ----------------------------------------------------------------------------
# locate source (this repo)
# ----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [ ! -d "$SRC_ROOT/dev-rule" ] || [ ! -d "$SRC_ROOT/scripts/colyn-roles" ]; then
  echo "[ERROR] source 不完整：$SRC_ROOT 找不到 dev-rule/ 或 scripts/colyn-roles/"
  echo "        確認你是從 clean-ai-dev-flow repo 內跑這支腳本。"
  exit 1
fi

# ----------------------------------------------------------------------------
# normalize target to absolute path
# ----------------------------------------------------------------------------
if [ ! -d "$TARGET_RAW" ]; then
  if [ "$INIT_REPO" = "1" ]; then
    if [ "$DRY" = "1" ]; then
      echo "[DRY] would: mkdir -p $TARGET_RAW"
      # 為了讓 cd 能成功，DRY 模式仍實際 mkdir（無破壞性）
    fi
    mkdir -p "$TARGET_RAW"
  else
    echo "[ERROR] target 不存在：$TARGET_RAW"
    echo "        加 INIT_REPO=1 讓本腳本幫你建目錄 + git init，"
    echo "        或自己先 mkdir + git init 再跑。"
    exit 1
  fi
fi

TARGET="$(cd "$TARGET_RAW" && pwd)"

if [ "$TARGET" = "$SRC_ROOT" ]; then
  echo "[ERROR] target == source ($SRC_ROOT)。拒絕自我複製。"
  exit 1
fi

echo "=========================================="
echo " bootstrap-to-new-project"
echo "=========================================="
echo "  source:    $SRC_ROOT"
echo "  target:    $TARGET"
echo "  DRY:       $DRY    (1 = 只 show 不寫)"
echo "  FORCE:     $FORCE  (1 = 已存在也覆蓋)"
echo "  INIT_REPO: $INIT_REPO  (1 = git init + .planning/ + CLAUDE.md)"
echo ""

# ----------------------------------------------------------------------------
# Step 0 (optional) — INIT_REPO
# ----------------------------------------------------------------------------
if [ "$INIT_REPO" = "1" ]; then
  echo "[step 0] INIT_REPO=1 → 初始化 repo + scaffolding"

  # git init（已是 repo 跳過）
  if [ ! -d "$TARGET/.git" ]; then
    if [ "$DRY" = "1" ]; then
      echo "  [DRY] would: git -C $TARGET init -b main"
    else
      git -C "$TARGET" init -b main
      echo "  [OK] git init -b main"
    fi
  else
    echo "  [skip] $TARGET 已是 git repo"
    # 確認有 main 分支
    if ! git -C "$TARGET" show-ref --verify --quiet refs/heads/main 2>/dev/null; then
      current="$(git -C "$TARGET" symbolic-ref --short HEAD 2>/dev/null || echo '<detached>')"
      echo "  [WARN] 沒 main 分支（目前在 $current）。worker rebase 會炸。"
      echo "         請手動：git -C $TARGET branch -m $current main"
    fi
  fi

  # .planning/
  if [ ! -d "$TARGET/.planning" ]; then
    if [ "$DRY" = "1" ]; then
      echo "  [DRY] would: mkdir $TARGET/.planning"
    else
      mkdir -p "$TARGET/.planning"
      echo "  [OK] mkdir .planning/"
    fi
  fi

  # CLAUDE.md placeholder
  if [ ! -f "$TARGET/CLAUDE.md" ]; then
    if [ "$DRY" = "1" ]; then
      echo "  [DRY] would: write $TARGET/CLAUDE.md (placeholder)"
    else
      cat > "$TARGET/CLAUDE.md" <<'CLAUDEMD'
# CLAUDE.md

> 本檔由 clean-ai-dev-flow bootstrap 產生，請在動工前改寫成本專案的業務語境。

## 專案是什麼
TODO：一句話描述本專案做什麼、給誰用、為什麼存在。

## 紅線重申（業務層）
TODO：除了 dev-rule/ 的通用紅線，本專案有哪些業務層紅線（例：金流欄位不可 log、PII 加密、特定 endpoint 不可裸開）。

## 規範下層
所有通用紅線、平行開發 SOP、安全標準請見 `dev-rule/`（SSOT，修改走 `[DEV-RULE]` PR）。
本檔只放本專案專屬的業務語境與紅線重申。
CLAUDEMD
      echo "  [OK] CLAUDE.md placeholder 已寫"
    fi
  else
    echo "  [skip] CLAUDE.md 已存在"
  fi
  echo ""
fi

# ----------------------------------------------------------------------------
# Step 1 — pre-flight：target 已有 dev-rule / scripts？
# ----------------------------------------------------------------------------
echo "[step 1] pre-flight"

CONFLICTS=()
[ -e "$TARGET/dev-rule" ] && CONFLICTS+=("dev-rule")
[ -e "$TARGET/scripts/colyn-roles" ] && CONFLICTS+=("scripts/colyn-roles")

if [ "${#CONFLICTS[@]}" -gt 0 ]; then
  if [ "$FORCE" != "1" ]; then
    echo "  [ERROR] target 已存在以下路徑（會被覆寫）："
    for c in "${CONFLICTS[@]}"; do echo "    - $TARGET/$c"; done
    echo "  加 FORCE=1 才會繼續（會先備份成 .bak.<timestamp>）"
    exit 1
  fi

  TS="$(date +%Y%m%d-%H%M%S)"
  echo "  [FORCE] 備份既有目錄：尾碼 .bak.$TS"
  for c in "${CONFLICTS[@]}"; do
    if [ "$DRY" = "1" ]; then
      echo "    [DRY] would: mv $TARGET/$c $TARGET/$c.bak.$TS"
    else
      mv "$TARGET/$c" "$TARGET/$c.bak.$TS"
      echo "    [OK] mv $c → $c.bak.$TS"
    fi
  done
fi
echo "  [OK] pre-flight 通過"
echo ""

# ----------------------------------------------------------------------------
# Step 2 — 複製 dev-rule/ + scripts/colyn-roles/
# ----------------------------------------------------------------------------
echo "[step 2] 複製 SSOT 檔案"

if [ "$DRY" = "1" ]; then
  echo "  [DRY] would: cp -R $SRC_ROOT/dev-rule $TARGET/dev-rule"
  echo "  [DRY] would: mkdir -p $TARGET/scripts && cp -R $SRC_ROOT/scripts/colyn-roles $TARGET/scripts/colyn-roles"
else
  cp -R "$SRC_ROOT/dev-rule" "$TARGET/dev-rule"
  echo "  [OK] dev-rule/ ($(find "$TARGET/dev-rule" -type f | wc -l | tr -d ' ') files)"

  mkdir -p "$TARGET/scripts"
  cp -R "$SRC_ROOT/scripts/colyn-roles" "$TARGET/scripts/colyn-roles"
  echo "  [OK] scripts/colyn-roles/ ($(find "$TARGET/scripts/colyn-roles" -type f | wc -l | tr -d ' ') files)"
fi
echo ""

# ----------------------------------------------------------------------------
# Step 3 — 部署 .claude/ 雙層(2026-05-30 split 後新 schema)
#   shared:    sample/settings.json       → target/.claude/settings.json
#   personal:  sample/settings.local.json → target/.claude/settings.local.json
#              (placeholder /Users/your-name/Desktop/MY-NEW-PROJECT → $TARGET)
# Legacy fallback:若 sample 還是舊單檔 .claude.local.json,仍走舊路徑。
# ----------------------------------------------------------------------------
echo "[step 3] 部署 .claude/ 雙層 → $TARGET/.claude/"

SAMPLE_DIR="$TARGET/dev-rule/sample"
SAMPLE_SHARED="$SAMPLE_DIR/settings.json"
SAMPLE_LOCAL="$SAMPLE_DIR/settings.local.json"
SAMPLE_LEGACY="$SAMPLE_DIR/.claude.local.json"
CLAUDE_DIR="$TARGET/.claude"
DST_SHARED="$CLAUDE_DIR/settings.json"
DST_LOCAL="$CLAUDE_DIR/settings.local.json"
PLACEHOLDER="/Users/your-name/Desktop/MY-NEW-PROJECT"

NEW_LOCAL_COMMENT="Deployed by bootstrap-to-new-project.sh on $(date +%Y-%m-%d) for $TARGET. Personal layer (gitignored). See dev-rule/sample/README.md."

# macOS sed 與 Linux sed 的 -i 參數不同
SED_INPLACE=(-i '')
[[ "$OSTYPE" != "darwin"* ]] && SED_INPLACE=(-i)

if [ "$DRY" = "1" ]; then
  echo "  [DRY] would mkdir -p $CLAUDE_DIR"
  # In DRY mode step 2 didn't actually copy, so check SRC sample to forecast outcome.
  SRC_SAMPLE_DIR="$SRC_ROOT/dev-rule/sample"
  if [ -f "$SRC_SAMPLE_DIR/settings.json" ] && [ -f "$SRC_SAMPLE_DIR/settings.local.json" ]; then
    echo "  [DRY] would cp $SRC_SAMPLE_DIR/settings.json → $DST_SHARED"
    echo "  [DRY] would cp $SRC_SAMPLE_DIR/settings.local.json → $DST_LOCAL (replace $PLACEHOLDER → $TARGET)"
  elif [ -f "$SRC_SAMPLE_DIR/.claude.local.json" ]; then
    echo "  [DRY] WARNING: SRC uses legacy schema ($SRC_SAMPLE_DIR/.claude.local.json); shared layer 未部署"
  else
    echo "  [DRY] [ERROR] SRC has no sample files at $SRC_SAMPLE_DIR"
  fi
else
  mkdir -p "$CLAUDE_DIR"

  if [ -f "$SAMPLE_SHARED" ] && [ -f "$SAMPLE_LOCAL" ]; then
    # New two-file schema
    cp "$SAMPLE_SHARED" "$DST_SHARED"
    echo "  [OK] shared layer → $DST_SHARED"

    cp "$SAMPLE_LOCAL" "$DST_LOCAL"
    sed "${SED_INPLACE[@]}" "s|$PLACEHOLDER|$TARGET|g" "$DST_LOCAL"
    if command -v python3 >/dev/null 2>&1; then
      python3 - "$DST_LOCAL" "$NEW_LOCAL_COMMENT" <<'PYEOF'
import json, sys
path, new_comment = sys.argv[1], sys.argv[2]
with open(path) as f: data = json.load(f)
data["_comment"] = new_comment
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PYEOF
    fi
    echo "  [OK] personal layer → $DST_LOCAL (path placeholder replaced)"
  elif [ -f "$SAMPLE_LEGACY" ]; then
    echo "  [WARN] legacy single-file schema detected; deploying to settings.local.json only."
    echo "         settings.json (shared layer) NOT deployed — run dev-rule/sample/ split first."
    cp "$SAMPLE_LEGACY" "$DST_LOCAL"
    sed "${SED_INPLACE[@]}" "s|$PLACEHOLDER|$TARGET|g" "$DST_LOCAL"
    echo "  [OK] personal layer → $DST_LOCAL (legacy schema)"
  else
    echo "  [ERROR] no sample files at $SAMPLE_DIR (expected settings.json + settings.local.json, or legacy .claude.local.json)"
    exit 1
  fi

  # 驗證:沒有 placeholder 殘留
  REMAIN=0
  [ -f "$DST_LOCAL" ] && REMAIN=$(grep -c "/Users/your-name/Desktop/MY-NEW-PROJECT" "$DST_LOCAL" || true)
  if [ "$REMAIN" -gt 0 ]; then
    echo "  [ERROR] $REMAIN 處路徑佔位符殘留於 $DST_LOCAL"
    grep -n "/Users/your-name/Desktop/MY-NEW-PROJECT" "$DST_LOCAL"
    exit 1
  fi
  echo "  [OK] 0 處路徑佔位符殘留"

  # 驗證:兩份 JSON 皆有效
  if command -v python3 >/dev/null 2>&1; then
    for f in "$DST_SHARED" "$DST_LOCAL"; do
      [ -f "$f" ] || continue
      if ! python3 -c "import json; json.load(open('$f'))" 2>/dev/null; then
        echo "  [ERROR] JSON 解析失敗:$f"
        exit 1
      fi
    done
    echo "  [OK] JSON 全部有效"
  fi
fi
echo ""

# ----------------------------------------------------------------------------
# Done — 印下一步
# ----------------------------------------------------------------------------
echo "=========================================="
echo " bootstrap 完成"
echo "=========================================="
cat <<NEXT

下一步（在 target 內跑）：

  cd $TARGET
  bash scripts/colyn-roles/install-tools.sh         # 裝工具鏈 + 自動 wire codegraph MCP
  bash scripts/colyn-roles/start.sh                 # 起 tmux roles

注意:.claude/settings.{json,local.json} 已由本腳本直接部署,
      首次 setup 不必再跑 apply-claude-settings.sh
      (該腳本用於日後 sample 變動時的再同步)。

驗證 bootstrap 成功:

  test -f .claude/settings.json       && echo "shared layer OK"
  test -f .claude/settings.local.json && echo "local layer OK"
  grep -cE "your-name|MY-NEW-PROJECT" .claude/settings.local.json   # 應為 0
  jq empty .claude/settings.json .claude/settings.local.json && echo "JSON OK"

NEXT
