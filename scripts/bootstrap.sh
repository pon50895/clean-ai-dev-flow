#!/usr/bin/env bash
#
# scripts/bootstrap.sh - 把開發套件的「專案層」套進一個專案(取代舊 bootstrap-to-new-project.sh)。
#
# 用法:
#   bash scripts/bootstrap.sh <target-dir> [--dry-run]
#
# 複製的東西(只有這些):
#   template/CLAUDE.md                 -> <target>/CLAUDE.md                (專案 CLAUDE.md 範本,尖括號處待填)
#   template/kit.json                  -> <target>/.claude/kit.json         (機器 gate 與 destructive-guard 的設定)
#   template/kit.schema.json           -> <target>/.claude/kit.schema.json
#   template/.githooks/{pre-commit,pre-push} -> <target>/.githooks/        (讀 kit.json 的 git hook 骨架)
#   template/scripts/kit/*             -> <target>/scripts/kit/            (kit.mjs、lint/tsc ratchet、emoji、env drift、pins)
#   template/scripts/dependency-pins.json -> <target>/scripts/dependency-pins.json
#   dev-rule/**                        -> <target>/dev-rule/               (排除專案專屬的 LEGAL_COMPLIANCE.md、UI_VISUAL_STANDARDS.md)
#
# 刻意不複製:
#   .claude/skills/、.claude/hooks/ - skill 由 ~/.claude/skills 的 symlink 在使用者層提供,
#     hook 由 playbook 全域掛載;專案層再放一份會蓋掉使用者層版本,重新製造漂移。
#
# Hook 啟用方式:`git config core.hooksPath .githooks`(零依賴,不需要 husky / npm install)。
# 選 core.hooksPath 而非 `npx husky`:目標專案不一定是 node 專案,hook 本身是純 sh,
# 只在讀 kit.json 時用 node(找不到 node 則該段落自動略過)。
# 目標若已經用 husky,不覆蓋它的 core.hooksPath,改印手動合併說明。
#
# 行為保證:
#   - 冪等:內容相同的檔案略過;第二次執行應為 0 個新增
#   - 不覆蓋:目標已有同名但內容不同的檔案 -> 列出並跳過,不動它
#   - --dry-run:只列出會做的動作,不寫任何東西
#   - 不刪任何檔案

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_RAW=""
DRY=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY=1 ;;
    -h|--help)
      sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'
      exit 0 ;;
    -*) echo "[bootstrap] unknown option: $arg" >&2; exit 2 ;;
    *)
      if [ -n "$TARGET_RAW" ]; then echo "[bootstrap] only one <target-dir> allowed" >&2; exit 2; fi
      TARGET_RAW="$arg" ;;
  esac
done

if [ -z "$TARGET_RAW" ]; then
  echo "usage: bash scripts/bootstrap.sh <target-dir> [--dry-run]" >&2
  exit 2
fi
if [ ! -d "$TARGET_RAW" ]; then
  echo "[bootstrap] target dir does not exist: $TARGET_RAW" >&2
  exit 2
fi
TARGET="$(cd "$TARGET_RAW" && pwd)"

if [ "$TARGET" = "$SRC" ]; then
  echo "[bootstrap] target is the kit repo itself - refusing." >&2
  exit 2
fi

created=0
unchanged=0
skipped=0
SKIPPED_LIST=""

[ "$DRY" = "1" ] && echo "[bootstrap] DRY RUN - nothing will be written."
echo "[bootstrap] source: $SRC"
echo "[bootstrap] target: $TARGET"

# copy_one <src-file> <dest-relpath>
copy_one() {
  local src="$1" rel="$2" dest="$TARGET/$2"
  if [ -e "$dest" ]; then
    if cmp -s "$src" "$dest"; then
      unchanged=$((unchanged + 1))
    else
      skipped=$((skipped + 1))
      SKIPPED_LIST="${SKIPPED_LIST}  ${rel}"$'\n'
      echo "  SKIP (exists, differs): $rel"
    fi
    return 0
  fi
  created=$((created + 1))
  if [ "$DRY" = "1" ]; then
    echo "  WOULD CREATE: $rel"
  else
    mkdir -p "$(dirname "$dest")"
    cp -p "$src" "$dest"
    echo "  CREATE: $rel"
  fi
}

# copy_tree <src-dir> <dest-prefix> [exclude-basename...]
copy_tree() {
  local dir="$1" prefix="$2"; shift 2
  local f rel base ex skip
  while IFS= read -r f; do
    rel="${f#"$dir"/}"
    base="$(basename "$f")"
    skip=0
    for ex in "$@"; do [ "$base" = "$ex" ] && skip=1; done
    [ "$skip" = "1" ] && continue
    copy_one "$f" "${prefix}${rel}"
  done < <(find "$dir" -type f | sort)
}

copy_one "$SRC/template/CLAUDE.md"          "CLAUDE.md"
copy_one "$SRC/template/kit.json"           ".claude/kit.json"
copy_one "$SRC/template/kit.schema.json"    ".claude/kit.schema.json"
copy_tree "$SRC/template/.githooks"         ".githooks/"
copy_tree "$SRC/template/scripts/kit"       "scripts/kit/"
copy_one "$SRC/template/scripts/dependency-pins.json" "scripts/dependency-pins.json"
copy_tree "$SRC/dev-rule"                   "dev-rule/" LEGAL_COMPLIANCE.md UI_VISUAL_STANDARDS.md

# Make sure hooks / scripts keep their exec bit even if the source lost it.
if [ "$DRY" != "1" ]; then
  for f in "$TARGET"/.githooks/pre-commit "$TARGET"/.githooks/pre-push \
           "$TARGET"/scripts/kit/*.sh "$TARGET"/scripts/kit/*.mjs; do
    [ -f "$f" ] && chmod +x "$f"
  done
fi

# --- hook activation -------------------------------------------------------
HOOKS_MSG=""
if git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  current="$(git -C "$TARGET" config --get core.hooksPath || true)"
  if [ "$current" = ".githooks" ]; then
    HOOKS_MSG="core.hooksPath already .githooks"
  elif [ -z "$current" ]; then
    if [ "$DRY" = "1" ]; then
      HOOKS_MSG="WOULD SET core.hooksPath=.githooks"
    else
      git -C "$TARGET" config core.hooksPath .githooks
      HOOKS_MSG="SET core.hooksPath=.githooks"
    fi
  else
    HOOKS_MSG="core.hooksPath is '$current' (left untouched) - call .githooks/pre-commit and .githooks/pre-push from your existing hooks, or run: git config core.hooksPath .githooks"
  fi
else
  HOOKS_MSG="target is not a git repo - run 'git init' there, then: git config core.hooksPath .githooks"
fi

echo ""
echo "[bootstrap] summary: created=$created unchanged=$unchanged skipped=$skipped"
echo "[bootstrap] hooks: $HOOKS_MSG"
if [ "$skipped" -gt 0 ]; then
  echo "[bootstrap] skipped (target already has a different file; not overwritten):"
  printf '%s' "$SKIPPED_LIST"
fi
if [ "$created" -eq 0 ] && [ "$skipped" -eq 0 ]; then
  echo "[bootstrap] no changes."
fi
if [ "$DRY" != "1" ] && [ "$created" -gt 0 ]; then
  echo "[bootstrap] next: edit CLAUDE.md (fill <...> / (填寫)) and .claude/kit.json (commands, ratchet workspaces, modules)."
fi
