#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════
# 91-url-bridge.sh —— GOW 启动钩子：拉起「沙箱 URL 桥接」（镜像固化版）
#
# 执行时机：由 /opt/gow/startup-app.sh 以 retro 身份、在 Lutris 启动前
#           **source**。父脚本带 `set -e`，故本文件内命令必须容错，禁止 exit。
#
# 作用：部署沙箱 xdg-open 代理到各 Proton 版本 bin 目录，并启动守护进程，
#       让 pressure-vessel 沙箱内的战网等程序能打开浏览器。
#
# 相关文件（均由本镜像提供）：
#   /usr/local/bin/url-bridge-daemon.sh
#   /usr/local/bin/url-bridge-start.sh
#   /usr/local/share/url-bridge/xdg-open-sandbox-proxy
# ═══════════════════════════════════════════════════════════════════════════

_bp_start="/usr/local/bin/url-bridge-start.sh"
[ -x "$HOME/.local/bin/url-bridge-start.sh" ] && _bp_start="$HOME/.local/bin/url-bridge-start.sh"

if [ -x "$_bp_start" ]; then
  "$_bp_start" >/dev/null 2>&1 || true
  if command -v gow_log >/dev/null 2>&1; then
    gow_log "[url-bridge] 已执行 $_bp_start"
  fi
else
  if command -v gow_log >/dev/null 2>&1; then
    gow_log "[url-bridge] 未找到 $_bp_start，跳过"
  fi
fi

true
