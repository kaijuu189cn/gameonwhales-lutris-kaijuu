#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# browser-picker —— Games-on-Whales (Wolf) / Lutris 容器内"浏览器选择器"
#
# 作用：被 xdg-open 调用时弹出选择窗口，让用户选择用哪个浏览器打开 URL。
#       战网（Battle.net）等 Wine 程序点击"使用浏览器完成验证"时即走此路径：
#         winebrowser.exe → xdg-open → browser-picker → 浏览器
#
# 用法：browser-picker <url>
#
# 【添加新浏览器】两步：
#   1. 把 AppImage / 可执行文件放进 APP_DIR 目录
#   2. 在下面 BROWSERS 数组加一行： "显示名称|可执行文件名 附加参数"
#      —— URL 会自动作为最后一个参数追加，不要写 %u（见下方"坑 3"）
#
# 【容器重启后】若曾用 apt 装过 zenity 之外的工具，需重跑 setup-tools.sh；
#   本脚本只需 zenity（镜像自带）与浏览器文件（在共享盘，恒在）。
# ═══════════════════════════════════════════════════════════════════════════

set -u

URL="${1:-}"
if [ -z "$URL" ]; then
  echo "usage: browser-picker <url>" >&2
  exit 1
fi

# ── 运行环境（headless sway + Xwayland :0）─────────────────────────────────
export HOME="${HOME:-/home/retro}"
export DISPLAY="${DISPLAY:-:0}"
# GTK 弹窗必须走 X11：默认走 wayland-1 时窗口不会被 sway 显示
export GDK_BACKEND=x11
# 关掉无障碍总线探测，避免 "Failed to execute child process dbus-launch" 噪音
export GTK_A11Y=none
# X 授权：仅当文件真实存在时才设置（该路径只在战网的 pressure-vessel 命名空间内存在）
[ -f /run/pressure-vessel/Xauthority ] && export XAUTHORITY=/run/pressure-vessel/Xauthority
# DBUS：优先用继承来的地址（从战网调用链继承）；否则探测 /tmp/dbus-* 套接字
if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
  for s in /tmp/dbus-*; do
    [ -S "$s" ] && { export DBUS_SESSION_BUS_ADDRESS="unix:path=$s"; break; }
  done
fi
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/wolf}"

# 浏览器所在目录（宿主共享盘，随容器挂载，恒在）
APP_DIR="${APP_DIR:-/mnt/WD4/public/software/linux}"

# ─────────────── 浏览器清单（加新浏览器只改这里）───────────────────────────
# 格式： "显示名称|可执行文件名 附加参数"
# 注意：chromium 系在容器内需要 --no-sandbox；
#       firefox 需要 --no-default-browser-check 防止它抢走默认浏览器设置。
BROWSERS=(
  "Firefox|firefox-149.0.r20260403140140-x86_64.AppImage --new-window --no-default-browser-check"
  "Chromium|Chromium-stable-152.0.7977.64-x86_64.AppImage --no-sandbox --new-window"
  "Google Chrome|Google-Chrome-stable-152.0.7977.64-1-x86_64.AppImage --no-sandbox --new-window"
  "Microsoft Edge|Microsoft-Edge-stable-152.0.4191.53-1-x86_64.AppImage --no-sandbox --new-window"
)
# ──────────────────────────────────────────────────────────────────────────

# ── 生成 zenity 列表参数（界面用英文：容器 locale 为 POSIX，中文会编码失败）──
ZENITY_ARGS=(--list --title="Choose Browser" --text="Open URL with:" \
             --column="Browser" --width=400 --height=300)
for entry in "${BROWSERS[@]}"; do
  ZENITY_ARGS+=("${entry%%|*}")
done

SELECTED="$(zenity "${ZENITY_ARGS[@]}" 2>/dev/null)" || true
if [ -z "$SELECTED" ]; then
  exit 1   # 用户取消
fi

# ── 按选择启动浏览器 ──────────────────────────────────────────────────────
for entry in "${BROWSERS[@]}"; do
  name="${entry%%|*}"
  if [ "$name" = "$SELECTED" ]; then
    cmd="${entry#*|}"
    # 坑 3：必须把命令拆成数组、URL 单独作为参数传递。
    # 绝不可用 cmd="${cmd//%u/$URL}" 之类的字符串替换——URL 里的 & 会被
    # bash 替换语法吞成替换模式文本，导致 URL 损坏。
    read -r -a CMD_ARGS <<< "$cmd"
    if [ ! -x "$APP_DIR/${CMD_ARGS[0]}" ]; then
      zenity --error --text="浏览器文件不可执行：${CMD_ARGS[0]}" 2>/dev/null || true
      exit 1
    fi
    [ "${name#*Firefox}" != "$name" ] && export MOZ_ENABLE_WAYLAND=0
    exec "$APP_DIR/${CMD_ARGS[0]}" "${CMD_ARGS[@]:1}" "$URL"
  fi
done

echo "unknown choice: $SELECTED" >&2
exit 1
