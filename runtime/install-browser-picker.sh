#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# install-browser-picker.sh —— 为 Wolf/GOW Lutris 容器安装"浏览器选择器"
#
# 作用：让 Wine 程序（战网等）打开网页验证时弹出选择窗口，用户自选浏览器。
# 用法：./install-browser-picker.sh [容器名]
#       不传容器名则自动挑第一个 WolfLutris_* 容器。
#
# 特性：幂等（可重复执行）；自动探测共享盘上的浏览器 AppImage；
#       只写持久化挂载区（容器重启后仍生效）。
#
# 依赖：宿主机有 docker CLI；容器内 zenity（镜像自带）。
# ═══════════════════════════════════════════════════════════════════════════
set -euo pipefail

# ── 目标容器 ───────────────────────────────────────────────────────────────
CONTAINER="${1:-}"
if [ -z "$CONTAINER" ]; then
  CONTAINER="$(docker ps --format '{{.Names}}' | grep -E '^WolfLutris_' | head -1 || true)"
fi
if [ -z "$CONTAINER" ]; then
  echo "✗ 未找到 WolfLutris 容器，请显式传入容器名" >&2
  exit 1
fi
echo "▶ 目标容器: $CONTAINER"

APP_DIR="/mnt/WD4/public/software/linux"   # 容器内路径（共享盘）
RUN_UID=1000                                # retro

dexec()  { docker exec "$CONTAINER" "$@"; }
dexecr() { docker exec -u retro "$CONTAINER" "$@"; }
# ⚠ 用 heredoc 喂 stdin 时必须加 -i：docker exec 默认不转发 stdin，否则写出 0 字节空文件
dexec_i() { docker exec -i "$CONTAINER" "$@"; }

# ── 1. 探测共享盘上可用的浏览器 ────────────────────────────────────────────
echo "▶ 探测浏览器 AppImage ..."
AVAILABLE="$(dexec sh -c "ls $APP_DIR/*.AppImage 2>/dev/null || true")"
if [ -z "$AVAILABLE" ]; then
  echo "✗ $APP_DIR 下没有 AppImage。请先把浏览器放到共享盘。" >&2
  exit 1
fi
echo "$AVAILABLE" | sed 's|.*/|  - |'

# 按模式匹配，生成 "显示名|文件名 参数" 清单
BROWSER_LINES=""
add_browser() {  # $1=模式  $2=显示名  $3=参数
  local f
  f="$(echo "$AVAILABLE" | grep -E "/$1\$" | head -1 | sed 's|.*/||' || true)"
  [ -z "$f" ] && return 0
  BROWSER_LINES+="  \"$2|$f $3\""$'\n'
  echo "  ✓ 登记: $2 ($f)"
}
# 注意：参数里不要写 %u —— URL 由脚本作为独立参数追加（避免 & 被 bash 吞掉）
add_browser 'firefox.*\.AppImage'        'Firefox'         '--new-window --no-default-browser-check'
add_browser 'Chromium.*\.AppImage'       'Chromium'        '--no-sandbox --new-window'
add_browser 'Google-Chrome.*\.AppImage'  'Google Chrome'   '--no-sandbox --new-window'
add_browser 'Microsoft-Edge.*\.AppImage' 'Microsoft Edge'  '--no-sandbox --new-window'

if [ -z "$BROWSER_LINES" ]; then
  echo "✗ 共享盘上没有识别到已知浏览器（firefox/chromium/chrome/edge 的 AppImage）" >&2
  exit 1
fi

