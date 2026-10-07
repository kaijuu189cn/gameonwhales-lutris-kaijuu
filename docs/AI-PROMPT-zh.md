# AI 提示词：Wolf / Games-on-Whales Lutris 容器 —— 让 Wine 程序的网页验证能打开浏览器（并支持自选浏览器）

> **用法**：把本文件整段贴给任意 AI Agent（或作为新会话的首条指令），它即可在同类容器中完成诊断、修复与部署。
> **来源**：2026-10-02 实战（会话 08），容器 `WolfLutris_397584808901142269`，镜像 `gameonwhales/lutris:kaijuu`。
> **验证状态**：全部步骤已在真实容器中跑通（含战网 `winebrowser → xdg-open → 选择器` 完整链路）。

---

## 0. 你的任务

在一个 **Games-on-Whales (Wolf) 的 Lutris 游戏容器**里，让 **Wine/Proton 程序（典型：国服 Battle.net 战网）** 在需要"使用浏览器完成网页验证"时能真正打开浏览器；若用户要求，则实现**每次打开链接弹出浏览器选择器**，让用户自选浏览器。

工作方式要求：
- 先**探测**环境事实再动手，不要假设路径/用户名/显示后端
- 只改**持久化挂载区内**的文件，改动要能在容器重启后保留
- 每步改动后**验证**（进程链 + 窗口树 + 截图三选二）
- 临时安装的工具要记录，并告知用户"容器重启后需重装"

---

## 1. 环境事实（先核对，勿照抄）

| 项目 | 事实 | 核对命令 |
|---|---|---|
| 容器名 | 形如 `WolfLutris_<会话ID>`，由 Wolf 动态创建 | `docker ps --format '{{.Names}}\t{{.Image}}'` |
| 镜像 | `gameonwhales/lutris:kaijuu`（Ubuntu 25.04） | 同上 |
| 运行用户 | `retro`（uid 1000），**非 root** | `docker exec -u retro <容器> id` |
| 显示栈 | sway（`WAYLAND_DISPLAY=wayland-1`）+ Xwayland `:0` | `docker exec <容器> ls /tmp/.X11-unix/` |
| Wine 显示 | Wine 程序走 Xwayland `:0`，其 `WAYLAND_DISPLAY=wayland-2` | `tr '\0' '\n' < /proc/<winepid>/environ \| grep -E 'DISPLAY\|WAYLAND'` |
| Wine 运行时 | lutris + umu + Proton（pressure-vessel 沙箱） | `ps aux \| grep -E 'umu-run\|proton'` |
| zone/时区 | 容器 `TZ=Europe/London`（与宿主不同，看日志时间需换算） | `docker exec <容器> date` |
| locale | **POSIX（无 UTF-8）** → GTK 对话框中文参数报 `Invalid byte sequence` | `docker exec -u retro <容器> locale` |
| 自带工具 | `zenity`、`xdg-open`、`xdg-mime`、`swaymsg`、`sway` | `which zenity xdg-open swaymsg` |
| 需另装工具 | `xdotool`、`grim`、`imagemagick`、`tesseract`、`desktop-file-utils`、`yad` | 逐个 `which` 检查 |

### 1.1 持久化边界（关键！）

容器**根文件系统每次重启重置**：`apt-get install` 装的一切都会丢失。
只有以下挂载点在重启后保留：

| 容器内路径 | 内容 | 从 wolf 主容器查看 |
|---|---|---|
| `/home/retro` | 用户家目录（含 `.local`、`.config` 之外的部分） | `/etc/wolf/<会话ID>/Lutris` |
| `/home/retro/.config` | 配置（mimeapps.list 在这） | `/etc/wolf/var/lutris/.config` |
| `/home/retro/.local` | 应用数据（我们放脚本和 .desktop 的地方） | `/etc/wolf/var/lutris/.local` |
| `/var/lutris` | Lutris 游戏库（战网的 WINEPREFIX 在这） | `/etc/wolf/var/lutris` |
| `/mnt/WD4/public` | **宿主共享盘**（浏览器 AppImage 放这里，恒在） | 宿主 `/mnt/WD4/public` |

