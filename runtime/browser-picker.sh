#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# browser-picker —— Wolf / Games-on-Whales Lutris 容器内的浏览器选择器
#
# 调用链：战网等 Wine 程序 → winebrowser.exe → xdg-open → 本脚本 → 浏览器
#   （沙箱场景下 xdg-open 是代理，经 FIFO 由 url-bridge-daemon 在沙箱外调用本脚本）
#
# ⚠ 坑：容器环境里已有 APP_DIR=/opt/gow/app（GOW 自用），
#   所以这里**不能**用 ${APP_DIR:-...}，否则会去 GOW 目录找浏览器而失败。
#   本脚本使用私有变量 PICKER_APP_DIR。
#
# 可用 ~/.config/browser-picker.conf 覆盖：
#     PICKER_APP_DIR=/mnt/WD4/public/software/linux
#     BROWSERS=( "Brave|Brave.AppImage --no-sandbox --new-window" )
# ═══════════════════════════════════════════════════════════════════════════
set -u

URL="${1:-}"
if [ -z "$URL" ]; then
  echo "usage: browser-picker <url>" >&2
  exit 1
fi

export HOME="${HOME:-/home/retro}"
export DISPLAY="${DISPLAY:-:0}"
export GDK_BACKEND=x11            # GTK 弹窗必须走 X11，否则 sway 不显示窗口
export GTK_A11Y=none
[ -f /run/pressure-vessel/Xauthority ] && export XAUTHORITY=/run/pressure-vessel/Xauthority
if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
  for _s in /tmp/dbus-*; do [ -S "$_s" ] && { export DBUS_SESSION_BUS_ADDRESS="unix:path=$_s"; break; }; done
fi
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/wolf}"

PICKER_APP_DIR="${PICKER_APP_DIR:-/mnt/WD4/public/software/linux}"
BROWSERS=(
  "Firefox|firefox --new-window --no-default-browser-check"
  "Chromium|Chromium --no-sandbox --new-window"
  "Google Chrome|Google-Chrome --no-sandbox --new-window"
  "Microsoft Edge|Microsoft-Edge --no-sandbox --new-window"
)

# 持久卷覆盖配置
[ -f "$HOME/.config/browser-picker.conf" ] && . "$HOME/.config/browser-picker.conf" 2>/dev/null

# 解析实际文件名：精确命中优先，否则按关键字模糊匹配（应对版本号变化）
resolve_bin() {
  _want="$1"
  if [ -x "$PICKER_APP_DIR/$_want" ]; then printf '%s\n' "$_want"; return 0; fi
  _key="${_want%%-*}"
  _hit="$(ls "$PICKER_APP_DIR" 2>/dev/null | grep -iF "$_key" | grep -i '\.AppImage$' | head -1)"
  [ -n "$_hit" ] && printf '%s\n' "$_hit"
}

# 组装菜单（同时解析出每个条目实际可用的文件）
MENU_NAMES=(); MENU_BINS=(); MENU_ARGS=()
for _e in "${BROWSERS[@]}"; do
  _name="${_e%%|*}"; _cmd="${_e#*|}"
  read -r -a _a <<< "$_cmd"
  _bin="$(resolve_bin "${_a[0]}")"
  [ -z "$_bin" ] && continue
  MENU_NAMES+=("$_name")
  MENU_BINS+=("$_bin")
  MENU_ARGS+=("${_a[*]:1}")
done

if [ ${#MENU_NAMES[@]} -eq 0 ]; then
  zenity --error --text="未在 $PICKER_APP_DIR 找到可用浏览器" 2>/dev/null || true
  exit 1
fi

ZENITY_ARGS=(--list --title="Choose Browser" --text="Open URL with:" --column="Browser" --width=400 --height=300)
ZENITY_ARGS+=("${MENU_NAMES[@]}")
SELECTED="$(zenity "${ZENITY_ARGS[@]}" 2>/dev/null)" || true
[ -z "$SELECTED" ] && exit 1

for _i in "${!MENU_NAMES[@]}"; do
  if [ "${MENU_NAMES[$_i]}" = "$SELECTED" ]; then
    _bin="${MENU_BINS[$_i]}"; _extra="${MENU_ARGS[$_i]}"
    case "${MENU_NAMES[$_i]}" in *Firefox*) export MOZ_ENABLE_WAYLAND=0 ;; esac
    read -r -a _ea <<< "$_extra"
    exec "$PICKER_APP_DIR/$_bin" "${_ea[@]}" "$URL"
  fi
done
exit 1
