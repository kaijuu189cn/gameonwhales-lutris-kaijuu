#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# setup-tools.sh —— 恢复 Wolf/Lutris 容器的诊断工具
#
# 背景：Wolf 会话容器重启后根文件系统重置，apt 安装的工具全部丢失；
#       只有挂载卷（~/.local、~/.config、/var/lutris、共享盘）持久。
#       本脚本重装诊断工具；核心配置（browser-picker）不受影响。
#
# 用法：./setup-tools.sh [容器名]
# ═══════════════════════════════════════════════════════════════════════════
set -euo pipefail

CONTAINER="${1:-}"
if [ -z "$CONTAINER" ]; then
  CONTAINER="$(docker ps --format '{{.Names}}' | grep -E '^WolfLutris_' | head -1 || true)"
fi
[ -z "$CONTAINER" ] && { echo "✗ 未找到 WolfLutris 容器" >&2; exit 1; }
echo "▶ 容器: $CONTAINER"

echo "▶ apt update ..."
docker exec "$CONTAINER" sh -c 'apt-get update -qq'

echo "▶ 安装工具（desktop-file-utils / xdotool / grim / imagemagick / x11-utils）..."
docker exec "$CONTAINER" sh -c '
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  desktop-file-utils xdotool grim imagemagick x11-utils x11-apps >/dev/null 2>&1 || \
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  desktop-file-utils xdotool grim imagemagick x11-utils >/dev/null 2>&1 || true'

echo "▶ 刷新 desktop 数据库 ..."
docker exec -u retro "$CONTAINER" sh -c 'update-desktop-database ~/.local/share/applications/ 2>/dev/null || true'

echo "▶ 结果："
docker exec "$CONTAINER" sh -c 'for t in zenity xdotool grim convert update-desktop-database xdg-open swaymsg; do printf "  %-24s %s\n" "$t" "$(command -v $t || echo MISSING)"; done'

cat <<'EOF'

提示：
  * 截图：wayland-1 不支持 screencopy，请用 wayland-2
      docker exec -u retro <容器> sh -c 'export WAYLAND_DISPLAY=wayland-2 XDG_RUNTIME_DIR=/run/user/wolf; grim -l 0 /tmp/s.png'
  * 单窗口截图：DISPLAY=:0 + xwd -id <窗口ID>
EOF