核对挂载（宿主机执行）：
```bash
docker inspect <容器> --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{"\n"}}{{end}}'
```

---

## 2. 症状 → 根因 → 处置（三种典型故障）

| # | 症状 | 根因 | 处置 |
|---|---|---|---|
| 1 | 点验证后弹 **"Open With…" → "No Apps available"** | `~/.config/mimeapps.list` 把 `http/https/text/html` 指向的 `.desktop` **不存在**（容器内根本没装浏览器；GIO 关联表里无可用应用） | 注册**真实存在**的浏览器 `.desktop`（指向共享盘 AppImage） |
| 2 | xdg-open 调起了浏览器，但**窗口不出现**（进程在、窗口树没有） | GTK/浏览器默认走 wayland-1，而 sway 不显示其窗口；K线说明：sway 树与 X11 树都查不到 | 强制 X11：`GDK_BACKEND=x11`；Firefox 另需 `MOZ_ENABLE_WAYLAND=0` |
| 3 | 浏览器打开后显示 **"页面出错！"**，URL 尾部出现 `%u` 乱码 | 脚本用 `cmd="${cmd//%u/$URL}"` 做字符串替换 —— bash 替换串里 URL 的 **`&` 被解释为"整个匹配文本"**，导致 URL 里所有 `&` 变成 `%u`，URL 损坏 | **改用数组传参**：命令拆词 + URL 作为独立参数追加（见 §4.2） |

补充故障（第 4 种，易复发）：

| # | 症状 | 根因 | 处置 |
|---|---|---|---|
| 4 | 已经配好选择器，过一阵**又不弹了**，直接开 Firefox | **Firefox 启动时把自己设为默认浏览器**，覆写了 `mimeapps.list` | 重写 `mimeapps.list`；给 Firefox 加 `--no-default-browser-check` |

---

## 3. 方案总览

```
战网（Wine）点击"使用浏览器验证"
   └─ winebrowser.exe           ← Wine 内置，读注册表决定用哪个外部程序
        └─ xdg-open <URL>       ← winebrowser 硬编码调用 xdg-open
             └─ browser-picker  ← 我们注册的默认 handler（.desktop 指向脚本）
                  └─ zenity --list  弹窗让用户选浏览器
                       └─ <浏览器 AppImage> <URL>
```

涉及 4 个文件（全在持久卷）：

| 文件 | 作用 |
|---|---|
| `~/.local/bin/browser-picker` | 选择器脚本（弹窗 + 启动浏览器） |
| `~/.local/share/applications/browser-picker.desktop` | 把脚本注册成 URL handler |
| `~/.local/share/applications/firefox.desktop` 等 | 各浏览器注册（备用/供选择器列项） |
| `~/.config/mimeapps.list` | 指定 http/https/text/html 的默认 handler = 选择器 |

---

## 4. 实施步骤

### 4.0 探测（先做，别跳）

```bash
C=<容器名>

# 谁在处理 URL 打开
docker exec -u retro $C sh -c 'cat ~/.config/mimeapps.list 2>/dev/null; echo ---; ls ~/.local/share/applications/*.desktop 2>/dev/null'
docker exec -u retro $C sh -c 'xdg-mime query default x-scheme-handler/https; gio mime x-scheme-handler/https 2>&1 | head -5'

# 浏览器 AppImage 在哪
docker exec $C sh -c 'ls -la /mnt/WD4/public/software/linux/*.AppImage 2>/dev/null'

# 战网是否在跑 & 它的 X 授权（用于诊断无法显示窗口）
docker exec $C sh -c 'for p in $(pgrep -f Battle.net.exe | head -1); do tr "\0" "\n" < /proc/$p/environ | grep -E "DISPLAY|XAUTHORITY|WAYLAND"; done'
```

### 4.1 确认浏览器可用（先能跑，再谈集成）

AppImage 需要执行位；容器内跑 chromium 系必须 `--no-sandbox`；Firefox 必须 X11 模式。

