# 对话记录：WolfLutris 容器内 Battle.net 网页验证无法链接浏览器

## 2026-10-02 会话

### 用户要求
WolfLutris（gameonwhales/lutris:kaijuu）容器已打开，Battle.net 打开后要求"使用浏览器完成网页验证"，但链接不到浏览器。

### 环境
- 容器：`WolfLutris_397584808901142269`（gameonwhales/lutris:kaijuu，Ubuntu 25.04）
- 显示：sway（wayland-1）+ gamescope 1080p，Wine 程序跑在 Xwayland :0（wayland-2）
- Battle.net 通过 lutris + umu + Proton 11.0 运行（WINEPREFIX=/var/lutris/Games/battlenet/pfx/）

### 诊断过程
1. **窗口树定位**：`swaymsg -t get_tree` 发现 3 个浮动窗口：
   - 「战网」登录弹窗（392x391，pid 705）
   - **「Open With…」对话框（xdg-desktop-portal-gtk，pid 262）** ← 问题核心
   - explorer.exe 小窗口
2. **日志佐证**：Battle.net 日志（battle.net-20261002T021229.903143.log）显示：
   - `UAuth: begin loading: https://account.battlenet.com.cn/login/zh/login.app?app=app`
   - `Begin hosted flow: https://oauth.g.mkey.163.com/oauth/oauth_page?...`（网易 mkey oauth 授权）
3. **OCR 铁证**：抓取 Open With… 对话框截图，OCR 结果：
   > "No Apps available"
   > "No apps installed that can open '...RUEZMDYOOEYwQjey&flow=login&secure=true'"
   > "You can find more applications in Software"
4. **根因确认**：
   - `~/.config/mimeapps.list` 把 `text/html`、`http`、`https` 指向 `firefox.desktop`
   - 但容器内 **没有任何浏览器**（/usr/share/applications 无 firefox/chromium，/usr/bin 无浏览器）
   - Battle.net 登录流程调 xdg-open 打开 oauth URL → 找不到 firefox.desktop → portal 弹 Open With… 且 No Apps available

### 解决方案
1. 发现浏览器 AppImage 已存在于共享目录：`/mnt/WD4/public/software/linux/`
   - `firefox-149.0.r20260403140140-x86_64.AppImage`
   - `Chromium-stable-152.0.7977.64-x86_64.AppImage`
   - `Google-Chrome-stable-152.0.7977.64-1-x86_64.AppImage`
   - `Microsoft-Edge-stable-152.0.4191.53-1-x86_64.AppImage`
2. **提取 firefox AppImage** 到持久目录：
   - `/home/retro/.local/share/appimages/firefox/`（298MB，挂载自 wolf 持久卷 `/etc/wolf/var/lutris/.local`）
3. **创建 .desktop 文件**：`/home/retro/.local/share/applications/firefox.desktop`
   - `Exec=env MOZ_ENABLE_WAYLAND=0 GDK_BACKEND=x11 /home/retro/.local/share/appimages/firefox/firefox-bin %u`
   - 关键：**必须强制 X11 模式**（MOZ_ENABLE_WAYLAND=0），否则 firefox 走 Wayland 窗口不出现在 sway/X11 树
4. mimeapps.list 原本就指向 firefox.desktop，无需改动

### 验证结果
- `xdg-open https://example.com` → firefox 正常打开（sway 树出现 "Example Domain — Mozilla Firefox"）
- `xdg-open "https://oauth.g.mkey.163.com/oauth/oauth_page?client_id=ld12&state=TEST..."` → firefox 打开 **"网易账号登录 — Mozilla Firefox"** 窗口（正是战网 oauth 需要的）
- Open With… 对话框消失
- 持久化确认：wolf 容器视角 `/etc/wolf/var/lutris/.local/share/appimages/firefox/` 与 `applications/firefox.desktop` 均已写入，容器重启后保留

## 追加需求（同日）：xdg-open 弹"选择浏览器"窗口

### 用户要求
希望 xdg-open 打开链接时弹出选择窗口，手动选择用哪个浏览器。

### 实测结论
1. **xdg-open 原生不弹选择器**：有默认浏览器直接打开；无默认按字母序选第一个；完全无关联才弹 portal "Open With…"，但 headless 环境下列表为空（portal-gtk `UseIn=gnome` 不匹配 sway，AppChooser 枚举不完整）
2. **zenity/yad 需要强制 X11 + XAUTHORITY**：GTK3 应用默认走 wayland-1 但窗口不被 sway 显示；设 `GDK_BACKEND=x11` + `XAUTHORITY=/run/pressure-vessel/Xauthority`（umu 压力容器的 X 授权）后窗口正常出现在 X11 树并被 wayland-2 抓屏捕获

