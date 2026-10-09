#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# install-browser-picker.sh —— 为运行中的 Wolf/GOW Lutris 容器安装浏览器选择器
#
# 作用：让 Wine 程序（战网等）打开网页验证时弹出选择窗口，用户自选浏览器。
# 用法：./install-browser-picker.sh [容器名]    （不传则自动挑第一个 WolfLutris_*）
#
# 安装内容（全部在持久卷，容器重启后保留）：
#   ~/.local/bin/browser-picker                 选择器脚本（取自同目录 browser-picker.sh）
#   ~/.local/share/applications/browser-picker.desktop
#   ~/.config/mimeapps.list                     默认 handler → 选择器（保留其他关联）
#
# ⚠ 若要解决"战网点了完全没反应"，还需运行 ../sandbox-bridge/install-bridge.sh：
#   战网跑在 pressure-vessel 沙箱内，沙箱里的 /usr/bin/xdg-open 是
#   steam-runtime-urlopen，根本不会走到本选择器。
#
# 特性：幂等；自检（文件非空 / handler 解析 / 实际调起选择器）
# ═══════════════════════════════════════════════════════════════════════════
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CONTAINER="${1:-}"
if [ -z "$CONTAINER" ]; then
  CONTAINER="$(docker ps --format '{{.Names}}' | grep -E '^WolfLutris_' | head -1 || true)"
fi
[ -z "$CONTAINER" ] && { echo "✗ 未找到 WolfLutris 容器，请显式传入容器名" >&2; exit 1; }
echo "▶ 目标容器: $CONTAINER"

SRC_PICKER="$HERE/browser-picker.sh"
[ -s "$SRC_PICKER" ] || { echo "✗ 缺少 browser-picker.sh" >&2; exit 1; }

dexec()   { docker exec "$CONTAINER" "$@"; }
dexecr()  { docker exec -u retro "$CONTAINER" "$@"; }
dexec_i() { docker exec -i "$CONTAINER" "$@"; }

# ── 1. 安装选择器脚本 ─────────────────────────────────────────────────────
echo "▶ 安装选择器脚本 ..."
dexec mkdir -p /home/retro/.local/bin
docker cp "$SRC_PICKER" "$CONTAINER:/home/retro/.local/bin/browser-picker"
dexec chmod 755 /home/retro/.local/bin/browser-picker
dexec chown 1000:1000 /home/retro/.local/bin/browser-picker
dexecr bash -n /home/retro/.local/bin/browser-picker && echo "  ✓ 语法检查通过"

# ── 2. 注册 .desktop ──────────────────────────────────────────────────────
echo "▶ 注册 .desktop ..."
dexec_i sh -c 'cat > /home/retro/.local/share/applications/browser-picker.desktop' <<'EOF'
[Desktop Entry]
Version=1.0
Name=Browser Picker
GenericName=Web Browser Chooser
Comment=Choose which browser to open a link
Exec=/home/retro/.local/bin/browser-picker %u
Terminal=false
Type=Application
MimeType=x-scheme-handler/http;x-scheme-handler/https;text/html;
StartupNotify=false
Categories=Network;WebBrowser;
EOF
dexec chown 1000:1000 /home/retro/.local/share/applications/browser-picker.desktop
echo "  ✓ browser-picker.desktop"

# ── 3. 设为默认 handler（保留既有其他关联，如 discord://）─────────────────
echo "▶ 设置默认 handler ..."
PRESERVED="$(dexec sh -c 'grep "=" /home/retro/.config/mimeapps.list 2>/dev/null \
  | grep -vE "^(x-scheme-handler/(http|https)|text/html)=" || true')"
{
  echo "[Default Applications]"
  echo "x-scheme-handler/http=browser-picker.desktop"
  echo "x-scheme-handler/https=browser-picker.desktop"
  echo "text/html=browser-picker.desktop"
  if [ -n "$PRESERVED" ]; then
    echo "# ↓ 保留的原有其他关联（本安装器不改动）"
    echo "$PRESERVED"
  fi
} | dexec_i sh -c 'cat > /home/retro/.config/mimeapps.list'
dexec chown 1000:1000 /home/retro/.config/mimeapps.list
[ -n "$PRESERVED" ] && echo "  ✓ 保留原有其他关联 $(printf '%s\n' "$PRESERVED" | grep -c '=') 条"

# ── 4. 刷新关联缓存 ───────────────────────────────────────────────────────
echo "▶ 刷新 desktop 数据库 ..."
dexec sh -c 'command -v update-desktop-database >/dev/null 2>&1 || {
  apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends desktop-file-utils >/dev/null 2>&1; }' || true
dexecr update-desktop-database /home/retro/.local/share/applications/ 2>/dev/null \
  || echo "  ! update-desktop-database 不可用（显式默认仍生效）"

# ── 5. 自检 ───────────────────────────────────────────────────────────────
echo "▶ 验证 ..."
EMPTY="$(dexec sh -c '
  for f in /home/retro/.local/bin/browser-picker \
           /home/retro/.local/share/applications/browser-picker.desktop \
           /home/retro/.config/mimeapps.list; do
    [ -s "$f" ] || echo "$f"
  done')"
if [ -n "$EMPTY" ]; then
  echo "  ✗ 以下文件为空（写入失败）：" >&2; echo "$EMPTY" | sed 's/^/      /' >&2; exit 1
fi
echo "  ✓ 关键文件均非空"

DEF="$(dexecr xdg-mime query default x-scheme-handler/https 2>/dev/null || true)"
echo "  默认 handler: ${DEF:-（未解析）}"

dexecr sh -c 'export HOME=/home/retro
  nohup xdg-open "https://example.com/install-check" >/tmp/picker-check.log 2>&1 &
  sleep 6
  if ps aux | grep -q "[z]enity --list"; then echo "  ✓ 选择器已弹出（zenity --list）";
  else echo "  ! 未见选择器，请检查 zenity 与 DISPLAY"; fi' || true
dexecr sh -c 'pkill -9 -x zenity 2>/dev/null; true' || true

cat <<EOF

✔ 选择器安装完成（容器：$CONTAINER）
  脚本：/home/retro/.local/bin/browser-picker
  默认：browser-picker.desktop（http/https/text/html）
  配置：~/.config/browser-picker.conf（可覆盖 PICKER_APP_DIR / BROWSERS）

⚠ 若战网点击后仍毫无反应，说明请求卡在 pressure-vessel 沙箱内，
  请继续执行：  ../sandbox-bridge/install-bridge.sh $CONTAINER
EOF
