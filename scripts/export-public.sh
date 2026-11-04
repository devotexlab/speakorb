#!/usr/bin/env bash
# 把这个仓库导出成一份可以公开的干净副本：新目录、新的 git 历史、只含公开内容。
# 不会推送任何东西，也不会改动当前仓库。
#
#   ./scripts/export-public.sh ../speakorb
#
# 不导出：docs/planning/（内部规划和参考资料）、dist/（安装包）、PROGRESS.md（内部进度）。
set -euo pipefail
cd "$(dirname "$0")/.."

TARGET="${1:-}"
if [ -z "${TARGET}" ]; then
  echo "用法：$0 <目标目录>" >&2
  exit 1
fi
if [ -e "${TARGET}" ] && [ -n "$(ls -A "${TARGET}" 2>/dev/null)" ]; then
  echo "目标目录不是空的：${TARGET}" >&2
  exit 1
fi

EXCLUDE='^(docs/planning/|dist/|PROGRESS\.md$)'

echo "==> 复制公开文件"
mkdir -p "${TARGET}"
git ls-files --cached --others --exclude-standard \
  | grep -vE "${EXCLUDE}" \
  | while IFS= read -r f; do
      [ -f "$f" ] || continue   # 已删除但还没提交的文件
      mkdir -p "${TARGET}/$(dirname "$f")"
      cp -p "$f" "${TARGET}/$f"
    done

echo "==> 检查不该公开的内容"
cd "${TARGET}"
fail=0
# 逆向、私人项目、本机路径：一处都不能有。
if grep -rnIiE --exclude=export-public.sh 'typeless|ghidra|mitmproxy|webcrack|反编译|逆向|抓包|family-gateway|familygw|/Users/[a-z]' . ; then
  echo "!! 上面这些内容不应该公开" >&2
  fail=1
fi
# 钥匙、私钥。
if grep -rnIE --exclude=export-public.sh '(AIza[0-9A-Za-z_-]{30,}|sk-[A-Za-z0-9]{32,}|sk-or-v1-[a-f0-9]{20,}|ghp_[A-Za-z0-9]{30,}|BEGIN (RSA|OPENSSH|EC) PRIVATE)' . ; then
  echo "!! 疑似钥匙" >&2
  fail=1
fi
# 旧代号只允许出现在数据迁移、改名记录里。
if grep -rnI --exclude=export-public.sh 'Talktype\|talktype' . | grep -vE '^\./(Sources/SpeakorbApp/LegacyMigration\.swift|CHANGELOG\.md|docs/naming\.md|docs/architecture\.md):' ; then
  echo "!! 旧代号 Talktype 还没改完" >&2
  fail=1
fi
if [ "${fail}" -ne 0 ]; then
  echo "导出的副本在 ${TARGET}，但检查没通过，先别公开。" >&2
  exit 1
fi

echo "==> 新建 git 仓库（不提交、不推送）"
git init -q -b main
git add -A

echo
echo "完成：${TARGET}"
echo "下一步（都由你来做）："
echo "  1. cd ${TARGET} && swift build && swift test"
echo "  2. 看一遍 git status，确认没有不想公开的文件"
echo "  3. git commit -s -m \"Initial public release\""
echo "  4. 在 GitHub 建仓库后：git remote add origin <地址> && git push -u origin main"
