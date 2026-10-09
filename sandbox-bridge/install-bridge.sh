#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# install-bridge.sh —— 把「沙箱 URL 桥接」装进正在运行的 GOW Lutris 容器
#
# 用途：不重建镜像就修复"战网点使用浏览器验证没反应"的问题。
#   根因是 pressure-vessel 沙箱内的 xdg-open 被替换为 steam-runtime-urlopen，
#   它只会尝试 Steam 管道与 D-Bus portal，两者在本环境都不可用。
#
# 用法：./install-bridge.sh [容器名]
#       不传则自动挑第一个 WolfLutris_* 容器
#
# 安装内容（全部落在持久卷，容器重启后保留）：
#   ~/.local/bin/xdg-open-sandbox-proxy   沙箱内代理源文件
#   ~/.local/bin/url-bridge-daemon.sh     FIFO → 选择器 的守护进程
#   ~/.local/bin/url-bridge-start.sh      部署代理 + 重启守护进程（幂等）
#   ~/.config/sway/custom-cfg             sway 启动时自动执行上面的 start
#   → 并立即把代理装到各 Proton 版本 bin 目录、拉起守护进程
# ═══════════════════════════════════════════════════════════════════════════
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CONTAINER="${1:-}"
if [ -z "$CONTAINER" ]; then
  CONTAINER="$(docker ps --format '{{.Names}}' | grep -E '^WolfLutris_' | head -1 || true)"
fi
[ -z "$CONTAINER" ] && { echo "✗ 未找到 WolfLutris 容器" >&2; exit 1; }
echo "▶ 目标容器: $CONTAINER"

dexec()  { docker exec "$CONTAINER" "$@"; }
dexecr() { docker exec -u retro "$CONTAINER" "$@"; }
dexec_i(){ docker exec -i "$CONTAINER" "$@"; }

dexec mkdir -p /home/retro/.local/bin /home/retro/.config/sway

echo "▶ 写入桥接脚本 ..."
for f in xdg-open-sandbox-proxy url-bridge-daemon.sh url-bridge-start.sh; do
  [ -s "$HERE/$f" ] || { echo "✗ 缺失或为空: $HERE/$f" >&2; exit 1; }
  docker cp "$HERE/$f" "$CONTAINER:/home/retro/.local/bin/$f"
  dexec chmod 755 "/home/retro/.local/bin/$f"
  dexec chown 1000:1000 "/home/retro/.local/bin/$f"
  echo "  ✓ ~/.local/bin/$f"
done

echo "▶ 写 sway 自启片段 ..."
dexec_i sh -c 'cat > /home/retro/.config/sway/custom-cfg' < "$HERE/sway-custom-cfg"
dexec chmod 644 /home/retro/.config/sway/custom-cfg
dexec chown 1000:1000 /home/retro/.config/sway/custom-cfg
echo "  ✓ ~/.config/sway/custom-cfg"

echo "▶ 校验语法 ..."
dexecr sh -n /home/retro/.local/bin/xdg-open-sandbox-proxy
dexecr sh -n /home/retro/.local/bin/url-bridge-daemon.sh
dexecr sh -n /home/retro/.local/bin/url-bridge-start.sh
echo "  ✓ 三个脚本语法 OK"

echo "▶ 部署代理并启动守护进程 ..."
dexecr /home/retro/.local/bin/url-bridge-start.sh
sleep 2

echo "▶ 结果："
dexecr sh -c 'echo "  守护进程: $(cat ~/.local/share/url-bridge/daemon.pid 2>/dev/null || echo 未启动)"
  echo "  FIFO    : $(ls -la ~/.local/share/url-bridge/requests.fifo 2>/dev/null | awk "{print \$1}" || echo 缺失)"
  echo "  代理已装: $(ls ~/.steam/debian-installation/steamapps/common/Proton*/files/bin/xdg-open 2>/dev/null | wc -l) 个 Proton 版本"
  echo "  --- 最近日志 ---"; tail -3 /tmp/url-bridge.log 2>/dev/null | sed "s/^/  /"'

cat <<EOF

✔ 沙箱 URL 桥接已安装。
  下一步：在战网里点「使用浏览器完成登录」，应弹出 Choose Browser 选择窗口。
  排障：  docker exec -u retro $CONTAINER tail -20 /tmp/url-bridge.log
  自检：  docker exec $CONTAINER sh -c 'P=\$(pgrep -f Battle.net.exe|head -1); B="\$(ls -d ~/.steam/debian-installation/steamapps/common/Proton*/files/bin|head -1)"; nsenter -t \$P -m -- env PATH="\$B:/usr/bin:/bin" HOME=/home/retro xdg-open https://example.com'
EOF
