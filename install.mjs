#!/usr/bin/env node
/**
 * omni-free-llm —— 免费 AI 一键安装器（跨平台、交互式、零私钥、傻瓜式）
 *
 * 一条命令装好，交互式引导：
 *   ① 选择安装/存储路径
 *   ② 选择「匿名免费池」还是「个人 API」（个人 API 一步步引导注册并提示保存）
 *   ③ 接入后可选装「关终端自动关」看门狗（按操作系统给方案）
 *   ④ 可选装 MCP（让编辑器里的 AI 自助管理免费池）
 *   ⑤ 提示接入编辑器（终端默认直接可用）
 *
 * 支持：Windows / macOS / Linux（含麒麟、统信 UOS、openEuler、Deepin 等国产系统）。
 */
import { spawn, execSync } from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import * as crypto from "node:crypto";
import { createInterface } from "node:readline";

const PORT = 20128;
const BASE = "http://localhost:" + PORT;
const FREE_LIST_URL = "https://raw.githubusercontent.com/mnfst/awesome-free-llm-apis/main/data.json";
// 默认回答风格：写进 config.json 的 systemPrompt，用户随时可改，不必动代码
export const DEFAULT_SYSTEM_PROMPT = [
  "你是终端里的 AI 助手，回答会被渲染成带颜色的 Markdown。请遵守：",
  "1. 先给结论，再给原因；不要复述问题、不要客套开场白、不要总结陈词。",
  "2. 回复尽量短：分点作答，每点一行，默认 10 行以内，除非用户明确要求展开。",
  "3. 给代码时用最少的代码实现需求：不加没要求的功能、不做顺手重构、不写样板和冗余注释；多个方案时优先最轻量的那个。",
  "4. 用 ## 小标题划分阶段，用 **粗体** 标出关键词，命令和代码用反引号或三反引号包裹。",
  "5. 用中文回答。",
].join("\n");

// ---- 内置免费 AI 清单（零私钥，仅注册 URL；id 需是 oMNIROUTE 认识的 provider id）----
const FREE_KEYS = [
  { id: "zai", name: "智谱 Z AI（GLM）", note: "国产·国内直连·永久免费·无需 VPN（大陆首选）", url: "https://open.bigmodel.cn" },
  { id: "groq", name: "Groq", note: "速度极快·每月约 1500 万 tokens 免费", url: "https://console.groq.com/keys" },
  { id: "deepseek", name: "DeepSeek", note: "国产·便宜·国内直连（新用户有免费额度）", url: "https://platform.deepseek.com" },
  { id: "logfare", name: "Logfare", note: "无速率限制（请求会被记录做研究）", url: "https://logfare.ai/register" },
  { id: "gemini", name: "Google Gemini", note: "免费 tier（中国大陆不可用）", url: "https://aistudio.google.com/apikey" },
];

// ---- 颜色 ----
const G = "\x1b[32m", B = "\x1b[36m", Y = "\x1b[33m", R = "\x1b[31m", D = "\x1b[0m", BD = "\x1b[1m";

// 装之前先看磁盘够不够，别写进去 2G 才失败。statfsSync 是 Node 自带的，跨平台。
const NEED_GB = 3; // omniroute 实测装完约 2.3G，留一点余量
function freeGB(p) {
  try { const st = fs.statfsSync(p); return (st.bavail * st.bsize) / 1073741824; } catch { return null; }
}
// ---- OS 检测 ----
function detectOS() {
  const p = process.platform;
  if (p === "win32") return { id: "windows", name: "Windows" };
  if (p === "darwin") return { id: "macos", name: "macOS" };
  if (p === "linux") {
    let rel = "";
    try { rel = fs.readFileSync("/etc/os-release", "utf8"); } catch {}
    const pretty = rel.match(/^PRETTY_NAME="?([^"\n]+)"?/m);
    const idm = rel.match(/^ID="?([^"\n]+)"?/m);
    return { id: "linux", name: pretty ? pretty[1] : "Linux", distro: idm ? idm[1] : "linux" };
  }
  return { id: p, name: p };
}
const OS = detectOS();

// ---- 交互式提问 ----
let _rl = null;
function ask(q) {
  if (!_rl) _rl = createInterface({ input: process.stdin, output: process.stdout });
  return new Promise((r) => _rl.question(q, (a) => r(a.trim())));
}
function closePrompt() { if (_rl) _rl.close(); }

