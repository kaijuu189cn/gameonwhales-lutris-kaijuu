#!/bin/sh
# ═══════════════════════════════════════════════════════════════════════════
# url-bridge-start.sh —— 幂等地部署并启动「沙箱 URL 桥接」
#
# 做两件事：
#   1) 把沙箱 xdg-open 代理安装到各个 Proton 版本的 bin 目录
#      （该目录是 Wine 进程 PATH 的第一项，且位于持久挂载 steamapps 上，
#        容器重启后仍在；兼容 Proton 版本号变化，会遍历所有版本）
#   2) 重启 url-bridge-daemon.sh（先杀旧实例，避免多个守护进程抢读同一 FIFO）
#
# 调用方：
#   - 镜像固化：/opt/gow/startup.d/91-url-bridge.sh（会话启动时）
#   - 运行时装法：~/.config/sway/custom-cfg 的 exec 行（sway 启动时）
#   也可手工执行，用于排障或首次部署。
#
# 查找顺序（两种部署方式共用本脚本）：
#   代理源  : $HOME/.local/bin/xdg-open-sandbox-proxy 或 /usr/local/share/url-bridge/…
#   守护进程: $HOME/.local/bin/url-bridge-daemon.sh    或 /usr/local/bin/url-bridge-daemon.sh
# ═══════════════════════════════════════════════════════════════════════════

HOME="${HOME:-/home/retro}"
LOG="${URL_BRIDGE_LOG:-/tmp/url-bridge.log}"
PIDF="${URL_BRIDGE_PID:-$HOME/.local/share/url-bridge/daemon.pid}"

# ── 定位代理源与守护进程（支持镜像安装与用户目录安装两种布局）──────────
PROXY_SRC=""
for c in "$HOME/.local/bin/xdg-open-sandbox-proxy" \
         /usr/local/share/url-bridge/xdg-open-sandbox-proxy; do
  [ -f "$c" ] && { PROXY_SRC="$c"; break; }
done

DAEMON=""
for c in "$HOME/.local/bin/url-bridge-daemon.sh" \
         /usr/local/bin/url-bridge-daemon.sh; do
  [ -x "$c" ] && { DAEMON="$c"; break; }
done

if [ -z "$DAEMON" ]; then
  echo "url-bridge-start: 找不到 url-bridge-daemon.sh，放弃" >>"$LOG" 2>&1
  exit 1
fi

# ── 1) 安装沙箱代理到所有 Proton 版本的 bin 目录 ────────────────────────
installed=0
if [ -n "$PROXY_SRC" ]; then
  for d in "$HOME/.steam/debian-installation/steamapps/common/Proton "*"/files/bin"; do
    [ -d "$d" ] || continue
    if cp -f "$PROXY_SRC" "$d/xdg-open" 2>/dev/null; then
      chmod 755 "$d/xdg-open" 2>/dev/null
      installed=$((installed + 1))
    fi
  done
  echo "url-bridge-start: 代理已安装到 $installed 个 Proton bin 目录（源 $PROXY_SRC）" >>"$LOG" 2>&1
else
  echo "url-bridge-start: 未找到 xdg-open-sandbox-proxy 源文件，跳过代理安装" >>"$LOG" 2>&1
fi

# ── 2) 重启守护进程 ─────────────────────────────────────────────────────
[ -f "$PIDF" ] && kill -9 "$(cat "$PIDF" 2>/dev/null)" 2>/dev/null
for p in $(pgrep -f "url-bridge-daemon.sh" 2>/dev/null); do
  [ "$p" = "$$" ] && continue
  kill -9 "$p" 2>/dev/null
done
sleep 1
mkdir -p "$HOME/.local/share/url-bridge" 2>/dev/null
setsid nohup "$DAEMON" >>"$LOG" 2>&1 < /dev/null &
sleep 1
echo "url-bridge-start: 完成 daemon=$DAEMON pid=$(cat "$PIDF" 2>/dev/null)" >>"$LOG" 2>&1
exit 0
