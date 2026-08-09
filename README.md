# network-fallback-proxy

网络故障自动代理兜底工具集 —— 让 AI Agent 或命令行任务在访问 GitHub 等外网站点遇到网络波动时,自动检测并启用本机代理(v2rayN/Clash 等),带超时与退避重试,且「用完自动还原」,不会卡死任务、不会干扰你的代理客户端。

> ⚠️ 前置要求:本工具**不提供 VPN 服务**。你需要自己已经安装并运行 VPN 客户端(v2rayN / Clash 等)且配置好节点,本工具只是「调用」你已有的代理。

## 特性

- 🔍 **三层状态检测**:VPN 客户端进程 → 代理端口 → 实测外网连通性(google generate_204),确认「真的通」而不是「端口在」
- 🚀 **自动开启**:需要代理时未开启 → 自动拉起 xray 核心(用 v2rayN 生成的配置,绕过 GUI),端口必然起来
- ⏻ **自动关闭**:按需关闭 = 关闭 Windows 系统代理(`ProxyEnable=0`),**不杀任何进程**,v2rayN GUI 保留
- 🔄 **用完自动还原**:`run_with_proxy.sh` 临时开代理执行命令,结束后自动还原到操作前的状态(操作前关 → 结束关;操作前开 → 保持开)
- ⏱ **永不卡死**:所有网络命令带超时(5s/20s),失败指数退避重试(1s/2s/4s,最多 3 次),绝不无限阻塞
- 🔒 **隐私安全**:脚本从不读取/打印节点地址、密码、订阅信息;只动系统代理开关 + 子进程环境变量,不改 git 全局配置

## 文件结构

```
network-fallback-proxy/
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
```

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
