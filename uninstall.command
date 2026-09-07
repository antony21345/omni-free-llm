#!/usr/bin/env bash
# omni-free-llm macOS 双击卸载入口（.sh 双击不会执行，只有 .command 会）
cd "$(dirname "$0")" || { echo "✖ 无法进入目录"; read -r; exit 1; }
bash ./uninstall.sh "$@"
RC=$?
echo
# 窗口关不关由终端自己的设置决定，脚本无权控制 —— 别承诺做不到的事。
echo "卸载流程结束。这个窗口不会自动关闭（终端的默认行为），按 ⌘W 即可关掉。"
echo "想让它以后自动关：终端 → 设置 → 配置文件 → Shell → 「Shell 退出时」选「若 shell 正常退出则关闭窗口」。"
read -r -p "按回车键退出脚本: "
exit $RC
