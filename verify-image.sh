#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# verify-image.sh —— 验证「固化镜像」
#
# 做四件事：
#   1. 检查镜像内固化文件是否就位，且**不在会被运行时卷覆盖的路径**上
#   2. 用全新卷挂到 /home/retro，模拟"新会话容器"（照真实 cont-init 创建 retro 用户）
#   3. 预置一份"被浏览器改坏 + 含 discord 关联"的旧 mimeapps.list，跑启动钩子，
#      验证自愈：http/https/text/html 校正回 browser-picker.desktop，discord 保留
#   4. 验证 xdg-mime 能解析到 browser-picker.desktop
#
# ⚠ 重要环境细节：docker 的 -v 路径由**宿主机**解析，不是本容器内路径。
#   本脚本会自动把"本容器内路径"换算成"宿主机路径"（见 host_path_of）。
#
# 用法：./verify-image.sh [镜像名]
# ═══════════════════════════════════════════════════════════════════════════
set -euo pipefail

IMAGE="${1:-gameonwhales/lutris:kaijuu-picker}"
HERE="$(cd "$(dirname "$0")" && pwd)"
WORKDIR="$HERE"                      # 独立运行：验证卷放在脚本同级目录

# ── 本容器路径 → 宿主机路径（供 docker -v 使用）───────────────────────────
host_path_of() {
  local p="$1" best_src="" best_dst=""
  local map
  map="$(docker inspect "$(hostname)" --format '{{range .Mounts}}{{.Source}}|{{.Destination}}{{"\n"}}{{end}}' 2>/dev/null || true)"
  while IFS='|' read -r src dst; do
    [ -z "${dst:-}" ] && continue
    case "$p" in
      "$dst"|"$dst"/*)
        if [ "${#dst}" -gt "${#best_dst}" ]; then best_src="$src"; best_dst="$dst"; fi
        ;;
    esac
  done <<< "$map"
  if [ -n "$best_dst" ]; then
    printf '%s%s\n' "$best_src" "${p#"$best_dst"}"
  else
    printf '%s\n' "$p"
  fi
}

LOCAL_VOL="$WORKDIR/.verify-volume"      # 已被 .gitignore 忽略
HOST_VOL="$(host_path_of "$LOCAL_VOL")"
rm -rf "$LOCAL_VOL"; mkdir -p "$LOCAL_VOL/.config"

echo "▶ 镜像      : $IMAGE"
echo "▶ 卷(本容器): $LOCAL_VOL"
echo "▶ 卷(宿主)  : $HOST_VOL"

# ── 预置"旧卷"：被 Firefox 抢了默认，同时有 discord 关联 ──────────────────
cat > "$LOCAL_VOL/.config/mimeapps.list" <<'EOF'
[Default Applications]
x-scheme-handler/http=firefox.desktop
x-scheme-handler/https=firefox.desktop
text/html=firefox.desktop
x-scheme-handler/discord-1221314350216646828=discord-1221314350216646828.desktop
EOF
chmod -R 777 "$LOCAL_VOL"
echo "▶ 预置的旧配置（模拟被 Firefox 改坏）:"
sed 's/^/    /' "$LOCAL_VOL/.config/mimeapps.list"

echo
echo "════════ 容器内检查 ════════"
docker run --rm -v "$HOST_VOL:/home/retro" --entrypoint bash "$IMAGE" -c '
set -e
echo "── 0. 卷是否真的挂进来了 ──"
if [ -s /home/retro/.config/mimeapps.list ]; then
  echo "    ✓ 预置文件可见（挂载生效）"; sed "s/^/      /" /home/retro/.config/mimeapps.list
else
  echo "    ✗ 预置文件不可见 —— 挂载未生效，后续结论不可信"; exit 9
fi

echo "── 1. 固化文件 ──"
for f in /usr/local/bin/browser-picker \
         /usr/share/applications/browser-picker.desktop \
         /etc/xdg/mimeapps.list \
         /opt/gow/startup.d/90-browser-picker.sh; do
  if [ -s "$f" ]; then printf "    ✓ %-52s %s B\n" "$f" "$(stat -c%s "$f")";
  else printf "    ✗ %s 缺失或为空\n" "$f"; fi
done

echo "── 2. 确认未落在被卷覆盖的路径 ──"
for f in /usr/local/bin/browser-picker /usr/share/applications/browser-picker.desktop \
         /etc/xdg/mimeapps.list /opt/gow/startup.d/90-browser-picker.sh; do
  case "$f" in
    /home/retro*|/var/lutris*|/mnt/WD4/public*) echo "    ✗ $f 位于挂载覆盖区！" ;;
    *)                                          echo "    ✓ $f 不在挂载覆盖区" ;;
  esac
done

echo "── 3. 依赖工具 ──"
for t in zenity xdg-open xdg-mime update-desktop-database gosu; do
  printf "    %-24s %s\n" "$t" "$(command -v $t || echo MISSING)"
done

echo "── 4. 运行镜像内真实的 cont-init 用户创建脚本 ──"
mkdir -p /tmp/xdg
source /opt/gow/bash-lib/utils.sh 2>/dev/null || true
export UNAME=retro HOME=/home/retro PUID=1000 PGID=1000 UMASK=000 XDG_RUNTIME_DIR=/tmp/xdg
source /etc/cont-init.d/10-setup_user.sh
printf "    retro → %s\n" "$(id retro 2>/dev/null || echo 创建失败)"

echo "── 5. 执行启动钩子（retro 身份 source，模拟开机）──"
gosu retro env HOME=/home/retro bash -c ". /opt/gow/startup.d/90-browser-picker.sh" || echo "    ! 钩子返回非零"

echo "── 6. 钩子执行后的 ~/.config/mimeapps.list ──"
sed "s/^/    /" /home/retro/.config/mimeapps.list

echo "── 7. 断言 ──"
ok=1
grep -q "^x-scheme-handler/https=browser-picker.desktop$" /home/retro/.config/mimeapps.list || { echo "    ✗ https 未校正"; ok=0; }
grep -q "^x-scheme-handler/http=browser-picker.desktop$"  /home/retro/.config/mimeapps.list || { echo "    ✗ http 未校正";  ok=0; }
grep -q "^text/html=browser-picker.desktop$"              /home/retro/.config/mimeapps.list || { echo "    ✗ html 未校正";  ok=0; }
grep -q "discord-1221314350216646828" /home/retro/.config/mimeapps.list || { echo "    ✗ discord 关联丢失"; ok=0; }
[ "$ok" = 1 ] && echo "    ✓ 自愈成功：三个键已校正，discord 关联保留"

echo "── 8. 文件属主（应为 retro）──"
stat -c "    %U:%G  %n" /home/retro/.config/mimeapps.list

echo "── 9. xdg-mime 解析默认 handler ──"
grep -q "x-scheme-handler/https=browser-picker.desktop" /etc/xdg/mimeapps.list \
  && echo "    ✓ 系统级 /etc/xdg/mimeapps.list 已指向 browser-picker.desktop"
printf "    用户级 https → %s\n" "$(gosu retro env HOME=/home/retro xdg-mime query default x-scheme-handler/https)"

echo "── 10. 脚本语法与关键逻辑 ──"
bash -n /usr/local/bin/browser-picker && echo "    ✓ browser-picker 语法 OK"
grep -q "read -r -a _args" /usr/local/bin/browser-picker && echo "    ✓ URL 数组传参（防 & 被吞）"
grep -q "no-default-browser-check" /usr/local/bin/browser-picker && echo "    ✓ Firefox 防抢默认参数在位"
grep -q "GDK_BACKEND=x11" /usr/local/bin/browser-picker && echo "    ✓ GTK 强制 X11"
grep -q "browser-picker.conf" /usr/local/bin/browser-picker && echo "    ✓ 支持卷内配置覆盖（免重建）"
'
rc=$?
echo "════════ 验证结束 (exit=$rc) ════════"

# 保留一份卷内容作为证据，其余清理
cp -f "$LOCAL_VOL/.config/mimeapps.list" "$WORKDIR/.verify-volume-result.txt" 2>/dev/null || true
rm -rf "$LOCAL_VOL"
exit $rc