```bash
docker exec -u retro $C sh -c '
export HOME=/home/retro DISPLAY=:0 GDK_BACKEND=x11 MOZ_ENABLE_WAYLAND=0
chmod +x /mnt/WD4/public/software/linux/*.AppImage 2>/dev/null
nohup /mnt/WD4/public/software/linux/firefox-*.AppImage --new-window https://example.com >/tmp/ff.log 2>&1 &
sleep 10; ps aux | grep -c "[f]irefox-bin"'
```
窗口验证见 §5.2。

### 4.2 部署 `browser-picker` 脚本

> **本步骤含全部历史坑的修复**，直接照抄。完整带注释版见「附录 B」。

写到 `~/.local/bin/browser-picker`（容器内，`-u retro`），权限 755。
要点（每一条都对应 §2 的一个坑）：

1. `export GDK_BACKEND=x11` —— 弹窗必须走 X11，否则窗口不显示（坑 2）
2. `XAUTHORITY` **只在文件存在时设置** —— 该路径仅存在于战网的 pressure-vessel 命名空间
3. `DBUS_SESSION_BUS_ADDRESS` **优先继承**，其次探测 `/tmp/dbus-*` —— 切忌硬编码（每次启动会变）
4. `MOZ_ENABLE_WAYLAND=0` 仅对 Firefox 设置（坑 2）
5. **URL 用数组传参，禁止字符串替换**（坑 3）：
   ```bash
   read -r -a CMD_ARGS <<< "$cmd"
   exec "$APP_DIR/${CMD_ARGS[0]}" "${CMD_ARGS[@]:1}" "$URL"
   ```
6. 浏览器清单集中在一个 `BROWSERS` 数组，新增浏览器只改一行
7. 界面文案用**英文**（locale 非 UTF-8，中文会报错）
8. `--no-default-browser-check` 给 Firefox（坑 4）

### 4.3 注册 `.desktop`

`~/.local/share/applications/browser-picker.desktop`：
```ini
[Desktop Entry]
Version=1.0
Name=Browser Picker
Exec=/home/retro/.local/bin/browser-picker %u
Terminal=false
Type=Application
MimeType=x-scheme-handler/http;x-scheme-handler/https;text/html;
StartupNotify=false
Categories=Network;WebBrowser;
```

同时为每个浏览器建 `.desktop`（供 GIO 认为"有应用可处理"，也可被手动指定）：
```ini
[Desktop Entry]
Version=1.0
Name=Firefox
Exec=env MOZ_ENABLE_WAYLAND=0 GDK_BACKEND=x11 /mnt/WD4/public/software/linux/firefox-149.0.r20260403140140-x86_64.AppImage --new-window --no-default-browser-check %u
Terminal=false
Type=Application
Icon=/mnt/WD4/public/software/linux/firefox-149.0.r20260403140140-x86_64.AppImage
MimeType=text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;application/pdf;
StartupNotify=true
StartupWMClass=Firefox
Categories=Network;WebBrowser;
```
> `Exec` 里可以带 `env VAR=... ` 前缀；`%u` 是 .desktop 规范的 URL 占位符（**此处允许用 `%u`**，因为由桌面环境替换，不经过 bash）。

### 4.4 指定默认 handler

`~/.config/mimeapps.list`：
```ini
[Default Applications]
x-scheme-handler/http=browser-picker.desktop
x-scheme-handler/https=browser-picker.desktop
text/html=browser-picker.desktop
```
> ⚠ **不要整份覆盖**：该文件里可能还有用户的其它协议关联（例如 `x-scheme-handler/discord-<id>=discord-<id>.desktop`）。
> 正确做法是"读取既有行 → 过滤掉 http/https/text/html → 追加到新内容后面"（本包 `install-browser-picker.sh` 已实现，实测能保留 Discord 关联）。

> 若只想**直接用一个浏览器**、不要选择器，把上面三行都改成 `firefox.desktop` 即可。

### 4.5 刷新关联缓存（重要）

```bash
docker exec $C sh -c 'DEBIAN_FRONTEND=noninteractive apt-get update -qq && \
  apt-get install -y --no-install-recommends desktop-file-utils'
docker exec -u retro $C sh -c 'update-desktop-database ~/.local/share/applications/'
```
> `update-desktop-database` 属于 `desktop-file-utils`，**镜像未自带**，且容器重启后丢失 —— 每次新增/修改 `.desktop` 后都要执行。
> 若一时装不上，`mimeapps.list` 里的显式默认仍会生效，但 GIO 的"可选应用列表"会不全。

