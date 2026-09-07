#!/usr/bin/env bash
# omni-free-llm macOS 双击入口
# macOS 双击 .sh 只会用编辑器打开，只有 .command 才会自动开终端执行。
# 双击本文件时终端的工作目录是用户主目录，所以必须先 cd 到本文件所在目录。
cd "$(dirname "$0")" || { echo "✖ 无法进入安装目录"; read -r; exit 1; }
bash ./install.sh "$@"
RC=$?
echo
if [ $RC -ne 0 ]; then echo "✖ 安装器退出，错误码 ${RC}（上面就是原因，截图发我）"; fi
echo "按回车键关闭本窗口…"
read -r
exit $RC
