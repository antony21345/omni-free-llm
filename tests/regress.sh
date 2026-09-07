#!/usr/bin/env bash
# omni-free-llm 回归测试：自包含，从 install.mjs 现生成运行时脚本再验证，不依赖已安装的副本
cd "$(dirname "$0")/.." || exit 1
ROOT="$(pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  ok   $1"; }
no(){ FAIL=$((FAIL+1)); echo "  FAIL $1"; }

command -v node >/dev/null || { echo "需要 Node 才能跑测试：https://nodejs.org"; exit 1; }

echo "[1] 语法检查"
node --check install.mjs 2>/dev/null && ok "install.mjs" || no "install.mjs"
for f in install.sh install.command uninstall.sh uninstall.command tests/regress.sh; do
  bash -n "$f" 2>/dev/null && ok "$f" || no "$f"
done

echo "[2] 编码与行尾（Windows 脚本必须 CRLF，Unix 脚本必须 LF）"
for f in install.bat install.ps1 uninstall.bat uninstall.ps1; do
  [ "$(grep -c $'\r' "$f")" -gt 0 ] && ok "$f CRLF" || no "$f 不是 CRLF（cmd 会解析失败）"
done
for f in install.sh install.command uninstall.sh uninstall.command; do
  [ "$(grep -c $'\r' "$f")" -eq 0 ] && ok "$f LF" || no "$f 混入 CR"
done
for f in install.ps1 uninstall.ps1; do
  head -c 3 "$f" | grep -q $'\xEF\xBB\xBF' && ok "$f 有 UTF-8 BOM" || no "$f 缺 BOM（PS 5.1 中文乱码）"
done

echo "[3] 可执行位"
for f in install.command uninstall.command install.sh uninstall.sh; do
  [ -x "$f" ] && ok "$f 可执行" || no "$f 缺 x 权限"
done

echo "[4] 从 install.mjs 生成运行时脚本"
node -e "
const fs=require('fs');
import('$ROOT/install.mjs').then(m=>{
  fs.writeFileSync('$T/omni.mjs', m.OMNI_SCRIPT);
  fs.writeFileSync('$T/omni-mcp.mjs', m.MCP_SCRIPT);
  fs.writeFileSync('$T/omni-watchdog.mjs', m.WATCHDOG_SCRIPT);
  if(!m.DEFAULT_SYSTEM_PROMPT) process.exit(1);
});" 2>/dev/null && ok "三个模板导出成功" || no "模板导出失败"
for f in omni.mjs omni-mcp.mjs omni-watchdog.mjs; do
  node --check "$T/$f" 2>/dev/null && ok "生成的 $f 语法正确" || no "生成的 $f 语法错误（模板转义有问题）"
done

echo "[5] 功能冒烟（mock 上游）"
cat > "$T/srv.mjs" <<'MOCK'
import http from "node:http";
http.createServer((req,res)=>{
  if(req.url.includes("/api/health")){res.writeHead(200,{"Content-Type":"application/json"});res.end('{"ok":true}');return;}
  if(req.url.includes("/chat/completions")){
    let b="";req.on("data",c=>b+=c);
    req.on("end",()=>{const j=JSON.parse(b);
      console.error("msgs="+j.messages.length+" stream="+j.stream);
      res.writeHead(200,{"Content-Type":"text/event-stream"});
      res.write('data: {"model":"mock-m","choices":[{"delta":{"content":"## 标题\\n**粗体**回答"}}]}\n\n');
      res.write('data: {"usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15},"choices":[]}\n\n');
      res.write('data: [DONE]\n\n');res.end();});
    return;}
  res.writeHead(404);res.end();
}).listen(20999);
MOCK
cat > "$T/config.json" <<'CFG'
{"port":20999,"baseUrl":"http://localhost:20999/v1","healthUrl":"http://localhost:20999/api/health",
"apiKey":"t","model":"auto","systemPrompt":"测试","backend":"npm","startArgs":[],"os":"macos",
"dir":"t","memoryEnabled":true,"memoryTopN":3,"spinner":true}
CFG
node "$T/srv.mjs" & MOCKPID=$!
sleep 1.5
OUT=$(OMNI_DIR="$T" node "$T/omni.mjs" chat "冒烟测试问题" 2>&1)
echo "$OUT" | grep -q "粗体" && ok "chat 有返回" || no "chat 无返回"
echo "$OUT" | grep -q "输入 10 tok" && ok "token 统计" || no "token 统计缺失"
echo "$OUT" | grep -q "模型 mock-m" && ok "模型名显示" || no "模型名缺失"
echo "$OUT" | grep -q $'\x1b\[1;36m' && ok "markdown 标题上色" || no "标题未上色"
[ -f "$T/memory/index.json" ] && ok "长记忆落盘" || no "长记忆未落盘"
OMNI_DIR="$T" node "$T/omni.mjs" memory 2>&1 | grep -q "条记忆" && ok "omni memory" || no "omni memory 失败"
OMNI_DIR="$T" node "$T/omni.mjs" memory search 冒烟 2>&1 | grep -q "冒烟" && ok "omni memory search" || no "memory search 未命中"
OMNI_DIR="$T" node "$T/omni.mjs" status 2>&1 | grep -q "base_url" && ok "omni status" || no "omni status 失败"
OMNI_DIR="$T" node "$T/omni.mjs" editor 2>&1 | grep -q "base_url" && ok "omni editor" || no "omni editor 失败"
kill $MOCKPID 2>/dev/null; wait $MOCKPID 2>/dev/null

echo "[6] 卸载脚本安全性"
B=$(ls -a "$T" | wc -l)
printf '2 3\nn\nno\n' | bash uninstall.sh "$T" >/dev/null 2>&1
A=$(ls -a "$T" | wc -l)
[ "$B" = "$A" ] && ok "取消后文件数不变" || no "取消后文件被改动"
printf '2 3\nn\nno\n' | bash uninstall.sh "$T" 2>&1 | grep -q "按文件类型列出" && ok "按文件类型提示" || no "类型提示缺失"
printf '\n' | bash uninstall.sh "$T" 2>&1 | grep -q "已取消" && ok "回车即取消" || no "回车未取消"
bash uninstall.sh "$HOME" </dev/null 2>&1 | grep -q "拒绝操作" && ok "拒绝对 HOME 动手" || no "危险路径未拦截"
MENU=$(printf '\n' | bash uninstall.sh "$T" 2>&1)
echo "$MENU" | grep -q "Node.js" && ok "菜单含 Node 选项" || no "菜单缺 Node 选项"
echo "$MENU" | grep -q "npm 下载缓存" && ok "菜单含 npm 缓存选项" || no "菜单缺 npm 缓存选项"
echo "$MENU" | grep -q "Homebrew 本身" && ok "菜单说明 Homebrew 不自动删" || no "缺 Homebrew 说明"
echo "$MENU" | grep -qE '\$[A-Za-z_]' && no "菜单里有未展开的变量（变量边界问题）" || ok "菜单无未展开变量"
ALLSEL=$(printf 'a\nn\nno\n' | bash uninstall.sh "$T" 2>&1)
echo "$ALLSEL" | grep -q "卸载 Node.js" && ok "a 全选时包含 Node" || no "a 全选未包含 Node"
echo "$ALLSEL" | grep -q "已取消" && ok "a 全选后仍可取消" || no "a 全选后取消失效"
[ -f "$T/config.json" ] && ok "a 全选取消后文件未动" || no "a 全选取消后文件被删"

echo
echo "通过 $PASS 项，失败 $FAIL 项"
exit $FAIL