### 实施
创建浏览器选择器脚本 `~/.local/bin/browser-picker`：
- zenity --list 列出 Firefox / Chromium / Google Chrome / Microsoft Edge
- 选中后 exec 对应 AppImage 打开 URL
- 4 个浏览器 AppImage 均在 `/mnt/WD4/public/software/linux/`（已挂载持久）

注册为默认浏览器：
- `~/.local/share/applications/browser-picker.desktop`（Exec=/home/retro/.local/bin/browser-picker %u）
- `mimeapps.list`：`x-scheme-handler/http|https` 和 `text/html` → browser-picker.desktop
- chromium.desktop / firefox.desktop 保留注册（选择器备选项）

### 验证
- `xdg-open https://oauth.g.mkey.163.com/...` → **弹出 "Choose Browser" 选择窗口**（zenity 400x300，列出 4 个浏览器）
- 用 xdotool 选中 Firefox → firefox 正常打开 URL
- 全部配置已持久化到 wolf 卷（`/etc/wolf/var/lutris/.local/bin/`、`.local/share/applications/`、`.config/mimeapps.list`），容器重启保留

### 注意事项
- 选择器界面为英文（容器 locale 是 POSIX，中文传参会编码失败；如需中文需先生成 zh_CN.UTF-8 locale）
- Edge AppImage 原本无执行位，已 chmod +x
- 若用户取消选择（点 Cancel），xdg-open 返回非零，链接不打开

### 遗留问题
- 未实际完成战网登录（需要用户在选中的浏览器里完成网易账号验证后回到战网）
- firefox 曾出现 "Firefox is already running"（profile 锁），可删 `~/.mozilla/firefox/*.lz4` 或加 `--profile`

## 追加（同日）：选择器脚本改为集中配置，支持轻松添加新浏览器

### 用户提问
下载了新浏览器后，如何加入选择器？

### 改动
1. 重写 `~/.local/bin/browser-picker`：
   - 用 `BROWSERS` 关联数组集中定义所有浏览器（"显示名称|可执行文件 参数 %u"）
   - zenity 列表和启动逻辑自动从数组生成
   - 加新浏览器只需在数组加一行 + 把文件放入 `/mnt/WD4/public/software/linux/`
2. 验证：v2 脚本弹窗正常，选中 Firefox 成功打开
3. README 增加"如何添加新浏览器"章节

### 添加新浏览器步骤（给用户）
1. 把 AppImage 放入 `/mnt/WD4/public/software/linux/`
2. 编辑 `~/.local/bin/browser-picker` 的 BROWSERS 数组加一行，如：
   `"Brave|brave.AppImage --no-sandbox --new-window %u"`
3. `bash -n` 检查语法即可

## 追加（同日）：修复 URL 传参 bug（& 变 %u）

### 现象
战网打开浏览器验证时，firefox 显示"页面出错！"，登录流程中断。

### 根因
`browser-picker` 脚本用 `cmd="${cmd//%u/$URL}"` 做字符串替换时，bash 替换串里 URL 的裸 `&` 被解释为"整个匹配文本"，导致 URL 里所有 `&` 参数分隔符变成 `%u`，firefox 收到残缺 URL（如 `...scope%3D%ureturn=http...`）→ 页面出错。

### 修复
改为**数组传参**：
- 命令模板不再含 `%u`，URL 作为独立参数最后追加
- `read -ra CMD_ARGS <<< "$cmd"` 拆分参数，`exec "$APP_DIR/${CMD_ARGS[0]}" "${CMD_ARGS[@]:1}" "$URL"` 执行
- 添加浏览器清单格式简化为 `"显示名称|可执行文件 附加参数"`（URL 自动追加）

### 验证
- 645 字符真实战网 URL 完整传递，所有 `&`/`%26` 保留
- 端到端：选择器选 Firefox → firefox 进程收到完整登录 URL → 页面正常加载（非"页面出错"）
- 产出/browser-picker.sh 已同步

## 追加（同日）：战网验证时"不弹选择器"问题

### 现象
战网触发登录验证时，不弹选择器，而是直接打开 firefox（或显示"页面出错"）。

### 根因
**firefox 启动时自动把自己设为默认浏览器**，覆盖了 `~/.config/mimeapps.list`：
```
x-scheme-handler/https=firefox.desktop   ← firefox 自动写入
```
导致 xdg-open 直接走 firefox，跳过 browser-picker 选择器。

