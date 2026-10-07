# ═══════════════════════════════════════════════════════════════════════════
# gameonwhales/lutris:kaijuu + 浏览器选择器（固化版）
#
# 原 kaijuu 层：
#     FROM gameonwhales/lutris:edge
#     RUN apt-get update && apt-get install -y libglew-dev steam && rm -rf /var/lib/apt/lists/*
#
# 本文件在其上「固化」浏览器选择器：让战网等 Wine 程序点击"使用浏览器验证"时
# 弹出选择窗口，用户自选浏览器。
#
# ⚠ 关键设计约束（否则固化了也会失效）
#   Wolf 启动会话容器时会用**卷覆盖**下列路径：
#       /home/retro              ← 宿主 <会话目录>/Lutris
#       /home/retro/.config      ← 宿主 var/lutris/.config
#       /home/retro/.local       ← 宿主 var/lutris/.local
#       /var/lutris              ← 宿主 var/lutris
#   写在这些路径下的镜像文件会被挂载**遮蔽**（看不到）。
#   因此本文件把内容放在：
#       /usr/local/bin/browser-picker          脚本本体
#       /usr/share/applications/*.desktop      URL handler 注册
#       /etc/xdg/mimeapps.list                 系统级默认（XDG_CONFIG_DIRS）
#       /opt/gow/startup.d/90-browser-picker.sh 启动钩子（retro 身份，被 source）
#   启动钩子负责把用户级 ~/.config/mimeapps.list（在卷里、会覆盖系统级）写成正确内容，
#   从而做到「每次开机自愈」，包括修复"浏览器抢默认"这类回退。
#
# 构建：
#     docker build -t gameonwhales/lutris:kaijuu-picker .
# 运行：交给 Wolf 调度（镜像名填 gameonwhales/lutris:kaijuu-picker）
# ═══════════════════════════════════════════════════════════════════════════

FROM gameonwhales/lutris:edge

LABEL org.opencontainers.image.title="gow-lutris-kaijuu-browser-picker" \
      org.opencontainers.image.description="kaijuu + browser picker for Wine web-auth (Battle.net)" \
      org.opencontainers.image.source="local"

# ── 1. 原 kaijuu 层（保持不变）────────────────────────────────────────────
RUN apt-get update && \
    apt-get install -y \
        libglew-dev steam && \
    rm -rf /var/lib/apt/lists/*

# ── 2. 依赖：弹窗与 URL 关联 ──────────────────────────────────────────────
#   zenity              —— 选择器弹窗（edge 基础镜像通常已带，显式声明以防上游变更）
#   desktop-file-utils  —— update-desktop-database（生成 mimeinfo.cache）
#   xdg-utils           —— xdg-open / xdg-mime / xdg-settings
#   ca-certificates     —— https 页面根证书（战网登录页）
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        zenity \
        desktop-file-utils \
        xdg-utils \
        ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# ── 3. 固化文件 ───────────────────────────────────────────────────────────
COPY context/browser-picker          /usr/local/bin/browser-picker
COPY context/browser-picker.desktop  /usr/share/applications/browser-picker.desktop
COPY context/mimeapps.list           /etc/xdg/mimeapps.list
COPY context/90-browser-picker.sh    /opt/gow/startup.d/90-browser-picker.sh

RUN chmod 0755 /usr/local/bin/browser-picker \
               /opt/gow/startup.d/90-browser-picker.sh && \
    chmod 0644 /etc/xdg/mimeapps.list \
               /usr/share/applications/browser-picker.desktop && \
    update-desktop-database /usr/share/applications 2>/dev/null || true

# ── 4. 可选：把浏览器本体也烤进镜像 ───────────────────────────────────────
#   默认不烤：浏览器 AppImage 放在宿主共享盘 /mnt/WD4/public/software/linux
#   （运行时挂载，无需进镜像），且体积大、Chrome/Edge 有再分发条款问题。
#   若希望镜像自带一个浏览器（不依赖共享盘），取消下面注释并自行核对版本/校验和。
#
#   ARG FIREFOX_URL=https://download.mozilla.org/?product=firefox-latest-ssl&os=linux64&lang=zh-CN
#   RUN mkdir -p /opt/browsers && \
#       curl -fL "$FIREFOX_URL" -o /tmp/ff.tar.xz && \
#       tar -xJf /tmp/ff.tar.xz -C /opt/browsers && \
#       mv /opt/browsers/firefox /opt/browsers/firefox-bin-dir && \
#       ln -s /opt/browsers/firefox-bin-dir/firefox /opt/browsers/firefox && \
#       rm -f /tmp/ff.tar.xz
#   # 并把脚本里的 APP_DIR 指向 /opt/browsers，或在启动钩子里写
#   #   ~/.config/browser-picker.conf → APP_DIR=/opt/browsers

# ── 5. 自检（构建期快速验收，失败即构建失败）──────────────────────────────
RUN set -eux; \
    test -x /usr/local/bin/browser-picker; \
    test -s /usr/share/applications/browser-picker.desktop; \
    test -s /etc/xdg/mimeapps.list; \
    test -x /opt/gow/startup.d/90-browser-picker.sh; \
    grep -q 'x-scheme-handler/https=browser-picker.desktop' /etc/xdg/mimeapps.list; \
    command -v zenity >/dev/null; \
    command -v update-desktop-database >/dev/null; \
    echo "browser-picker 固化自检通过"