### 4.6 容器重启后的恢复动作

| 需要恢复的东西 | 是否已持久 | 动作 |
|---|---|---|
| `browser-picker`、`.desktop`、`mimeapps.list` | ✅ 持久（在 `.local`/`.config` 卷） | 无需动作 |
| 浏览器 AppImage | ✅ 持久（共享盘） | 无需动作 |
| `desktop-file-utils` / `xdotool` / `grim` 等工具 | ❌ 丢失 | 按需重装（`setup-tools.sh`） |
| Firefox 会抢默认浏览器 | ⚠️ 每次启动可能覆写 | 见 §7 排查项 4 |

---

## 5. 验证

### 5.1 调用链验证（最直接）

```bash
docker exec -u retro $C sh -c '
export HOME=/home/retro
nohup xdg-open "https://example.com/v?a=1&b=2" >/tmp/x.log 2>&1 &
sleep 5
ps aux | grep -E "[b]rowser-picker|[z]enity --list"'
```
期望看到 `browser-picker` 与 `zenity --list` 进程 → 说明选择器已被调起。

**从战网真实链路验证**（winebrowser 是战网实际用的通道）：
```bash
docker exec -u retro $C sh -c '
export HOME=/home/retro DISPLAY=:0 WINEPREFIX=/var/lutris/Games/battlenet/pfx/
WINE="/home/retro/.steam/debian-installation/steamapps/common/Proton 11.0/files/bin/wine"
nohup "$WINE" winebrowser.exe "https://example.com?a=1&b=2" >/tmp/wb.log 2>&1 &
sleep 10
ps aux | grep -E "[x]dg-open|[b]rowser-picker|[z]enity --list"'
```

### 5.2 窗口是否真的可见

```bash
# X11 窗口列表（Xwayland :0）
docker exec -u retro $C sh -c 'export DISPLAY=:0; xwininfo -root -tree | grep -iE "Choose|Firefox|Chromium"'

# sway 窗口树（wayland-1 里的 Xwayland 窗口也会出现）
docker exec -u retro $C sh -c 'export SWAYSOCK=/run/user/wolf/sway.socket WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR=/run/user/wolf
swaymsg -t get_tree | grep -E "\"name\"" | head -20'
```

**截图**（重要技巧）：
```bash
# wayland-1 无法截图（不支持 wlr-screencopy），但 wayland-2 可以！
docker exec -u retro $C sh -c 'export WAYLAND_DISPLAY=wayland-2 XDG_RUNTIME_DIR=/run/user/wolf
grim -l 0 /tmp/shot.png'
docker cp $C:/tmp/shot.png ./shot.png
```
单窗口截图（X11 窗口）：
```bash
docker exec -u retro $C sh -c 'export DISPLAY=:0
xwd -id <窗口ID> -silent -out /tmp/w.xwd && convert /tmp/w.xwd /tmp/w.png'   # 需 imagemagick
```

### 5.3 URL 完整性验证（防坑 3 回归）

用 stub 把选择器与浏览器都替换掉，做**确定性**验证：
```bash
docker exec -u retro $C sh -c '
mkdir -p /tmp/stub /tmp/fakeapp
printf "#!/bin/sh\necho Firefox\n" > /tmp/stub/zenity
printf "#!/bin/sh\necho \"argc=\$#\"; for a in \"\$@\"; do echo \"[\$a]\"; done\n" \
  > /tmp/fakeapp/firefox-149.0.r20260403140140-x86_64.AppImage
chmod +x /tmp/stub/zenity /tmp/fakeapp/firefox-149.0.r20260403140140-x86_64.AppImage
export HOME=/home/retro
PATH=/tmp/stub:$PATH APP_DIR=/tmp/fakeapp bash ~/.local/bin/browser-picker \
  "https://e.com/p?x%3D1%26y%3D2&a=1&b=2&c=3"'
```
期望：URL 作为**独立一个参数**原样输出，`&`、`%26` 一个不少。若看到 `%u` 或 URL 被拆开 → 退回 §2 坑 3。

