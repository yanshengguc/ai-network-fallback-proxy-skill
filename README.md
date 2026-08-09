# network-fallback-proxy

网络故障自动代理兜底工具集 —— 让 AI Agent 或命令行任务在访问 GitHub 等外网站点遇到网络波动时,自动检测并启用本机代理(v2rayN/Clash 等),带超时与退避重试,且「用完自动还原」,不会卡死任务、不会干扰你的代理客户端。

> ⚠️ 前置要求:本工具**不提供 VPN 服务**。你需要自己已经安装并运行 VPN 客户端(v2rayN / Clash 等)且配置好节点,本工具只是「调用」你已有的代理。

## 安装(快速开始,不限于 WorkBuddy)

**任何 AI Agent 或命令行环境都能用**——本工具只是「一个 SKILL.md + 几个 bash/python 脚本」,没有框架绑定。

```bash
# 方式一:git clone(推荐,方便更新)
git clone https://github.com/yanshengguc/ai-network-fallback-proxy-skill.git
#    → WorkBuddy 用户:放到用户技能目录即可被识别
#      Windows: %USERPROFILE%\.workbuddy\skills\network-fallback-proxy\
#      Linux/macOS: ~/.workbuddy/skills/ai-network-fallback-proxy-skill/
#    → 其他 Agent:任意目录,直接调用 scripts/ 下的脚本

# 方式二:仅下载脚本
curl -sL https://github.com/yanshengguc/ai-network-fallback-proxy-skill/archive/refs/heads/main.tar.gz | tar -xz
```

安装后验证:`bash scripts/status.sh` 应输出 `VERDICT=VPN_ON/OFF` 及端口状态。

> 个性化:默认代理端口 10808、v2rayN 路径 `C:\v2rayN-windows-64\...`,可通过环境变量覆盖:`PROXY_PORT`、`V2RAYN_DIR`、`PYTHON`。兼容 Clash(7890)等:改 `scripts/probe.sh` 的 PORTS 与 `scripts/vpnctl.py` 的 `V2RAYN_DIR/PORT` 即可。

## 特性

- 🔍 **三层状态检测**:VPN 客户端进程 → 代理端口 → 实测外网连通性(google generate_204),确认「真的通」而不是「端口在」
- 🚀 **自动开启**:需要代理时未开启 → 自动拉起 xray 核心(用 v2rayN 生成的配置,绕过 GUI),端口必然起来
- ⏻ **自动关闭**:按需关闭 = 关闭 Windows 系统代理(`ProxyEnable=0`),**不杀任何进程**,v2rayN GUI 保留
- 🔄 **用完自动还原**:`run_with_proxy.sh` 临时开代理执行命令,结束后自动还原到操作前的状态(操作前关 → 结束关;操作前开 → 保持开)
- ⏱ **永不卡死**:所有网络命令带超时(5s/20s),失败指数退避重试(1s/2s/4s,最多 3 次),绝不无限阻塞
- 🔒 **隐私安全**:脚本从不读取/打印节点地址、密码、订阅信息;只动系统代理开关 + 子进程环境变量,不改 git 全局配置

## 文件结构

```
ai-network-fallback-proxy-skill/
├── SKILL.md          # 技能说明(触发条件、流程、退出码、Agent 执行要点)
├── scripts/
│   ├── vpnctl.py     # 核心控制器:on / off / status(后台无窗口)
│   ├── start.sh      # 开启代理(薄封装)
│   ├── stop.sh       # 关闭代理(薄封装,支持 --check 预演)
│   ├── status.sh     # 状态检测(薄封装)
│   ├── fetch.sh      # 带超时+代理兜底+退避重试的请求工具
│   ├── probe.sh      # 探测本机代理端口
│   └── run_with_proxy.sh  # 临时开代理执行命令,用完自动还原
```

## 快速开始

