#!/bin/bash
# 双击我把 Speakorb 安装到「应用程序」，然后打开。
set -e
BASE="$(cd "$(dirname "$0")" && pwd)"
SRC="$BASE/Speakorb.app"
DEST="/Applications/Speakorb.app"
if [ ! -d "$SRC" ]; then
  echo "找不到 Speakorb.app，请确认本文件与 App 在同一个磁盘映像里。"
  read -r -p "按回车退出..."
  exit 1
fi
rm -rf "$DEST"
cp -R "$SRC" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
open "$DEST"
echo "已安装到 $DEST"
read -r -p "可以关闭这个窗口了，按回车退出..."