---

## 6. 坑清单（血泪版，按踩坑顺序）

1. **xdg-open 原生不会弹"选浏览器"窗口**
   - 有默认 handler → 直接打开；无默认 → 按字母序挑第一个；完全无关联 → 弹 portal "Open With…"，但列表要 GIO 认得（依赖 `mimeinfo.cache`）。
   - 此容器里 `xdg-desktop-portal-gtk` 的 `UseIn=gnome` 不匹配 sway，**AppChooser 列表不完整**（实测弹窗但列表空）。
   - 结论：要"每次自选"，**别指望系统原生 chooser，自建 zenity 选择器**。

2. **GTK 弹窗（zenity/yad）默认不显示**
   - 症状：进程活着，但 `swaymsg -t get_tree` 与 `xwininfo` 都查不到窗口。
   - 修复：`GDK_BACKEND=x11`；必要时 `XAUTHORITY=/run/pressure-vessel/Xauthority`。
   - 若报 `Authorization required ... cannot open display: :0` → 就是 X 授权问题。

3. **URL 传参绝不用字符串替换**（本项目最隐蔽的 bug）
   - 错误写法：`cmd="${cmd//%u/$URL}"` → URL 中 `&` 被 bash 当作"替换串里的匹配引用"，全部变成 `%u`。
   - 正确：数组传参（§4.2 第 5 条）。
   - 症状表现：浏览器能开，但页面"出错"、URL 尾部是 `%uflow=login%usecure=true` 之类。

4. **Firefox/Chrome 会抢默认浏览器**
   - 首次启动会写 `mimeapps.list`，把 `x-scheme-handler/https` 改成自己，导致选择器被绕过。
   - 修复：启动参数加 `--no-default-browser-check`；被覆写后重写 `mimeapps.list`。

5. **chromium 系在容器内必须 `--no-sandbox`**，否则起不来。

6. **AppImage 需要执行位**：共享盘上的文件可能没有 `+x`，`chmod +x` 解决；且注意 AppImage 以 root 运行 Firefox 会报 "Running Firefox as root ... not supported"，必须用 `-u retro`。

7. **容器 locale 是 POSIX**：中文传给 zenity 会 `Unable to parse command line: Invalid byte sequence`，界面用英文。

8. **`/tmp` 里的东西重启即失**；`/run/pressure-vessel/` 与 `XAUTHORITY` 也随 umu 会话生成，**只在战网进程的命名空间内可见**（在普通 `docker exec` 里 `ls` 不到，这是正常的）。

9. **DBus 地址每次启动都变**（形如 `unix:path=/tmp/dbus-XXXXXXXX`）：从 `/proc/<pid>/environ` 现取，或直接继承（战网调用链已带），**不要硬编码**。

10. **grim 在 wayland-1 不可用**（`compositor doesn't support wlr-screencopy-unstable-v1`），但 **wayland-2 可以** —— 这是该容器唯一可靠的整屏截图手段。

11. **Wolf 会话容器重启后 apt 装的全丢**：诊断类工具（grim/xdotool/imagemagick/tesseract/desktop-file-utils）需重装；核心配置在持久卷，不受影响。

12. **`docker exec` 默认不转发 stdin**（写文件时的隐形坑）
    - 错误写法：`docker exec $C sh -c "cat > /path/file" <<'EOF' ... EOF` → 目标文件**变成 0 字节**，而命令本身返回成功、毫无报错。
    - 正确写法：加 `-i` —— `docker exec -i $C sh -c "cat > /path/file" <<'EOF' ... EOF`
    - 同理适用于任何需要 stdin 的写法（`tee`、`patch` 等）。
    - **防御**：写完立刻校验非空，例如
      ```bash
      docker exec $C sh -c 'for f in <文件列表>; do [ -s "$f" ] || echo "EMPTY: $f"; done'
      ```
    - 本项目实测教训：该坑一次写空了 `browser-picker.desktop`、`firefox.desktop`、`chromium.desktop`、`mimeapps.list`，把原本可用的配置写坏且无任何报错。

---

## 7. 排查手册（按用户描述定位）