### 修复
1. `mimeapps.list` 恢复默认 → `browser-picker.desktop`（http/https/text/html）
2. firefox.desktop 和 picker 脚本里的 firefox 启动参数加 `--no-default-browser-check`（防止 firefox 再覆盖默认）
3. firefox.desktop 指向 AppImage 原文件（统一路径）

### 验证
完整链路 `winebrowser.exe（战网）→ xdg-open → browser-picker → zenity 选择器` 已跑通，选择器正常弹出列出 4 个浏览器。

### 教训
- firefox（及 chrome 系浏览器）首次运行会主动设默认浏览器，覆盖 mimeapps.list
- 加了 `--no-default-browser-check` 后不会覆盖
- 以后新增浏览器到 picker 时，记得给会"抢默认"的浏览器加该参数

---

## 追加（2026-10-09）：战网"点了完全没反应"的两个真因

前几轮修好的是**容器层面**的问题（浏览器未注册、抢默认、URL 传参）。但用户在实际
战网里点击"使用浏览器完成登录"时依然毫无反应。深挖后找到两个更底层的原因。

### 真因 A：pressure-vessel 沙箱里的 xdg-open 被换掉了

战网进程运行在 umu/Proton 的 pressure-vessel 沙箱内。进入它的挂载命名空间观察：

```bash
P=$(pgrep -f Battle.net.exe | head -1)
nsenter -t $P -m -- ls -la /usr/bin/xdg-open /usr/bin/zenity
# ls: cannot access '/usr/bin/zenity': No such file or directory
# lrwxrwxrwx  /usr/bin/xdg-open -> steam-runtime-urlopen
```

沙箱内的 `xdg-open` 不是 freedesktop 的 xdg-open，而是 `steam-runtime-urlopen`：

```bash
nsenter -t $P -m -- env HOME=/home/retro DISPLAY=:0 xdg-open https://example.com
# steam-runtime-urlopen: Unable to open URL
# steam-runtime-urlopen: tried using steam.pipe, received error: Steam is not running
# steam-runtime-urlopen: tried using xdg-desktop-portal, received error: Unable to connect to D-Bus session bus
```

它只走两条路：Steam 管道（Steam 没运行）与 D-Bus portal（沙箱内没有可用会话总线
——战网进程的 `DBUS_SESSION_BUS_ADDRESS=unix:path=/run/pressure-vessel/bus` 已关闭）。
两条都失败 → 直接放弃 → **我们注册的 browser-picker 永远不会被调用**。

而且沙箱内无法就地弹窗：容器的 zenity 虽可通过 `/run/host/usr/bin/zenity` 看到，
但因缺 `libadwaita-1.so.0` 等容器库而无法运行；容器自己的 `xdg-open` 脚本也因缺
`xdg-mime` 而失败。

**解法：跨沙箱桥接**（`sandbox-bridge/`）

- 找到注入点：Wine 进程的 `PATH` 第一项是 Proton 的
  `.../common/Proton 11.0/files/bin`，该目录在持久挂载 steamapps 上且**可写**。
  实验证实 `winebrowser` 会按 `PATH` 解析 `xdg-open`（放一个探针脚本进去即被调用）。
- 沙箱内代理：把 http(s) URL 写进共享 FIFO（以 `O_RDWR` 打开，不会阻塞）。
- 沙箱外守护进程：读 FIFO → 调 `browser-picker` → 弹选择器 → 启动浏览器。
- 持久化：`~/.config/sway/custom-cfg`（被 sway 主配置 include，且在持久卷）在每次
  会话启动时调用 `url-bridge-start.sh`，重装代理并重启守护进程。

### 真因 B：`APP_DIR` 环境变量被 GOW 占用

修复 A 之后，桥接日志能收到战网的真实 URL，但选择器弹不出来。用 `bash -x` 追踪
包装器后看到：

```
+21: APP_DIR=/opt/gow/app
```

GOW 容器本身设置了 `APP_DIR=/opt/gow/app`（Gamepad UI 用），而选择器脚本写的是
`APP_DIR="${APP_DIR:-/mnt/WD4/public/software/linux}"` —— 于是它去 GOW 目录找浏览器，
找不到、弹错误框、退出。**环境变量污染。**

**解法**：脚本改用私有变量名 `PICKER_APP_DIR`；并增加文件名模糊匹配
（浏览器升级换版本号后仍能找到）。

### 验证

沙箱内触发 → 桥接日志出现战网真实 URL → 弹出 Choose Browser → 选择后浏览器打开
战网登录页 → 完成登录，页面显示"现在可以返回战网游戏或应用程序"。
