#!/usr/bin/env bash
# omni-free-llm macOS 双击入口
# macOS 双击 .sh 只会用编辑器打开，只有 .command 才会自动开终端执行。
# 双击本文件时终端的工作目录是用户主目录，所以必须先 cd 到本文件所在目录。
cd "$(dirname "$0")" || { echo "✖ 无法进入安装目录"; read -r; exit 1; }
bash ./install.sh "$@"
RC=$?
echo
if [ $RC -ne 0 ]; then echo "✖ 安装器退出，错误码 ${RC}（上面就是原因，截图发我）"; fi
# 窗口关不关由终端自己的设置决定，脚本无权控制 —— 别承诺做不到的事。
echo "安装流程结束。这个窗口不会自动关闭（终端的默认行为），按 ⌘W 即可关掉。"
echo "想让它以后自动关：终端 → 设置 → 配置文件 → Shell → 「Shell 退出时」选「若 shell 正常退出则关闭窗口」。"
read -r -p "按回车键退出脚本: "
exit $RC
