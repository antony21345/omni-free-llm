#!/usr/bin/env bash
# omni-free-llm macOS 双击卸载入口（.sh 双击不会执行，只有 .command 会）
cd "$(dirname "$0")" || { echo "✖ 无法进入目录"; read -r; exit 1; }
bash ./uninstall.sh "$@"
RC=$?
echo
echo "按回车键关闭本窗口…"
read -r
exit $RC