// ---- 工具 ----
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const sh = (cmd, opts = {}) => { try { return execSync(cmd, { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"], ...opts }).trim(); } catch { return ""; } };
// run: 只关心成败（看退出码，不看 stdout），且把输出直接打到窗口 —— 长时间安装不能一片死寂
const run = (cmd, opts = {}) => { try { execSync(cmd, { stdio: "inherit", ...opts }); return true; } catch { return false; } };
async function health() { try { const r = await fetch(BASE + "/api/health", { signal: AbortSignal.timeout(2500) }); return r.ok; } catch { return false; } }
async function waitHealth(ms) { const t = Date.now(); while (Date.now() - t < ms) { if (await health()) return true; await sleep(3000); } return false; }
async function api(p, { method = "GET", body, cookie } = {}) {
  const res = await fetch(BASE + p, { method, headers: { "Content-Type": "application/json", ...(cookie ? { Cookie: cookie } : {}) }, body: body ? JSON.stringify(body) : undefined });
  let j = null; try { j = await res.json(); } catch {}
  return { status: res.status, ok: res.ok, body: j, headers: res.headers };
}
function cookieOf(h) {
  try { const g = h.getSetCookie ? h.getSetCookie() : []; const s = h.get("set-cookie"); const a = g.length ? g : (s ? [s] : []); return a.map((c) => c.split(";")[0]).join("; "); } catch { return ""; }
}

// ---- 后端 ----
const nodeOk = () => { const [m, n] = process.versions.node.split(".").map(Number); return (m === 22 && n >= 22) || (m >= 24 && m < 27); };
const npmRoot = () => sh("npm root -g");
// 注意：npm 发布包里没有 scripts/dev/run-next.mjs（那是开发仓库的路径），正式入口是 bin/omniroute.mjs
const omniCli = () => { const p = path.join(npmRoot(), "omniroute", "bin", "omniroute.mjs"); return fs.existsSync(p) ? p : ""; };
const serveArgs = () => [omniCli(), "serve", "--port", String(PORT), "--no-open"];

async function ensureBackend(password, docker) {
  if (await health()) return true;
  if (docker) {
    sh("docker rm -f omniroute");
    sh(`docker run -d --name omniroute --restart unless-stopped -p ${PORT}:${PORT} -e INITIAL_PASSWORD=${password} diegosouzapw/omniroute:latest`, { timeout: 120000 });
  } else {
    if (!omniCli()) {
      console.log(`${B}ℹ${D} 首次安装官方 npm 包 omniroute（1.2G 左右，视网速 3-15 分钟，下面是 npm 的实时进度）…`);
      if (!run("npm install -g omniroute --registry=https://registry.npmmirror.com --no-audit --no-fund", { timeout: 600000 })) {
        console.log(`${Y}⚠${D} 镜像源安装失败，改用官方源重试（可能更慢）…`);
        run("npm install -g omniroute --no-audit --no-fund", { timeout: 600000 });
      }
    }
    if (!omniCli()) { console.error(`${R}✖ omniroute 安装后仍找不到 bin/omniroute.mjs${D}`); return false; }
    const child = spawn(process.execPath, ["--max-old-space-size=4096", ...serveArgs()], { detached: true, stdio: "ignore", env: { ...process.env, INITIAL_PASSWORD: password, PORT: String(PORT) } });
    child.unref();
  }
  return await waitHealth(180000);
}

// ---- 管理 API ----
async function login(password) {
  const r = await api("/api/auth/login", { method: "POST", body: { password } });
  const c = cookieOf(r.headers);
  if (!r.ok || !c) throw new Error("登录失败");
  return c;
}
async function setupFree(cookie) {
  const list = await api("/api/providers/free-onboarding", { cookie });
  const ids = ((list.body && list.body.providers) || []).map((p) => p.id || p.provider || p.slug).filter(Boolean);
  if (ids.length === 0) return 0;
  await api("/api/providers/free-onboarding", { method: "POST", cookie, body: { providerIds: ids.slice(0, 20), confirmed: true } });
  await api("/api/settings", { method: "PATCH", cookie, body: { freeAccessPolicy: "off", noAuthFallbackDisabledProviders: [] } });
  return ids.length;
}
async function createKey(cookie) {
  const r = await api("/api/keys", { method: "POST", cookie, body: { name: "omni-cli", modelAccessMode: "all" } });
  if (!r.ok || !r.body || !r.body.key) throw new Error("创建 key 失败");
  return r.body.key;
}
async function addKey(cookie, spec) {
  const [provider, key] = spec.split(":");
  if (!provider || !key) return false;
  const r = await api("/api/providers", { method: "POST", cookie, body: { provider, apiKey: key, name: provider } });
  const id = r.body && (r.body.id || r.body.connectionId);
  if (!id) return false;
  await api(`/api/providers/${id}`, { method: "PATCH", cookie, body: { isActive: true } });
  await api(`/api/providers/${id}/sync-models`, { method: "POST", cookie });
  return true;
}

// ---- 自动检索最新免费 AI（远程清单，失败用内置）----
async function fetchFreeList() {
  try {
    const r = await fetch(FREE_LIST_URL, { signal: AbortSignal.timeout(8000) });
    const j = await r.json();
    const ps = (j.providers || []).filter((p) => p.category === "provider_api");
    if (ps.length) return ps.map((p) => ({ id: p.name.toLowerCase().replace(/[^a-z0-9]+/g, "-"), name: p.name, note: (p.description || "").slice(0, 60), url: p.url || "" }));
  } catch {}
  return FREE_KEYS;
}

// ---- 个人 API 逐步引导 ----
async function guidePersonalKeys(cookie) {
  console.log(`\n${BD}${B}开始接入个人免费 API${D}（按提示一个个来，随时输入 0 结束）`);
  const list = await fetchFreeList();
  let added = 0;
  for (let i = 0; i < list.length; i++) {
    const f = list[i];
    console.log(`\n  ${Y}[${i + 1}/${list.length}]${D} ${G}${f.name}${D} —— ${f.note}`);
    console.log(`      ${B}注册拿 key：${f.url}${D}`);
    const ans = await ask(`      粘贴 ${f.name} 的 key（回车跳过 / 输入 0 结束）：`);
    if (ans === "0") break;
    if (!ans) continue;
    if (await addKey(cookie, `${f.id}:${ans}`)) { added++; console.log(`      ${G}✔${D} 已接入。${Y}请务必自己妥善保存好这个 key！${D}`); }
    else console.log(`      ${Y}⚠${D} 接入失败（provider id 可能不匹配，可稍后在 dashboard 手动接入）`);
  }
  console.log(`\n${G}✔${D} 个人 API 接入完成（共 ${added} 个）`);
}

// ---- 内嵌运行时脚本（装到用户所选目录）----
export const OMNI_SCRIPT = `#!/usr/bin/env node
// omni — 免费 AI 对话 + 管理。子命令: up/down/chat/status/key/free-list/mcp/editor
import { spawn, execSync } from "node:child_process";
import { readFileSync, writeFileSync, existsSync, appendFileSync, mkdirSync } from "node:fs";
import { homedir } from "node:os";
const DIR = process.env.OMNI_DIR || homedir().replace(/\\\\/g, "/") + "/.omniroute";
const CFG = JSON.parse(readFileSync(DIR + "/config.json", "utf8"));
const cmd = process.argv[2] || "help", rest = process.argv.slice(3);
const G = "\\x1b[32m", B = "\\x1b[36m", Y = "\\x1b[33m", D = "\\x1b[0m";
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const sh = (c) => { try { return execSync(c, { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim(); } catch { return ""; } };
async function health() { try { const r = await fetch(CFG.healthUrl, { signal: AbortSignal.timeout(2500) }); return r.ok; } catch { return false; } }
async function up() {
  if (await health()) return true;
  if (CFG.backend === "docker") { sh("docker start omniroute 2>/dev/null || docker run -d --name omniroute --restart unless-stopped -p " + CFG.port + ":" + CFG.port + " -e INITIAL_PASSWORD=" + CFG.adminPassword + " diegosouzapw/omniroute:latest"); }
  else {
    const c = spawn(process.execPath, ["--max-old-space-size=4096"].concat(CFG.startArgs || []), { detached: true, stdio: "ignore", env: { ...process.env, INITIAL_PASSWORD: CFG.adminPassword, PORT: String(CFG.port) } });
    c.unref(); try { writeFileSync(DIR + "/.pid", String(c.pid)); } catch {}
  }
  const t = Date.now(); while (Date.now() - t < 180000) { if (await health()) return true; await sleep(3000); }
  return false;
}
function down() {
  if (CFG.backend === "docker") { sh("docker rm -f omniroute"); console.log("✅ 已关闭"); return; }
  // 首选 omniroute 自带的 stop；再按平台兜底（原来只有 Windows 的 netstat/taskkill，Mac/Linux 上等于没关）
  const cli = (CFG.startArgs || [])[0];
  if (cli) sh('"' + process.execPath + '" "' + cli + '" stop');
  if (CFG.os === "windows") {
    try { const out = sh('netstat -ano | findstr ":' + CFG.port + '.*LISTENING"'); for (const l of out.split("\\n")) { const m = l.match(/(\\d+)\\s*$/); if (m) sh("taskkill /F /PID " + m[1] + " /T"); } } catch {}
  } else {
    const pids = sh("lsof -ti tcp:" + CFG.port);
    if (pids) sh("kill " + pids.split("\\n").join(" "));
  }
  console.log("✅ 已关闭");
}
// 极简 Markdown -> ANSI：按行渲染（标记基本不跨行），既保留流式又能上色
function makeRenderer() {
  const H = "\\x1b[1;36m", BOLD = "\\x1b[1m", CODE = "\\x1b[33m", LI = "\\x1b[36m", BLK = "\\x1b[90m", RS = "\\x1b[0m";
  let inBlock = false;
  return (line) => {
    if (/^\\s*\`\`\`/.test(line)) { inBlock = !inBlock; return BLK + line + RS; }
    if (inBlock) return BLK + line + RS;
    if (/^\\s*#{1,6}\\s/.test(line)) return H + line.replace(/^\\s*#+\\s*/, "") + RS;
    let t = line;
    t = t.replace(/\\*\\*(.+?)\\*\\*/g, BOLD + "$1" + RS);
    t = t.replace(/\`([^\`]+)\`/g, CODE + "$1" + RS);
    t = t.replace(/^(\\s*)[-*+]\\s+/, "$1" + LI + "• " + RS);
    t = t.replace(/^(\\s*)(\\d+\\.)\\s+/, "$1" + LI + "$2" + RS + " ");
    return t;
  };
}
let currentAbort = null;   // 当前进行中的请求，:q / Ctrl+C 要能真正掐断它
// ---- 长记忆：按天分文件保存，关键词索引，检索时只注入相关片段（不是全部历史）以省 token ----
const MEM_DIR = DIR + "/memory";
const MEM_INDEX = MEM_DIR + "/index.json";
const memLoad = () => { try { return JSON.parse(readFileSync(MEM_INDEX, "utf8")); } catch { return { items: [] }; } };
const memSave = (idx) => { mkdirSync(MEM_DIR, { recursive: true }); writeFileSync(MEM_INDEX, JSON.stringify(idx, null, 2)); };
// 规则提取关键词（零成本、瞬时）：英文单词 + 中文 2-4 字片段，按词频取前 12 个
function memKeywords(text) {
  const en = (String(text).toLowerCase().match(/[a-z0-9_.-]{3,}/g) || []);
  // 滑窗 n-gram：贪婪连续切分对起始位置敏感，换个问法就匹配不上；滑窗保证「数据库」「索引」都在
  const zh = [];
  for (const seg of String(text).replace(/[^\\u4e00-\\u9fa5]+/g, " ").split(" ")) {
    for (let n = 2; n <= 4; n++) for (let i = 0; i + n <= seg.length; i++) zh.push(seg.slice(i, i + n));
  }
  const freq = {};
  for (const w of en.concat(zh)) freq[w] = (freq[w] || 0) + 1;
  return Object.keys(freq).sort((a, b) => (freq[b] - freq[a]) || (b.length - a.length)).slice(0, 24);
}
function memAppend(userText, aiText) {
  try {
    mkdirSync(MEM_DIR, { recursive: true });
    const now = new Date();
    const day = now.toISOString().slice(0, 10);
    const id = day + "-" + now.getTime().toString(36);
    appendFileSync(MEM_DIR + "/" + day + ".md", "\\n## " + id + "  " + now.toLocaleString() + "\\n\\n**问：** " + userText + "\\n\\n**答：** " + aiText + "\\n");
    const idx = memLoad();
    idx.items.push({ id: id, file: day + ".md", time: now.toISOString(), keywords: memKeywords(userText + " " + aiText), summary: String(userText).slice(0, 60) });
    memSave(idx);
  } catch {}
}
// 检索：关键词命中数为主、时间新近度为辅打分，取前 N 条
function memSearch(query, topN) {
  const idx = memLoad();
  if (!idx.items.length) return [];
  const qk = memKeywords(query);
  if (!qk.length) return [];
  const now = Date.now();
  return idx.items
    .map((it) => {
      const hit = (it.keywords || []).filter((k) => qk.some((q) => k.indexOf(q) >= 0 || q.indexOf(k) >= 0)).length;
      const ageDays = (now - new Date(it.time).getTime()) / 86400000;
      return { it: it, score: hit * 10 - Math.min(ageDays, 30) * 0.1 };
    })
    .filter((x) => x.score > 0)
    .sort((a, b) => b.score - a.score)
    .slice(0, topN)
    .map((x) => x.it);
}
function memRead(item) {
  try {
    const txt = readFileSync(MEM_DIR + "/" + item.file, "utf8");
    const i = txt.indexOf("## " + item.id);
    if (i < 0) return "";
    const j = txt.indexOf("\\n## ", i + 1);
    return txt.slice(i, j < 0 ? undefined : j).trim();
  } catch { return ""; }
}
// 关系图：关键词 -> 涉及它的对话片段，输出 mermaid（只给你看，不喂给 AI）
function memGraph() {
  const idx = memLoad();
  const by = {};
  for (const it of idx.items) for (const k of (it.keywords || []).slice(0, 3)) (by[k] = by[k] || []).push(it.id);
  const keys = Object.keys(by).filter((k) => by[k].length > 1).sort((a, b) => by[b].length - by[a].length).slice(0, 20);
  if (!keys.length) return "（还没有足够的记忆生成关系图，多聊几轮再看）";
  let out = "graph LR\\n";
  for (const k of keys) for (const id of by[k].slice(0, 5)) out += '  "' + k + '" --> "' + id + '"\\n';
  return out;
}
// ---- 把上游的失败翻译成人话（状态码 + Retry-After/RateLimit 头 + 响应体里的 error.message）----
function fmtWait(sec) {
  if (!isFinite(sec) || sec <= 0) return "";
  if (sec < 60) return Math.ceil(sec) + " 秒后";
  if (sec < 3600) return Math.ceil(sec / 60) + " 分钟后";
  if (sec < 86400) return (sec / 3600).toFixed(1) + " 小时后";
  return (sec / 86400).toFixed(1) + " 天后";
}
// 重置时间可能是秒数、unix 时间戳、HTTP 日期或 "1h2m3s" 这类写法
function parseReset(v) {
  const t = String(v || "").trim();
  if (!t) return null;
  if (/^\\d+(\\.\\d+)?$/.test(t)) { const n = Number(t); return n > 1e9 ? (n * 1000 - Date.now()) / 1000 : n; }
  const m = t.match(/^(?:(\\d+)h)?(?:(\\d+)m)?(?:([\\d.]+)s)?$/);
  if (m && (m[1] || m[2] || m[3])) return Number(m[1] || 0) * 3600 + Number(m[2] || 0) * 60 + Number(m[3] || 0);
  const d = new Date(t).getTime();
  if (!isNaN(d)) return (d - Date.now()) / 1000;
  return null;
}
function explainHttp(status, headers, bodyText) {
  let detail = "";
  try {
    const j = JSON.parse(bodyText);
    detail = (j.error && (j.error.message || j.error.type || j.error.code)) || j.message || "";
  } catch { detail = String(bodyText || "").replace(/\\s+/g, " ").slice(0, 100); }
  let sec = null;
  try {
    sec = parseReset(headers.get("retry-after"));
    if (sec == null) sec = parseReset(headers.get("x-ratelimit-reset-tokens") || headers.get("x-ratelimit-reset-requests") || headers.get("x-ratelimit-reset"));
  } catch {}
  const when = sec != null ? fmtWait(sec) : "";
  const base = status === 429 ? ("额度已用完或触发限流" + (when ? "，约 " + when + "恢复" : "，未告知恢复时间"))
    : (status === 401 || status === 403) ? "认证失败：key 无效、已过期或没有该模型权限"
    : status === 402 ? "余额/免费额度不足"
    : status === 404 ? "模型不存在或未接入"
    : status === 400 ? "请求被拒绝（参数或内容不被接受）"
    : status >= 500 ? "上游服务故障" + (when ? "，约 " + when + "恢复" : "")
    : "HTTP " + status;
  return base + (detail ? "（" + String(detail).slice(0, 100) + "）" : "");
}
// 思考动画：从回车到第一个字之间给出明确反馈，并显示已等待秒数；非 TTY 不画动画
function startSpinner(label) {
  // config.json 里设 "spinner": false 可完全关掉转圈（怀疑终端渲染出问题时用来排除变量）
  if (!process.stdout.isTTY || CFG.spinner === false) return () => {};
  const F = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];
  let i = 0, timer = null, drawn = false;
  const t0 = Date.now();
  // 延迟 400ms 才开始转（快的请求根本不画），间隔 200ms —— 高频重绘会一直压着终端的 tty-io 线程
  const delay = setTimeout(() => {
    timer = setInterval(() => {
      drawn = true;
      const sec = ((Date.now() - t0) / 1000).toFixed(1);
      process.stdout.write("\\r\\x1b[36m" + F[i++ % F.length] + "\\x1b[0m " + label + " " + sec + "s");
    }, 200);
  }, 400);
  return () => {
    clearTimeout(delay);
    if (timer) clearInterval(timer);
    if (drawn) process.stdout.write("\\r\\x1b[K");
  };
}
// 流式输出：逐行上色打印，不再等整段生成完；出错抛异常交给调用方，REPL 不会被一次限流踢出去
async function chat(messages) {
  const t0 = Date.now();
  const stop = startSpinner("已收到，正在思考…");
  try { return await chatInner(messages, stop, t0); } finally { stop(); currentAbort = null; }
}
async function chatInner(messages, stop, t0) {
  if (!(await up())) throw new Error("服务启动超时");
  const msgs = CFG.systemPrompt ? [{ role: "system", content: CFG.systemPrompt }].concat(messages) : messages.slice();
  // 只注入检索到的相关片段，而不是把全部历史都带上 —— 这是省 token 的关键
  const lastUser = messages.slice().reverse().find((m) => m.role === "user");
  if (lastUser && CFG.memoryEnabled !== false) {
    const hits = memSearch(lastUser.content, CFG.memoryTopN || 3).map(memRead).filter(Boolean);
    if (hits.length) msgs.splice(CFG.systemPrompt ? 1 : 0, 0, { role: "system", content: "以下是相关的历史对话片段（供参考，不必复述）：\\n\\n" + hits.join("\\n\\n---\\n\\n") });
  }
  const render = makeRenderer();
  const st = { full: "", pend: "", usage: null, models: [] };
  const MAX_TRY = 3;
  let lastErr = null;
  const fails = [];
  for (let attempt = 0; attempt < MAX_TRY; attempt++) {
    // 断点接手：把已生成的半截带给接手的模型，让它续写而不是从头再来
    const send = st.full ? msgs.concat([
      { role: "assistant", content: st.full },
      { role: "user", content: "（上一条回答因上游中断而截断，请紧接着截断处继续写完，不要重复已经说过的内容，也不要重新开头。）" },
    ]) : msgs;
    try {
      await readStream(send, st, render, stop);
      if (st.full) break;
      lastErr = new Error("上游接受了请求但没有返回任何内容");
      fails.push((st.models[st.models.length - 1] || "上游") + "：" + lastErr.message);
    } catch (e) {
      lastErr = e;
      const who = st.models[st.models.length - 1] || "上游";
      fails.push(who + "：" + (e.message || String(e)));
    }
    if (attempt < MAX_TRY - 1) {
      stop();
      const why = lastErr && lastErr.message ? "（" + lastErr.message.split("（")[0].slice(0, 40) + "）" : "";
      process.stdout.write("\\x1b[33m⚠ " + (st.full ? "上游中断" + why + "，正在切换并接手续写…" : "当前免费源不可用" + why + "，正在换一个重试…") + "\\x1b[0m\\n");
    }
  }
  if (st.pend) { process.stdout.write(render(st.pend) + "\\n"); st.pend = ""; }
  else process.stdout.write("\\n");
  if (!st.full) {
    const uniq = fails.filter((x, i) => fails.indexOf(x) === i);
    const lines = uniq.length ? uniq.map((x) => "  • " + x).join("\\n") : "  • " + ((lastErr && lastErr.message) || "未知原因");
    throw new Error("所有免费源当前都用不了，逐个原因如下：\\n" + lines +
      "\\n\\n  接一个个人免费 key 会稳定很多（无需信用卡）：" +
      "\\n    omni key groq <你的key>   注册 https://console.groq.com/keys（最快）" +
      "\\n    omni key zai  <你的key>   注册 https://open.bigmodel.cn（国内直连免 VPN）" +
      "\\n  也可以先 omni free-list 看看还有哪些免费源可用。");
  }
  const sec = ((Date.now() - t0) / 1000).toFixed(1);
  const m = st.models.length ? " · 模型 " + st.models.join(" → ") : "";
  const u = st.usage ? " · 输入 " + (st.usage.prompt_tokens || 0) + " tok · 输出 " + (st.usage.completion_tokens || 0) + " tok · 共 " + (st.usage.total_tokens || 0) + " tok"
                     : " · 输出 " + st.full.length + " 字（上游未返回 token 统计）";
  process.stdout.write("\\x1b[90m⏱ " + sec + "s" + m + u + "\\x1b[0m\\n");
  return st.full;
}
// 读一次流式响应，边收边渲染；把状态累积到 st 上，断线重连时不丢已生成的内容
async function readStream(sendMsgs, st, render, stop) {
  currentAbort = new AbortController();
  const r = await fetch(CFG.baseUrl + "/chat/completions", { method: "POST", headers: { "Content-Type": "application/json", Authorization: "Bearer " + CFG.apiKey }, body: JSON.stringify({ model: process.env.OMNI_MODEL || CFG.model || "auto", messages: sendMsgs, stream: true, stream_options: { include_usage: true } }), signal: currentAbort.signal });
  if (!r.ok) { let t = ""; try { t = await r.text(); } catch {} throw new Error(explainHttp(r.status, r.headers, t)); }
  const dec = new TextDecoder();
  let buf = "";
  for await (const chunk of r.body) {
    buf += dec.decode(chunk, { stream: true });
    const lines = buf.split("\\n");
    buf = lines.pop();
    for (const line of lines) {
      const s2 = line.trim();
      if (!s2.startsWith("data:")) continue;
      const d = s2.slice(5).trim();
      if (!d || d === "[DONE]") continue;
      try {
        const j = JSON.parse(d);
        if (j.usage) st.usage = j.usage;
        if (j.model && st.models[st.models.length - 1] !== j.model) st.models.push(j.model);
        const c = j.choices && j.choices[0] && j.choices[0].delta && j.choices[0].delta.content;
        if (c) {
          if (!st.full) stop();
          st.full += c; st.pend += c;
          const outs = st.pend.split("\\n");
          st.pend = outs.pop();
          for (const ln of outs) process.stdout.write(render(ln) + "\\n");
        }
      } catch {}
    }
  }
}
async function api(p, { method = "GET", body, cookie } = {}) { const res = await fetch("http://localhost:" + CFG.port + p, { method, headers: { "Content-Type": "application/json", ...(cookie ? { Cookie: cookie } : {}) }, body: body ? JSON.stringify(body) : undefined }); let j = null; try { j = await res.json(); } catch {} return { status: res.status, ok: res.ok, body: j, headers: res.headers }; }
function cookieOf(h) { try { const g = h.getSetCookie ? h.getSetCookie() : []; const s = h.get("set-cookie"); const a = g.length ? g : (s ? [s] : []); return a.map((c) => c.split(";")[0]).join("; "); } catch { return ""; } }
async function addKey(provider, key) {
  const lg = await api("/api/auth/login", { method: "POST", body: { password: CFG.adminPassword } });
  const cookie = cookieOf(lg.headers); if (!cookie) { console.error("✖ 登录失败"); return; }
  const r = await api("/api/providers", { method: "POST", cookie, body: { provider, apiKey: key, name: provider } });
  const id = r.body && (r.body.id || r.body.connectionId);
  if (!id) { console.error("✖ 接入失败 " + r.status); return; }
  await api("/api/providers/" + id, { method: "PATCH", cookie, body: { isActive: true } });
  await api("/api/providers/" + id + "/sync-models", { method: "POST", cookie });
  console.log("✅ 已接入 " + provider + "。请妥善保存你的 key！想默认用它：改 " + DIR + "/config.json 的 model");
}
async function freeList() {
  const builtin = ${JSON.stringify(FREE_KEYS)};
  console.log("\\n" + B + "内置免费 AI（已验证，可直接 omni key 接入）：" + D);
  for (const f of builtin) console.log("  " + G + "●" + D + " " + f.name + " —— " + f.note + "\\n    注册：" + B + f.url + D + "\\n    接入：omni key " + f.id + " <你的key>");
  try {
    const r = await fetch("${FREE_LIST_URL}", { signal: AbortSignal.timeout(8000) });
    const j = await r.json();
    const ps = (j.providers || []).filter((p) => p.category === "provider_api");
    console.log("\\n" + B + "最新免费 AI（来自 awesome-free-llm-apis，实时检索，" + j.lastUpdated + "）：" + D);
    for (const p of ps) console.log("  " + G + "●" + D + " " + p.name + " —— " + (p.description || "").slice(0, 70) + "\\n    注册：" + B + (p.url || "") + D);
    console.log("\\n" + Y + "提示：" + D + "上面新的免费 AI 若不在内置清单，可到 dashboard (http://localhost:" + CFG.port + ") 手动接入，或告诉我 provider id。");
  } catch { console.log("\\n" + Y + "（联网检索失败，仅显示内置清单）" + D); }
}
async function mcpGuide() {
  console.log("\\n" + B + "MCP 接入（让编辑器里的 AI 自助管理免费池）：" + D);
  console.log("  " + CFG.dir + "/omni-mcp.mjs 已提供 MCP 工具（omni_chat/omni_status/omni_up/omni_down/omni_free_list）");
  console.log("  在 Cursor / Claude Desktop / Cline 的 MCP 配置里添加：");
  console.log('  { "mcpServers": { "omni-free-llm": { "command": "' + process.execPath + '", "args": ["' + CFG.dir + '/omni-mcp.mjs"] } } }');
}
async function editorGuide() {
  console.log("\\n" + B + "接入编辑器（任意 OpenAI 兼容客户端通用）：" + D);
  console.log("  base_url = " + CFG.baseUrl + "\\n  api_key  = " + CFG.apiKey + "\\n  model    = " + CFG.model);
  console.log("  • VS Code：装 Cline 或 Continue 插件，选 OpenAI Compatible，填上面三项");
  console.log("  • PyCharm/IDEA：装 Continue 插件，填上面三项");
  console.log("  • 终端已可直接用：omni chat \\"问题\\"");
}
if (cmd === "up") { console.log((await up()) ? "✅ 已就绪 " + CFG.healthUrl : "✖ 启动超时"); }
else if (cmd === "down") down();
else if (cmd === "chat") {
  const useStdin = !process.stdin.isTTY && rest.length === 0;
  const once = async (text) => { try { const rep = await chat([{ role: "user", content: text }]); memAppend(text, rep); } catch (e) { console.error("✖ " + e.message); process.exit(1); } };
  if (rest.length) await once(rest.join(" "));
  else if (useStdin) { let b = ""; process.stdin.setEncoding("utf8"); process.stdin.on("data", (c) => b += c); process.stdin.on("end", () => once(b.trim())); }
  else {
    console.log("🤖 omni chat（model=" + CFG.model + "）。:q 或 Ctrl+C 退出（回答中也能退），:new 清空对话历史。");
    const rl = (await import("node:readline")).createInterface({ input: process.stdin, output: process.stdout, prompt: "❯ " });
    const history = [];      // 多轮上下文：把历史一并发给模型，AI 才记得上文
    const MAX_TURNS = 20;    // 只保留最近 20 轮，防止上下文无限膨胀烧掉免费额度
    let busy = false;        // 回答期间忽略输入，避免流式输出和键入交错
    // :q 必须优先于 busy 判断，否则 AI 回答期间（免费源可能十几秒）根本退不出去
    const quit = () => {
      try { if (currentAbort) currentAbort.abort(); } catch {}
      try { rl.close(); } catch {}
      process.stdout.write("\\n已退出。\\n");
      process.exit(0);
    };
    rl.on("SIGINT", quit);
    rl.prompt();
    rl.on("line", async (l) => {
      const t = l.trim();
      if (t === ":q") { quit(); return; }
      if (busy) { process.stdout.write("\\x1b[90m（正在回答中…要中断就输入 :q 或按 Ctrl+C）\\x1b[0m\\n"); return; }
      if (t === ":new") { history.length = 0; console.log("（已清空对话历史）"); rl.prompt(); return; }
      if (!t) { rl.prompt(); return; }
      busy = true;
      history.push({ role: "user", content: t });
      try {
        const reply = await chat(history);
        history.push({ role: "assistant", content: reply });
        memAppend(t, reply);
        if (history.length > MAX_TURNS * 2) history.splice(0, history.length - MAX_TURNS * 2);
      } catch (e) { console.error("✖ " + e.message); history.pop(); }
      finally { busy = false; }
      rl.prompt();
    });
  }
}
else if (cmd === "status") { console.log("服务：" + ((await health()) ? "运行中 ✅ " + CFG.healthUrl : "未运行")); console.log("目录：" + DIR + "\\n连接信息：\\n  base_url = " + CFG.baseUrl + "\\n  api_key  = " + CFG.apiKey + "\\n  model    = " + CFG.model); }
else if (cmd === "key") { if (rest.length >= 2) await addKey(rest[0], rest[1]); else if (rest.length === 1) console.log("用法：omni key <provider> <你的key>"); else { console.log("\\n" + B + "匿名免费池 vs 个人 API：" + D); console.log("  匿名池（已接好）：零注册即用·但易限流/慢/模型少"); console.log("  个人 API：稳定/快/模型全·需注册（无信用卡）"); console.log("  接入：omni key <provider> <key>，看清单用 omni free-list"); } }
else if (cmd === "memory") {
  const sub = rest[0] || "list";
  if (sub === "search") {
    const hits = memSearch(rest.slice(1).join(" "), 10);
    if (!hits.length) console.log("没有匹配的记忆");
    else for (const h of hits) console.log(G + h.id + D + "  " + h.time.slice(0, 16).replace("T", " ") + "\\n  " + h.summary);
  } else if (sub === "graph") {
    console.log(B + "记忆关系图（可粘到任何支持 mermaid 的地方渲染）：" + D + "\\n\\n\\u0060\\u0060\\u0060mermaid\\n" + memGraph() + "\\u0060\\u0060\\u0060");
  } else {
    const idx = memLoad();
    console.log("共 " + idx.items.length + " 条记忆，目录 " + MEM_DIR);
    for (const it of idx.items.slice(-10)) console.log("  " + G + it.id + D + "  " + it.summary);
    if (idx.items.length) console.log("\\n用法：omni memory search <关键词> / omni memory graph");
  }
}
else if (cmd === "free-list") await freeList();
else if (cmd === "mcp") await mcpGuide();
else if (cmd === "editor") await editorGuide();
else console.log("omni 用法：\\n  omni up / down / chat \\"问题\\" / status / key / free-list / mcp / editor\\n  omni memory [list|search <词>|graph]   长记忆：本地分段保存 + 关键词索引 + 关系图");
`;

export const WATCHDOG_SCRIPT = `#!/usr/bin/env node
// omni-watchdog — 关闭所有终端窗口后自动关闭服务（跨平台）
import { execSync } from "node:child_process";
import { readFileSync, existsSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { TextDecoder } from "node:util";
const DIR = process.env.OMNI_DIR || homedir().replace(/\\\\/g, "/") + "/.omniroute";
const CFG = JSON.parse(readFileSync(DIR + "/config.json", "utf8"));
const ACT = DIR + "/.activity";
const start = Date.now();
let dead = 0;
const alive = (c) => { try { execSync(c, { stdio: "ignore", windowsHide: true }); return true; } catch { return false; } };
function parseCsv(line){const f=[];let c="",q=false;for(let i=0;i<line.length;i++){const ch=line[i];if(q){if(ch==='"'){if(line[i+1]==='"'){c+='"';i++;}else q=false;}else c+=ch;}else{if(ch==='"')q=true;else if(ch===','){f.push(c);c="";}else c+=ch;}}f.push(c);return f;}
function hasTerminal() {
  try {
    if (CFG.os === "windows") {
      const hosts = new Set(["mintty.exe","windowsterminal.exe","wt.exe","cmd.exe","conhost.exe","powershell.exe","pwsh.exe","bash.exe","sh.exe"]);
      const noT = new Set(["","暂缺","n/a","n/d"]);
      const buf = execSync("tasklist /v /fo csv", { encoding: "buffer", windowsHide: true });
      const out = new TextDecoder("gbk").decode(buf);
      for (const line of out.split(/\\r?\\n/)) { const f = parseCsv(line); if (f.length < 9) continue; const n = (f[0]||"").toLowerCase(), t = (f[8]||"").trim(); if (hosts.has(n) && !noT.has(t.toLowerCase())) return true; }
      return false;
    }
    if (CFG.os === "macos") { return alive("pgrep -x Terminal") || alive("pgrep -x iTerm2") || alive("pgrep -x kitty") || alive("pgrep -x alacritty") || alive("pgrep -x WezTerm"); }
    return alive("pgrep -x gnome-terminal") || alive("pgrep -x konsole") || alive("pgrep -x xterm") || alive("pgrep -x kitty") || alive("pgrep -x alacritty") || alive("pgrep -x xfce4-terminal") || alive("pgrep -x tilix") || alive("pgrep -x terminator") || alive("pgrep -x mate-terminal");
  } catch { return true; }
}
function active() { try { return existsSync(ACT) && Date.now() - statSync(ACT).mtimeMs < 300000; } catch { return false; } }
function up() { try { execSync('netstat -ano | findstr ":' + CFG.port + '.*LISTENING"', { encoding: "utf8", windowsHide: true }); return true; } catch { return false; } }
function tick() { if (!up()) process.exit(0); const g = Date.now() - start < 180000; if (g || hasTerminal() || active()) { dead = 0; return; } dead++; if (dead >= 2) { try { execSync('"' + process.execPath + '" "' + DIR + '/omni.mjs" down', { stdio: "ignore", windowsHide: true }); } catch {} process.exit(0); } }
setInterval(tick, 20000); tick();
`;

export const MCP_SCRIPT = `#!/usr/bin/env node
// omni-mcp — 把免费池 + 管理能力暴露成 MCP 工具（供编辑器里的 AI 自助管理）
import { spawn } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { createInterface } from "node:readline";
const DIR = process.env.OMNI_DIR || homedir().replace(/\\\\/g, "/") + "/.omniroute";
const CFG = JSON.parse(readFileSync(DIR + "/config.json", "utf8"));
const ACT = DIR + "/.activity";
const touch = () => { try { writeFileSync(ACT, String(Date.now())); } catch {} };
async function health(){try{const r=await fetch(CFG.healthUrl,{signal:AbortSignal.timeout(2500)});return r.ok;}catch{return false;}}
async function ensureUp(){if(await health())return true;const c=spawn(process.execPath,[DIR+"/omni.mjs","up"],{detached:true,stdio:"ignore"});c.unref();const t0=Date.now();while(Date.now()-t0<180000){if(await health())return true;await new Promise(r=>setTimeout(r,3000));}return false;}
async function chat(prompt,model){touch();if(!(await ensureUp()))throw new Error("启动超时");const r=await fetch(CFG.baseUrl+"/chat/completions",{method:"POST",headers:{"Content-Type":"application/json",Authorization:"Bearer "+CFG.apiKey},body:JSON.stringify({model:model||CFG.model||"auto",messages:[{role:"user",content:String(prompt)}],stream:false})});const j=await r.json();if(!r.ok)throw new Error("HTTP "+r.status+" "+JSON.stringify(j).slice(0,400));touch();return j;}
async function freeList(){try{const r=await fetch("${FREE_LIST_URL}",{signal:AbortSignal.timeout(8000)});const j=await r.json();return (j.providers||[]).filter(p=>p.category==="provider_api").map(p=>({name:p.name,url:p.url,desc:(p.description||"").slice(0,80)}));}catch{return [];}}
const TOOLS=[
{name:"omni_chat",description:"调用 oMNIROUTE 免费 LLM 池对话（默认 "+CFG.model+"）。",inputSchema:{type:"object",properties:{prompt:{type:"string"},model:{type:"string"}},required:["prompt"]}},
{name:"omni_status",description:"查看服务状态与连接信息。",inputSchema:{type:"object",properties:{}}},
{name:"omni_up",description:"启动服务。",inputSchema:{type:"object",properties:{}}},
{name:"omni_down",description:"关闭服务。",inputSchema:{type:"object",properties:{}}},
{name:"omni_free_list",description:"检索最新可用的免费 AI 清单（带注册链接）。",inputSchema:{type:"object",properties:{}}}
];
async function handle(n,a){
if(n==="omni_chat"){const j=await chat(a.prompt,a.model);const c=j.choices&&j.choices[0]&&j.choices[0].message&&j.choices[0].message.content;if(c==null)throw new Error("无返回");return "["+(j.model||a.model||CFG.model)+"]\\n"+c;}
if(n==="omni_status"){return "服务:"+(await health()?"运行中":"未运行")+"\\nbase_url="+CFG.baseUrl+"\\nmodel="+CFG.model;}
if(n==="omni_up"){return (await ensureUp())?"已就绪":"启动失败";}
if(n==="omni_down"){const{execSync}=await import("node:child_process");try{return execSync('"'+process.execPath+'" "'+DIR+'/omni.mjs" down',{encoding:"utf8",windowsHide:true}).trim();}catch(e){return e.message;}}
if(n==="omni_free_list"){const l=await freeList();return l.length?l.map(x=>x.name+" — "+x.desc+"\\n  注册:"+x.url).join("\\n"):"检索失败";}
throw new Error("未知工具 "+n);}
const rl=createInterface({input:process.stdin});const send=(o)=>process.stdout.write(JSON.stringify(o)+"\\n");let pending=0,ended=false;
rl.on("line",async(line)=>{let m;try{m=JSON.parse(line);}catch{return;}
if(m.method==="initialize")send({jsonrpc:"2.0",id:m.id,result:{protocolVersion:"2024-11-05",capabilities:{tools:{}},serverInfo:{name:"omni-free-llm",version:"1.0.0"}}});
else if(m.method==="tools/list")send({jsonrpc:"2.0",id:m.id,result:{tools:TOOLS}});
else if(m.method==="tools/call"){const{name,arguments:a}=m.params||{};pending++;try{const t=await handle(name,a||{});send({jsonrpc:"2.0",id:m.id,result:{content:[{type:"text",text:t}],isError:false}});}catch(e){send({jsonrpc:"2.0",id:m.id,result:{content:[{type:"text",text:"错误: "+e.message}],isError:true}});}finally{pending--;maybeExit();}}
else if(m.method==="ping")send({jsonrpc:"2.0",id:m.id,result:{}});});
function maybeExit(){if(ended&&pending===0)process.exit(0);}process.stdin.on("end",()=>{ended=true;maybeExit();});
`;

// ---- 看门狗安装引导（按 OS）----
function watchdogGuide(dir) {
  console.log(`\n${BD}${B}「关终端自动关」看门狗（可选）${D}`);
  console.log(`  作用：关闭所有终端窗口后约 40 秒自动关闭服务，不占闲置资源。`);
  if (OS.id === "windows") {
    console.log(`  你的系统：${OS.name}。运行后看门狗会随 omni up 自动启动，无需额外配置。`);
  } else if (OS.id === "macos") {
    console.log(`  你的系统：${OS.name}。看门狗用 pgrep 检测 Terminal/iTerm2 等终端。`);
  } else {
    console.log(`  你的系统：${OS.name}（${OS.distro || "linux"}）。看门狗用 pgrep 检测 gnome-terminal/konsole 等终端。`);
  }
  console.log(`  安装位置：${dir}/omni-watchdog.mjs`);
}

// ---- 主流程 ----
async function main() {
  console.log(`${BD}${B}  omni-free-llm 免费 AI 一键安装${D}（${OS.name}）\n`);

  if (!nodeOk()) {
    console.error(`${R}✖ Node ${process.versions.node} 太旧${D}：需 >=22.22.2 或 >=24（<27）。https://nodejs.org`);
    process.exit(1);
  }
  console.log(`${G}✔${D} Node ${process.versions.node}，系统 ${OS.name}`);

  // ① 安装/存储路径
  const defDir = path.join(os.homedir(), ".omniroute").replace(/\\/g, "/");
  const dirAns = await ask(`${B}①${D} 安装与存储到哪个文件夹？（回车用默认 ${defDir}）：`);
  const DIR = (dirAns || defDir).replace(/\\/g, "/");
  fs.mkdirSync(DIR, { recursive: true });

  const free = freeGB(DIR);
  if (free != null) {
    if (free < NEED_GB) {
      console.log(`${R}⚠ 这个位置可用空间只有 ${free.toFixed(1)}GB，安装大约需要 ${NEED_GB}GB。${D}`);
      console.log(`  空间不够会装到一半失败，那时已经写进去的文件还得手动清。`);
      const go = await ask(`  仍然继续？(y/N)：`);
      if (go.toLowerCase() !== "y") { console.log(`${G}已取消，什么都没装。${D}`); closePrompt(); process.exit(0); }
    } else {
      console.log(`${G}✔${D} 可用空间 ${free.toFixed(1)}GB，够用（需要约 ${NEED_GB}GB）`);
    }
  }

  // ② 匿名 vs 个人 API
  console.log(`\n${BD}${B}② 选择免费来源${D}`);
  // 三个选项的磁盘占用其实一样：都要装同一个网关。把共同成本单独讲清楚，
  // 免得用户以为选「只要匿名池」能省空间。
  console.log(`  ${Y}注意：三种都要先装 oMNIROUTE 网关 —— 下载约 116MB，装完占约 2.3GB，耗时 5-15 分钟（视网速与磁盘）。${D}`);
  console.log(`  ${Y}这部分空间和时间是共同的，选哪个都一样，区别只在之后要不要花时间注册 key。${D}\n`);
  console.log(`  ${G}1${D} 匿名免费池   零注册即用，但易限流、偏慢、模型少`);
  console.log(`     ${D}└ 额外空间 0 ・ 额外耗时 0（装完直接能聊）`);
  console.log(`  ${G}2${D} 个人 API     稳定、快、模型全，无需信用卡`);
  console.log(`     ${D}└ 额外空间 0 ・ 额外耗时 每个 key 约 1-2 分钟（注册+粘贴，可随时跳过）`);
  console.log(`  ${G}3${D} 两个都要     匿名池兜底 + 个人 API 主力（推荐）`);
  console.log(`     ${D}└ 额外空间 0 ・ 额外耗时 同上，且可以一个都不填先用匿名池`);
  const mode = await ask(`  选 1/2/3（回车默认 3）：`) || "3";

  // 后端
  const docker = process.argv.includes("--docker");
  const password = crypto.randomBytes(12).toString("hex");
  console.log(`\n${B}ℹ${D} 安装后端（${docker ? "Docker" : "npm"}）并启动…`);
  if (!(await ensureBackend(password, docker))) { console.error(`${R}✖ 启动超时${D}，可重试或 --docker。`); process.exit(1); }
  console.log(`${G}✔${D} 服务已就绪`);

  let cookie = "", apiKey = "";
  try {
    cookie = await login(password);
    if (mode !== "2") { const n = await setupFree(cookie); console.log(`${G}✔${D} 已接入 ${n} 个免 key 匿名池`); }
    if (mode !== "1") await guidePersonalKeys(cookie);
    apiKey = await createKey(cookie);
  } catch (e) {
    console.log(`${Y}⚠${D} 自动接入失败：${e.message}`);
  }

  // 写配置 + 部署脚本
  const cfg = {
    port: PORT, baseUrl: `${BASE}/v1`, healthUrl: `${BASE}/api/health`,
    apiKey: apiKey || "", model: process.argv.includes("--model") ? (process.argv[process.argv.indexOf("--model") + 1] || "auto") : "auto",
    adminPassword: password, backend: docker ? "docker" : "npm", systemPrompt: DEFAULT_SYSTEM_PROMPT, memoryEnabled: true, memoryTopN: 3, spinner: true,
    startArgs: docker ? [] : serveArgs(), os: OS.id, dir: DIR,
  };
  fs.writeFileSync(path.join(DIR, "config.json"), JSON.stringify(cfg, null, 2));
  fs.writeFileSync(path.join(DIR, "omni.mjs"), OMNI_SCRIPT);
  fs.writeFileSync(path.join(DIR, "omni-watchdog.mjs"), WATCHDOG_SCRIPT);
  fs.writeFileSync(path.join(DIR, "omni-mcp.mjs"), MCP_SCRIPT);

  // ③ 看门狗（可选）
  watchdogGuide(DIR);
  const wdAns = await ask(`  是否启用「关终端自动关」看门狗？(y/N)：`);
  const useWatchdog = wdAns.toLowerCase() === "y" || wdAns.toLowerCase() === "yes";
  if (useWatchdog) console.log(`  ${G}✔${D} 看门狗已就绪，omni up 时会自动拉起。`);

  // ④ MCP
  const mcpAns = await ask(`\n${B}④${D} 是否启用 MCP（让编辑器里的 AI 自助管理免费池）？(y/N)：`);
  const useMcp = mcpAns.toLowerCase() === "y" || mcpAns.toLowerCase() === "yes";

  // ⑤ 编辑器
  console.log(`\n${B}⑤${D} 接入编辑器：终端已可直接用（见下），编辑器按需接入。`);

  // 写 alias
  writeAlias(DIR);
  printSummary(cfg, { useWatchdog, useMcp, mode });
  closePrompt();
}

function writeAlias(dir) {
  if (OS.id === "windows") {
    // cmd / PowerShell 不读 .bashrc / .zshrc：生成 omni.cmd 并把目录加进用户级 PATH
    const winDir = dir.replace(/\//g, "\\");
    fs.writeFileSync(path.join(dir, "omni.cmd"), `@echo off\r\nnode "%~dp0omni.mjs" %*\r\n`);
    const psFile = path.join(dir, ".addpath.ps1");
    fs.writeFileSync(psFile, [
      `$d = '${winDir.replace(/'/g, "''")}'`,
      `$p = [Environment]::GetEnvironmentVariable('Path','User'); if (-not $p) { $p = '' }`,
      `if (($p -split ';') -notcontains $d) { [Environment]::SetEnvironmentVariable('Path', ($p.TrimEnd(';') + ';' + $d).TrimStart(';'), 'User') }`,
    ].join("\r\n") + "\r\n");
    sh(`powershell -NoProfile -ExecutionPolicy Bypass -File "${psFile.replace(/\//g, "\\")}"`);
    try { fs.unlinkSync(psFile); } catch {}
    return;
  }
  const block = `# >>> omni-free-llm >>>\nalias omni='node "${dir}/omni.mjs"'\n# <<< omni-free-llm <<<`;
  for (const f of [path.join(os.homedir(), ".bashrc"), path.join(os.homedir(), ".zshrc")]) {
    try {
      const old = fs.existsSync(f) ? fs.readFileSync(f, "utf8") : "";
      fs.writeFileSync(f, old.replace(/# >>> omni-free-llm >>>[\s\S]*# <<< omni-free-llm <<</, "").trimEnd() + "\n\n" + block + "\n");
    } catch {}
  }
}

function printSummary(cfg, { useWatchdog, useMcp, mode }) {
  console.log(`\n${BD}${B}${"=".repeat(52)}${D}`);
  console.log(`${BD}  安装完成 ✅${D}`);
  console.log(`${B}${"=".repeat(52)}${D}`);
  console.log(`  目录     : ${cfg.dir}`);
  console.log(`  来源     : ${mode === "1" ? "匿名池" : mode === "2" ? "个人 API" : "匿名池 + 个人 API"}`);
  console.log(`  看门狗   : ${useWatchdog ? "✅ 已启用" : "未启用（可手动 node " + cfg.dir + "/omni-watchdog.mjs）"}`);
  console.log(`  MCP      : ${useMcp ? "✅ 已启用" : "未启用"}`);
  console.log(`  命令     : omni chat "问题" / omni status / omni key / omni free-list / omni down`);
  if (cfg.apiKey) console.log(`  base_url = ${B}${cfg.baseUrl}${D}\n  api_key  = ${B}${cfg.apiKey}${D}\n  model    = ${B}${cfg.model}${D}`);
  console.log(`${B}${"=".repeat(52)}${D}\n`);
  const winDir = cfg.dir.replace(/\//g, "\\");
  console.log(`${Y}下一步：${D}${OS.id === "windows" ? "重开一个 cmd 窗口" : "重开终端（或 source ~/.bashrc）"}后，运行 ${B}omni chat${D} 进入 AI 对话（输入 :q 退出）。`);
  if (OS.id === "windows") console.log(`${Y}若提示找不到 omni：${D}直接运行 ${B}node "${winDir}\\omni.mjs" chat${D}`);
  console.log(`${Y}接入编辑器：${D}运行 ${B}omni editor${D} 查看；MCP 配置运行 ${B}omni mcp${D} 查看。`);
}

const isMain = process.argv[1] && process.argv[1].replace(/\\/g, "/").endsWith("/install.mjs");
if (isMain) main().catch((e) => { console.error(`${R}✖ 安装失败：${e.message}${D}`); closePrompt(); process.exit(1); });