# ── 2. 生成并写入 browser-picker 脚本 ──────────────────────────────────────
echo "▶ 写入 ~/.local/bin/browser-picker ..."
TMP_PICKER="$(mktemp)"
{
  cat <<'HEADER'
#!/usr/bin/env bash
# browser-picker —— Wolf/Lutris 容器内的浏览器选择器（由 install-browser-picker.sh 生成）
# 用法: browser-picker <url>
# 添加浏览器：把 AppImage 放进 APP_DIR，然后在 BROWSERS 数组加一行。
# ⚠ URL 必须作为独立参数传给浏览器，切勿用字符串替换拼 URL（URL 里的 & 会被 bash 吞掉）。
set -u

URL="${1:-}"
[ -z "$URL" ] && { echo "usage: browser-picker <url>" >&2; exit 1; }

export HOME="${HOME:-/home/retro}"
export DISPLAY="${DISPLAY:-:0}"
export GDK_BACKEND=x11          # 弹窗必须走 X11，否则 sway 不显示窗口
export GTK_A11Y=none            # 抑制 dbus-launch 噪音
[ -f /run/pressure-vessel/Xauthority ] && export XAUTHORITY=/run/pressure-vessel/Xauthority
if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
  for s in /tmp/dbus-*; do [ -S "$s" ] && { export DBUS_SESSION_BUS_ADDRESS="unix:path=$s"; break; }; done
fi
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/wolf}"

APP_DIR="${APP_DIR:-/mnt/WD4/public/software/linux}"

BROWSERS=(
HEADER
  printf '%s' "$BROWSER_LINES"
  cat <<'BODY'
)

ZENITY_ARGS=(--list --title="Choose Browser" --text="Open URL with:" --column="Browser" --width=400 --height=300)
for entry in "${BROWSERS[@]}"; do ZENITY_ARGS+=("${entry%%|*}"); done

SELECTED="$(zenity "${ZENITY_ARGS[@]}" 2>/dev/null)" || true
[ -z "$SELECTED" ] && exit 1

for entry in "${BROWSERS[@]}"; do
  name="${entry%%|*}"
  if [ "$name" = "$SELECTED" ]; then
    cmd="${entry#*|}"
    read -r -a CMD_ARGS <<< "$cmd"
    if [ ! -x "$APP_DIR/${CMD_ARGS[0]}" ]; then
      zenity --error --text="不可执行: ${CMD_ARGS[0]}" 2>/dev/null || true
      exit 1
    fi
    [ "${name#*Firefox}" != "$name" ] && export MOZ_ENABLE_WAYLAND=0
    exec "$APP_DIR/${CMD_ARGS[0]}" "${CMD_ARGS[@]:1}" "$URL"
  fi
done
echo "unknown choice: $SELECTED" >&2
exit 1
BODY
} > "$TMP_PICKER"

# 复制进容器（docker cp 后属主会变 root，需修正）
docker exec "$CONTAINER" mkdir -p /home/retro/.local/bin
docker cp "$TMP_PICKER" "$CONTAINER:/home/retro/.local/bin/browser-picker"
rm -f "$TMP_PICKER"
dexec chmod 755 /home/retro/.local/bin/browser-picker
dexec chown "$RUN_UID:$RUN_UID" /home/retro/.local/bin/browser-picker
dexecr bash -n /home/retro/.local/bin/browser-picker && echo "  ✓ 语法检查通过"

# ── 3. 注册 .desktop ──────────────────────────────────────────────────────
echo "▶ 写入 .desktop ..."
dexec_i sh -c "cat > /home/retro/.local/share/applications/browser-picker.desktop" <<'EOF'
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

# 每个浏览器各建一个 .desktop（供 GIO 识别"有应用可处理"）
while IFS= read -r line; do
  [ -z "$line" ] && continue
  NAME="${line%%|*}"; NAME="${NAME#  \"}"
  FILEARG="${line#*|}"; FILEARG="${FILEARG%\"}"
  BIN="${FILEARG%% *}"
  EXTRA="${FILEARG#* }"
  [ "$EXTRA" = "$FILEARG" ] && EXTRA=""
  SLUG="$(echo "$NAME" | tr 'A-Z ' 'a-z-')"
  case "$NAME" in
    *Firefox*) ENVPREFIX="env MOZ_ENABLE_WAYLAND=0 GDK_BACKEND=x11 "; WMCLASS="Firefox" ;;
    *)         ENVPREFIX="env GDK_BACKEND=x11 ";                 WMCLASS="chromium-browser" ;;
  esac
  dexec_i sh -c "cat > /home/retro/.local/share/applications/${SLUG}.desktop" <<EOF
