#!/usr/bin/env bash
# 一键构建「kaijuu + 浏览器选择器」镜像
#
# 用法：./build.sh [镜像标签]
#   默认标签：gameonwhales/lutris:kaijuu-picker
set -euo pipefail

TAG="${1:-gameonwhales/lutris:kaijuu-picker}"
HERE="$(cd "$(dirname "$0")" && pwd)"

echo "▶ 构建上下文: $HERE"
echo "▶ 目标标签  : $TAG"

# 构建前本地自检（与 Dockerfile 内自检呼应，失败即中止，避免烤出坏镜像）
for f in "$HERE/context/browser-picker" \
         "$HERE/context/browser-picker.desktop" \
         "$HERE/context/mimeapps.list" \
         "$HERE/context/90-browser-picker.sh"; do
  [ -s "$f" ] || { echo "✗ 缺失或为空: $f" >&2; exit 1; }
done
bash -n "$HERE/context/browser-picker"
bash -n "$HERE/context/90-browser-picker.sh"
grep -q 'x-scheme-handler/https=browser-picker.desktop' "$HERE/context/mimeapps.list" \
  || { echo "✗ mimeapps.list 内容不符" >&2; exit 1; }
echo "✓ 上下文自检通过"

docker build -t "$TAG" "$HERE"

echo
echo "✔ 构建完成: $TAG"
cat <<EOF

下一步：
  1) 让 Wolf 用这个镜像启动 Lutris 会话（把会话镜像名改成 $TAG）
  2) 进入容器后验证（宿主机执行）：
       docker exec -u retro <容器> sh -c 'cat ~/.config/mimeapps.list; xdg-mime query default x-scheme-handler/https'
     期望：三个 http/https/text/html 键指向 browser-picker.desktop
  3) 战网里点「使用浏览器完成验证」→ 应弹出 Choose Browser 窗口

提示：
  * 浏览器 AppImage 放在宿主共享盘 /mnt/WD4/public/software/linux（容器内同路径）
  * 想增删浏览器而不重建镜像：在容器里写 ~/.config/browser-picker.conf
  * 想停用启动自愈：在容器里 touch ~/.config/browser-picker.no-autofix
EOF