| 用户说 | 先查 | 大概率原因 |
|---|---|---|
| "链接不到浏览器" / 弹 Open With 且无应用 | `mimeapps.list` 指向的 .desktop 是否存在 | 没注册可用浏览器（坑 1） |
| "浏览器打开了但页面出错" | 浏览器进程的 argv（`ps aux \| grep firefox`） | URL 被 `%u` 污染（坑 3） |
| "浏览器进程在但看不到窗口" | `swaymsg -t get_tree` 是否有该窗口 | 未强制 X11（坑 2） |
| "之前能弹选择器，现在不弹了" | `cat ~/.config/mimeapps.list` | Firefox 抢了默认（坑 4） |
| "点了没反应" | `ps aux \| grep -E "xdg-open\|browser-picker\|zenity"` | 脚本无执行位 / zenity 起不来（坑 2、6） |

---

## 8. 附录 A：一键安装脚本

见同包 `install-browser-picker.sh`（幂等，可重复执行）。用法：

```bash
# 在宿主机执行（脚本内部用 docker exec）
./install-browser-picker.sh <容器名> [会话ID]
```

## 9. 附录 B：`browser-picker` 完整脚本

见同包 `browser-picker.sh`（带注释，含全部修复）。

## 10. 附录 C：安装/诊断用工具

见同包 `setup-tools.sh`。容器重启后执行一次即可恢复诊断能力：
```bash
./setup-tools.sh <容器名>
```

## 10b. 附录 D：把方案固化进镜像（可选，适合多会话/重复部署）

同包 `image/` 提供完整 Dockerfile，已实测构建并验证。**核心约束**：Wolf 运行时用卷覆盖 `/home/retro`、`/home/retro/.config`、`/home/retro/.local`、`/var/lutris`、`/mnt/WD4/public`，**写在这些路径下的镜像文件会被挂载遮蔽**。因此固化位置必须是：

| 内容 | 固化位置（不被覆盖） |
|---|---|
| 选择器脚本 | `/usr/local/bin/browser-picker` |
| handler 注册 | `/usr/share/applications/browser-picker.desktop` |
| 系统级默认 | `/etc/xdg/mimeapps.list`（XDG_CONFIG_DIRS，优先级低于用户级） |
| 开机自愈 | `/opt/gow/startup.d/90-browser-picker.sh`（GOW 以 retro 身份 **source**；父脚本带 `set -e` → 钩子内禁用 `exit` 且须容错） |

第 4 项解决"用户级优先于系统级"的问题：每次开机把 `~/.config/mimeapps.list` 的三个键校正回选择器，并保留其他关联（如 `discord://`）。

```bash
cd image && ./build.sh                                    # 构建 gameonwhales/lutris:kaijuu-picker
./verify-image.sh gameonwhales/lutris:kaijuu-picker        # 全新卷 + 旧配置自愈验证
```

> ⚠ 另一个环境坑：**`docker run -v` 的路径由宿主机解析**，不是执行 docker 命令所在容器的路径。若在容器内调用 docker，`-v` 必须给宿主路径（用 `docker inspect "$(hostname)" --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{"\n"}}{{end}}'` 查映射）；`verify-image.sh` 已内置自动换算。

---

## 11. 交付自检清单

- [ ] **所有写入的文件均非空**（`[ -s "$f" ]`；防 `docker exec` 漏 `-i` 写出空文件，见坑 12）
- [ ] `~/.local/bin/browser-picker` 存在且 755
- [ ] `~/.local/share/applications/browser-picker.desktop` 存在，`Exec` 指向脚本
- [ ] 各浏览器 `.desktop` 的 `Exec` 路径真实存在且可执行
- [ ] `~/.config/mimeapps.list` 默认指向 `browser-picker.desktop`
- [ ] `update-desktop-database` 已跑过（有 `mimeinfo.cache`）
- [ ] `xdg-open https://example.com` → 出现 `zenity --list` 进程
- [ ] `winebrowser.exe` 链路 → 出现选择器
- [ ] 选中后浏览器进程 argv 中的 URL **完整无 `%u`**
- [ ] Firefox 启动参数含 `--no-default-browser-check`
- [ ] 截图存档（wayland-2 grim）