[Desktop Entry]
Version=1.0
Name=$NAME
Exec=${ENVPREFIX}$APP_DIR/$BIN $EXTRA %u
Terminal=false
Type=Application
Icon=$APP_DIR/$BIN
MimeType=text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;application/pdf;
StartupNotify=true
StartupWMClass=$WMCLASS
Categories=Network;WebBrowser;
EOF
  echo "  ✓ $SLUG.desktop"
done <<< "$BROWSER_LINES"
dexec chown -R "$RUN_UID:$RUN_UID" /home/retro/.local/share/applications

# ── 4. 设为默认 handler（保留文件中既有的其他关联，如 discord://）─────────
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
} | dexec_i sh -c "cat > /home/retro/.config/mimeapps.list"
dexec chown "$RUN_UID:$RUN_UID" /home/retro/.config/mimeapps.list
[ -n "$PRESERVED" ] && echo "  ✓ 保留原有其他关联 $(printf '%s\n' "$PRESERVED" | wc -l) 条"

# ── 5. 刷新关联缓存 ───────────────────────────────────────────────────────
echo "▶ 刷新 desktop 数据库 ..."
dexec sh -c 'command -v update-desktop-database >/dev/null 2>&1 || {
  apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends desktop-file-utils >/dev/null 2>&1; }' || true
dexecr update-desktop-database /home/retro/.local/share/applications/ 2>/dev/null || echo "  ! update-desktop-database 不可用（显式默认仍生效）"

# ── 6. 验证 ───────────────────────────────────────────────────────────────
echo "▶ 验证 ..."

# 6.1 文件必须非空（docker exec 漏 -i 会写出 0 字节文件，这里兜底）
EMPTY="$(dexec sh -c '
  for f in /home/retro/.local/bin/browser-picker \
           /home/retro/.local/share/applications/browser-picker.desktop \
           /home/retro/.config/mimeapps.list; do
    [ -s "$f" ] || echo "$f"
  done')"
if [ -n "$EMPTY" ]; then
  echo "  ✗ 以下文件为空（写入失败）：" >&2
  echo "$EMPTY" | sed 's/^/      /' >&2
  exit 1
fi
echo "  ✓ 关键文件均非空"

# 6.2 默认 handler 必须解析到 browser-picker
DEF="$(dexecr xdg-mime query default x-scheme-handler/https 2>/dev/null || true)"
echo "  默认 handler: ${DEF:-（未解析）}"
if [ "$DEF" != "browser-picker.desktop" ]; then
  echo "  ! 期望 browser-picker.desktop，实际 ${DEF:-空}；若刚跑过 update-desktop-database 可忽略，否则检查 mimeapps.list" >&2
fi

# 6.3 调用链：xdg-open 应拉起 zenity 选择器
echo "  调用链测试:"
dexecr sh -c 'export HOME=/home/retro
  nohup xdg-open "https://example.com/install-check?a=1&b=2" >/tmp/picker-check.log 2>&1 &
  sleep 6
  if ps aux | grep -q "[z]enity --list"; then echo "    ✓ 选择器已弹出 (zenity --list)";
  elif ps aux | grep -q "[b]rowser-picker"; then echo "    ! browser-picker 已启动但 zenity 未出现";
  else echo "    ✗ 未见 browser-picker/zenity"; fi' || true
dexecr pkill -f "zenity --list" 2>/dev/null || true
dexecr pkill -f "browser-picker" 2>/dev/null || true

cat <<EOF

✔ 安装完成。
  - 容器：$CONTAINER
  - 脚本：/home/retro/.local/bin/browser-picker
  - 默认：browser-picker.desktop（http/https/text/html）
  - 已登记浏览器：
$BROWSER_LINES
提示：
  * 战网里点"使用浏览器完成验证"应弹出 Choose Browser 窗口。
  * 若某次不弹而直接开 Firefox，说明 Firefox 抢了默认，重跑本脚本即可。
  * 容器重启后本配置保留；但 xdotool/grim 等诊断工具需重装（见 setup-tools.sh）。
EOF
