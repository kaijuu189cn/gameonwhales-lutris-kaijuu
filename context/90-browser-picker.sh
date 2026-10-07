#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════
# 90-browser-picker.sh —— GOW 启动钩子（固化于镜像）
#
# 执行时机：由 /opt/gow/startup-app.sh 以 **retro 用户身份**、在 Lutris 启动前
#           **source**（不是执行）。父脚本带 `set -e`，故本文件内所有命令必须
#           容错，且**禁止 exit**。
#
# 为什么需要它：
#   Wolf 用卷覆盖 /home/retro/.config，所以用户级 ~/.config/mimeapps.list
#   （在卷里）优先级高于镜像内置的 /etc/xdg/mimeapps.list。若卷里的文件把
#   http/https 指向别的浏览器（典型：Firefox 首次运行把自己设为默认），
#   选择器就会被绕过。本钩子每次开机把这三个键校正回 browser-picker.desktop，
#   同时**保留**其他关联（如 discord://），实现"自愈"。
#
# 停用自愈：在持久卷里创建 ~/.config/browser-picker.no-autofix
# ═══════════════════════════════════════════════════════════════════════════

_bp_home="${HOME:-/home/retro}"
_bp_cfg_dir="${_bp_home}/.config"
_bp_file="${_bp_cfg_dir}/mimeapps.list"

_bp_log() {
  if command -v gow_log >/dev/null 2>&1; then gow_log "[browser-picker] $*"; fi
}

if [ -f "${_bp_cfg_dir}/browser-picker.no-autofix" ]; then
  _bp_log "检测到 no-autofix，跳过 mimeapps.list 校正"
else
  if mkdir -p "${_bp_cfg_dir}" 2>/dev/null; then
    # 保留既有的非 http/https/html 关联
    _bp_keep=""
    if [ -f "${_bp_file}" ]; then
      _bp_keep="$(grep '=' "${_bp_file}" 2>/dev/null \
        | grep -vE '^(x-scheme-handler/(http|https)|text/html)=' || true)"
    fi

    _bp_tmp="${_bp_file}.tmp.$$"
    {
      echo "[Default Applications]"
      echo "x-scheme-handler/http=browser-picker.desktop"
      echo "x-scheme-handler/https=browser-picker.desktop"
      echo "text/html=browser-picker.desktop"
      if [ -n "${_bp_keep}" ]; then
        echo "${_bp_keep}"
      fi
    } > "${_bp_tmp}" 2>/dev/null

    if [ -s "${_bp_tmp}" ]; then
      mv -f "${_bp_tmp}" "${_bp_file}" 2>/dev/null \
        && _bp_log "mimeapps.list 已校正（保留其他关联 $(printf '%s' "${_bp_keep}" | grep -c '=' 2>/dev/null || echo 0) 条）"
    fi
    rm -f "${_bp_tmp}" 2>/dev/null
  fi
fi

# 刷新用户级 desktop 数据库（卷里可能还有自定义 .desktop）
if [ -d "${_bp_home}/.local/share/applications" ] \
   && command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "${_bp_home}/.local/share/applications" >/dev/null 2>&1 || true
fi

true
