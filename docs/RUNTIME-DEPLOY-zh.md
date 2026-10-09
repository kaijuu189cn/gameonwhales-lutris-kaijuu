# WolfLutris 容器内 Battle.net 网页验证无法链接浏览器

## 目标
排查 WolfLutris 容器内 Battle.net 登录时"使用浏览器完成网页验证但链接不到浏览器"的问题并修复。

## 状态
✅ 已完成（2026-10-02）

## 结论
**根因**：容器内没有安装任何浏览器，但 `~/.config/mimeapps.list` 把 http/https 指向不存在的 `firefox.desktop`。Battle.net 登录流程（网易 mkey oauth）调 xdg-open 打开登录 URL 时找不到默认浏览器，xdg-desktop-portal 弹出 "Open With…" 且显示 "No Apps available"。

**修复**：把共享目录 `/mnt/WD4/public/software/linux/` 的 firefox AppImage 提取到持久位置并注册 .desktop，强制 X11 模式运行。xdg-open 现在能正常调起 firefox 打开网易登录页。

**追加需求**：xdg-open 弹"选择浏览器"窗口 → 用自定义 zenity 选择器 `browser-picker` 实现，设为默认浏览器，弹窗列出 Firefox/Chromium/Chrome/Edge 供选择。

## 产出清单
- `产出/` （本对话无独立脚本产出，配置为容器内持久文件）
- `附件/战网登录弹窗.png` — 战网登录弹窗截图（OCR：使用浏览器完成全部登录）
- `附件/OpenWith放大.png` — Open With… 对话框截图（OCR：No Apps available）
- `附件/AppChooser选择器.png` — portal AppChooser 弹窗（列表为空）
- `附件/firefox窗口测试.png` — firefox 打开 example.com 窗口测试
- `附件/修复验证-网易登录页.png` — 修复后 firefox 打开网易账号登录页
- `附件/最终-浏览器选择器.png` — 自定义浏览器选择器窗口（列出 4 个浏览器）
- `附件/wayland2全屏.png` — 修复前全屏状态

## 容器内改动（持久，重启保留）
| 路径 | 内容 |
|------|------|
| `/home/retro/.local/bin/browser-picker` | 浏览器选择器脚本（zenity 列表 + AppImage 调用） |
| `/home/retro/.local/share/appimages/firefox/` | firefox 149 提取目录（298MB，备用） |
| `/home/retro/.local/share/applications/browser-picker.desktop` | Exec=/home/retro/.local/bin/browser-picker %u |
| `/home/retro/.local/share/applications/firefox.desktop` | firefox 注册（选择器备选） |
| `/home/retro/.local/share/applications/chromium.desktop` | chromium 注册（选择器备选） |
| `~/.config/mimeapps.list` | 默认浏览器 → browser-picker.desktop |

## 关键经验
- sway 的 grim 无法抓 wayland-1（headless 无 screencopy），但 **wayland-2（Xwayland 用的 socket）可以 grim 抓全屏**
- firefox AppImage 在此容器必须 `MOZ_ENABLE_WAYLAND=0 GDK_BACKEND=x11` 才会出现在 Xwayland :0 窗口树
- **GTK3 弹窗（zenity/yad）必须 `GDK_BACKEND=x11` + `XAUTHORITY=/run/pressure-vessel/Xauthority`**，否则窗口不显示或报 cannot open display
- wolf 持久卷在容器内视角：`/etc/wolf/var/lutris/.local` ↔ 容器内 `/home/retro/.local`
- 容器 locale 是 POSIX，中文传参给 GTK 对话框会编码失败，选择器界面用英文

## 如何添加新浏览器到选择器
选择器脚本 `browser-picker` 已改为**集中配置**，加新浏览器只需两步：

1. **把浏览器 AppImage（或可执行文件）放入共享目录**
   `/mnt/WD4/public/software/linux/`（宿主机对应 `/mnt/WD4/public/software/linux/`，已持久挂载）

2. **在脚本的 BROWSERS 数组加一行**（编辑容器内 `~/.local/bin/browser-picker`）：
   ```
   "显示名称|可执行文件名 附加参数 --new-window %u"
   ```
   示例（Brave）：
   ```
   "Brave|brave.AppImage --no-sandbox --new-window %u"
   ```
   - `%u` 会自动替换成要打开的 URL
   - 名称含 "Firefox" 会自动加 `MOZ_ENABLE_WAYLAND=0`（可选）
   - 改完 `bash -n ~/.local/bin/browser-picker` 检查语法即可，无需其他操作

**修改命令**（在宿主机执行）：
```bash
docker exec -u retro WolfLutris_397584808901142269 vi ~/.local/bin/browser-picker
```

> 注：本机无编辑器偏好时可用 `sed -i` 或把文件拷出改完再拷回（如 `产出/browser-picker.sh` 就是当前脚本副本，可编辑后 `docker cp` 回去）。

---

## 追加（2026-10-09）：还需要的第二个脚本

仅装选择器**不足以**让战网打开浏览器：战网运行在 umu/Proton 的 pressure-vessel
沙箱内，沙箱里的 `/usr/bin/xdg-open` 是 `steam-runtime-urlopen`，只会尝试 Steam
管道与 D-Bus portal，本环境两者都不可用，请求根本到不了选择器。

因此运行时部署要跑两个脚本：

```bash
./runtime/install-browser-picker.sh <容器名>   # 选择器 + .desktop + mimeapps
./sandbox-bridge/install-bridge.sh  <容器名>   # 跨沙箱 URL 桥接（必需）
```

桥接装好后会写入 `~/.config/sway/custom-cfg`（持久卷），由 sway 在每次会话启动时
自动重装沙箱代理并拉起守护进程，因此容器重启后无需手工干预。

自检：

```bash
docker exec -u retro <容器> tail -20 /tmp/url-bridge.log
```

在战网里点击「使用浏览器完成登录」时，日志应出现
`url-bridge: 收到 https://account.battlenet.com.cn/...`，随后弹出 Choose Browser。