```bash
# 1. 检测当前代理状态
bash scripts/status.sh
# 输出: client=v2rayN.exe / core=xray.exe / port=10808 / connectivity=OK / VERDICT=VPN_ON

# 2. 开启代理(已开则 ALREADY_ON)
bash scripts/start.sh

# 3. 关闭代理(只关系统代理,不杀进程;--check 预演)
bash scripts/stop.sh
bash scripts/stop.sh --check

# 4. 带兜底拉取页面:直连 → 失败自动走代理 → 退避重试
bash scripts/fetch.sh "https://github.com"

# 5. 临时开代理执行命令,用完自动还原(如 HTTPS 方式 git push)
bash scripts/run_with_proxy.sh git push origin main

# 6. 任务内多次用代理:包住整个任务脚本,任务完成才统一关闭一次
#    (脚本内多次 curl/git 全程走代理,不会每条命令开关一次)
bash scripts/run_with_proxy.sh bash my_task.sh

# 7. Agent/程序化调用:一次开、多次用、最后关
bash scripts/start.sh        # 任务开始:开代理
...  # 任务中的多次网络操作,全部走代理
bash scripts/stop.sh         # 任务结束:统一关闭

# 8. 智能分流:国内直连(快),国外走代理;人在国外则反转
bash scripts/smart_fetch.sh "https://www.baidu.com"   # 国内 → 直连,最快
bash scripts/smart_fetch.sh "https://github.com"      # 国外 → 自动走代理
NET_LOCALE=abroad bash scripts/smart_fetch.sh "https://github.com"  # 人在国外:国外直连
```

> **多次使用建议**:如果任务需要多次访问外网,用 `run_with_proxy.sh` 包住**整个任务脚本**(或程序化地 `start.sh` 开头 / `stop.sh` 结尾),代理在整个任务期间保持开启,最后统一关闭一次——而不是每条命令单独开关,避免反复开关的开销。

> **智能分流(smart_fetch.sh)**:根据目标域名自动选择路径——`NET_LOCALE=cn`(默认)时国内目标**直连**(不碰代理,速度快),国外目标**走代理**;`NET_LOCALE=abroad`(人在国外)则**相反**(国外直连、国内走代理)。分类是 bash 内联毫秒级完成,直连失败会自动回退走代理。域名分类见 `scripts/smart_fetch.sh` 内嵌列表(常见国内外站点 + `.cn/.中国` 后缀 + IP 判定)。

> **任务内动态跟随**:同一任务里多次调用 `smart_fetch.sh` 时,代理状态随目标动态切换——目标国外自动开代理、切到国内目标自动关回直连(仅当代理是本工具刚开的;用户手动开的代理**绝不误关**)、再国外再开。任务结束用 `run_with_proxy.sh` 包裹可统一还原并清理状态。适合「搜索国内内容时不想挂代理、访问国外时自动走代理」的场景。

## 关键设计说明

- **curl/git 不读 Windows 系统代理,只认环境变量**:`run_with_proxy.sh` 和 `fetch.sh` 都会给子命令注入 `HTTP_PROXY/HTTPS_PROXY → 127.0.0.1:10808`(仅对子进程生效,不污染当前 shell)。
- **代理端口默认 10808**(v2rayN SOCKS5 混合端口,HTTP CONNECT 亦可用);v2rayN 安装目录可通过环境变量 `V2RAYN_DIR` 覆盖,Python 解释器通过 `PYTHON` 覆盖。
- **git push 走 SSH(22 端口)时不经过 HTTP 代理**,`run_with_proxy` 主要保障 HTTPS 方式的 git/clone/curl 操作。

## 退出码约定

| 退出码 | 含义 |
|---|---|
| 0 | 成功(直连或代理拿到内容;或 on/off/status 正常) |
| 1 | `start.sh`:START_TIMEOUT;`stop.sh`:STOP_ERROR/STOP_TIMEOUT |
| 2 | NO_VPN_CLIENT / NO_PROXY_PORT / VPN_OFF(恢复后仍不可用) |
| 3 | fetch.sh:FETCH_FAIL(代理在但重试后仍失败) |
| 4 | NO_VPN_CLIENT(本机没有安装 VPN 客户端) |

## 兼容性

- 当前面向 **Windows + v2rayN**(已实测);Clash(7890)/其他客户端可通过调整脚本中的端口与路径配置适配
- 依赖:bash、curl、python3(tasklist/netstat 为 Windows 内置)
