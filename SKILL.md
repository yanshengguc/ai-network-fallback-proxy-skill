---
name: ai-network-fallback-proxy-skill
description: 网络故障自动代理兜底 + 代理开关控制。当访问 GitHub 等外网站点出现超时/失败(DNS 解析失败、connect timeout、connection refused、SSL 错误、网络波动)时,自动检测本机 VPN 是否开启(进程+端口+实测连通三层校验),未开则自动拉起代理核心(xray)并注入代理环境变量,随后走代理并带超时和指数退避重试;支持按需自动开启/关闭代理(关闭=关 Windows 系统代理,不杀任何进程、全程后台无窗口),支持「用完自动还原」(临时开代理执行命令后自动恢复原状态,如 git push)。红线:绝不 kill v2rayN 客户端进程;输出绝不泄露节点信息。前置要求:用户必须自己已安装 VPN 客户端,本技能不提供 VPN 服务。触发词:网络不通、GitHub 打不开、外网失败、走代理、connect timeout、connection refused、代理、翻墙、检测VPN、vpn开了吗、自动开vpn、帮我开vpn、关代理、关闭代理、关vpn、开代理、用完还原、传github、git push。
version: 1.5.1
agent_created: true
---

# ai-network-fallback-proxy-skill — 网络故障自动代理兜底(AI Agent 专用)

## 用完自动还原(临时开启代理执行命令)

`scripts/run_with_proxy.sh <command...>` — 临时开启代理执行一条命令,结束后**自动还原到操作前的代理状态**:

- 操作前系统代理关闭 → 结束后自动关闭(`stop.sh`)
- 操作前系统代理开启 → 结束后保持开启,不多动
- 命令失败也还原(`trap EXIT` 保证),返回命令自身退出码

```bash
# 示例:临时开代理推送到 GitHub(HTTPS 方式依赖代理)
bash "scripts/run_with_proxy.sh" git push origin main
```

> **重要**:curl/git **不读 Windows 系统代理,只认环境变量**。因此 `run_with_proxy.sh` 除了确保代理端口可用外,还会给子命令注入 `HTTP_PROXY/HTTPS_PROXY → 127.0.0.1:10808`(仅对子进程生效,不污染当前 shell)。若只开系统代理而不注入环境变量,子命令根本不会走代理。
>
> git push 走 SSH(22 端口)时不经过 HTTP 代理,`run_with_proxy` 主要保障 HTTPS 方式的 git/clone/curl 操作。

## ⚠️ 前置条件:你必须自己拥有 VPN(硬性要求)

**本技能不提供、不安装、不配置任何 VPN 服务**,它只是「调用」你机器上已经装好的代理客户端。

- 使用前提:**你本机必须已安装 VPN 客户端**(v2rayN / Clash / 其他),且已配置好可用节点。
- 如果本机**没有安装**任何 VPN 客户端,脚本会输出 `NO_VPN_CLIENT` 并停止——**不要**绕过检测,也不要把「安装 VPN」当成技能能力。
- 向用户说明:没有自己的 VPN,本技能无法生效;需要用户先自行解决 VPN 来源。

> 区别:客户端**已装但没运行**时,本技能可以**自动拉起**它(见「自动开启」章节);但客户端**根本不存在**时,技能只会报错提示,不会代装。

## ⛔ 红线:绝不主动关闭 VPN(重要)

- 本技能所有脚本**只做「检测 / 启动 / 拉起」,绝不 kill / 停止 / 重启**任何 VPN 进程。
- **唯一例外**:`stop.sh` 在用户明确要求「关闭代理」时,只终止**代理核心**(监听代理端口的 xray 进程),**保留 v2rayN GUI 进程**——这是「只关代理,不关客户端」。
- 任何情况下都不要主动关闭用户的 v2rayN / Clash GUI 进程。
- 若需验证自动恢复能力,必须**先征求用户同意**,并在用户在场时进行。

## 自动开关(后台运行,不泄露节点)

核心控制器:`scripts/vpnctl.py`(bash 脚本均为薄封装),全程**后台无窗口**(启动核心用 `CREATE_NO_WINDOW`),输出**绝不包含节点信息**(只含端口号/进程名/PID/状态词)。

| 命令 | 作用 | 输出示例 |
|---|---|---|
| `bash start.sh` 或 `vpnctl.py on` | 开启代理:拉起核心(如需)+ 确保系统代理指向 10808 | `ALREADY_ON: 代理端口 10808 已在监听` + `sysproxy=on` |
| `bash stop.sh` 或 `vpnctl.py off` | 关闭代理:关闭 Windows 系统代理(ProxyEnable=0),不杀任何进程 | `STOPPED: 代理已关闭 (v2rayN GUI 保留)` |
| `bash stop.sh --check` | 预演关闭,不真关 | `CHECK: ... (v2rayN GUI 保留)` |
| `bash status.sh` 或 `vpnctl.py status` | 状态:进程/端口/连通性 | `VERDICT=VPN_ON` |

关键行为:
- `on` 端口已开返回 `ALREADY_ON`,但**仍会同步系统代理状态**(若之前被关闭则重新打开)。
- `off` 的语义是「**关闭代理 = 关闭系统代理**」(`ProxyEnable=0`),系统流量不再走 10808;进程(xray/v2rayN)全部保留,由 v2rayN 自行管理——**这是刻意设计**:xray 是 v2rayN 的管理员权限子进程,普通权限无法终止,且老板要求「只关代理不关进程」。
- `off` 也会尝试终止核心进程(尽力而为),权限不足时仅提示 WARN,不影响「代理已关闭」的结论。
- `off --check` 预演:报告将关闭系统代理 + 尝试终止的进程,不真执行。
- 节点安全:脚本从不读取/打印 `config.json` 内容、节点地址、密码、订阅信息;任何报错只含端口与状态。

> 关闭代理与杀进程的区别:代理生效的关键是「Windows 系统代理指向 10808」。关闭系统代理 = 流量不再走代理,即「代理已关」;而 xray 进程是否存活不影响此结论(它由 v2rayN 管理)。

## 自动开启(客户端已装但未运行时)

`start.sh` 内部调用 `vpnctl.py on`,逻辑:

1. **已可用**(`status` 判定 `VPN_ON`)→ 直接 `ALREADY_ON`,不做多余操作。
2. **客户端在跑但未连接** → 后台拉起 xray 核心(`bin/xray/xray.exe run -c binConfigs/config.json`,这是 v2rayN 自己生成的配置,绕过 GUI 让代理端口必然起来)。
3. **客户端没跑** → 报 `NO_VPN_CLIENT`,提示先自行启动 v2rayN。
4. 轮询等端口(最多 15s),成功输出 `STARTED`,失败输出 `START_TIMEOUT`。

`fetch.sh` 在检测到 VPN 未就绪(但客户端存在)时会自动调用 `start.sh` 恢复,恢复成功后才进入代理重试。

> 为什么能「绕过 GUI 直接拉起核心」:v2rayN 是 GUI 客户端,启动后**默认不会自动连接**节点(`GuiItem.AutoRun` 只是开机自启,不是自动连接),核心 xray.exe 不会自动启动、端口不会监听。但 v2rayN 每次连接时会在 `binConfigs/config.json` 生成完整可用的核心配置(含 10808 mixed 入站 + 选中节点),直接 `xray run -c` 即可让端口起来,无需 GUI 交互。

## 何时使用(触发条件)

任何**网络请求失败**的场景,按以下信号判断:

- DNS 解析失败(`Could not resolve host`)
- 连接超时(`connect timeout` / `Operation timed out` / 请求挂起超过数秒)
- 连接被拒(`Connection refused`)
- SSL/握手错误(`SSL connect error`、`Failed to connect`)
- 请求重试多次仍失败,或用户反馈「GitHub/外网打不开」

**核心原则:先直连,失败再走代理,全程带超时,绝不无限重试。**

## 本机代理环境(实测)

| 项 | 值 |
|---|---|
| 代理客户端 | v2rayN |
| SOCKS5 端口 | `127.0.0.1:10808`(混合,HTTP CONNECT 亦可用) |
| HTTP 端口 | `127.0.0.1:10809`(若已开启) |
| 环境变量 | `HTTP_PROXY=http://127.0.0.1:10808/` `HTTPS_PROXY=同`(当前 shell 已设) |

> 注意:curl 默认**不读** Windows 系统代理,只认环境变量或 `-x` 参数。Agent 子进程若未继承代理环境变量,必须显式传 `-x`。

## 标准流程

1. **检测 VPN 是否开启**:执行 `scripts/status.sh`,三层校验——① VPN 客户端进程(v2rayN/xray/clash 等)在不在运行;② 代理端口是否监听;③ 通过代理实测外网连通性(google generate_204)。输出 `VERDICT=VPN_ON / VPN_OFF / NO_PROXY_PORT / NO_VPN_CLIENT`。
   - `NO_VPN_CLIENT` → 用户没有装 VPN,直接说明前提,停止。
   - `NO_PROXY_PORT` / `VPN_OFF` → 尝试 `scripts/start.sh` 自动恢复(拉起核心);恢复失败则提示用户手动开代理/切节点,停止,不瞎重试。
2. **带超时直连**一次(connect-timeout 5s,总超时 20s)。若成功 → 正常返回,不折腾。
3. **直连失败 → 走代理重试**:用 `scripts/fetch.sh <url>`(内部自动:status 检测 → 未就绪先自动恢复 → 只走实测可用的代理端口 → 指数退避 1s/2s/4s,最多 3 次)。
4. **全部失败 → 结构化报错**:明确输出「检测结论 / 尝试过的代理 / 错误码」,提示用户检查 VPN 客户端是否运行、节点是否失效,不无限阻塞。

> 判定优先级:`NO_VPN_CLIENT` > `NO_PROXY_PORT` > `VPN_OFF` > `VPN_ON`。任何未就绪状态都先尝试自动恢复,恢复无效才返回。

## 关键参数(脚本默认,可用环境变量覆盖)

| 参数 | 默认值 | 说明 |
|---|---|---|
| 连接超时 | 5s | `--connect-timeout` |
| 单次请求总超时 | 20s | `-m` |
| 重试次数 | 3 | 指数退避:1s / 2s / 4s |
| 代理候选 | 10808 HTTP → socks5h → 10809 → 7890 → 7891 | 依次尝试 |

## 使用示例

```bash
# 检测 VPN 状态(进程 + 端口 + 实测连通)
bash "scripts/status.sh"
# 输出: client=v2rayN.exe / core=xray.exe / port=10808 / connectivity=OK / VERDICT=VPN_ON

# 开启代理(已开则 ALREADY_ON;后台无窗口拉起核心)
bash "scripts/start.sh"

# 关闭代理(只停核心,GUI 保留;--check 预演不真关)
bash "scripts/stop.sh"
bash "scripts/stop.sh" --check

# 探测本机代理端口
bash "scripts/probe.sh"

# 拉取页面:直连 → 失败自动检测/拉起代理 → 走代理 → 退避重试(最多3次)
bash "scripts/fetch.sh" "https://github.com"

# 拉取并保存内容到文件
bash "scripts/fetch.sh" "https://raw.githubusercontent.com/..." > result.txt

# 自定义重试次数
bash "scripts/fetch.sh" "https://github.com" 5

# 临时开代理执行单条命令,用完自动还原(HTTPS git push)
bash "scripts/run_with_proxy.sh" git push origin main

# 任务内多次用代理:包住整个任务脚本,任务完成才统一关闭一次
bash "scripts/run_with_proxy.sh" bash my_task.sh

# 程序化:任务开始 start.sh,任务结束 stop.sh(多次网络操作期间代理保持)

# 智能分流:国内直连(快),国外走代理;人在国外则反转
bash "scripts/smart_fetch.sh" "https://www.baidu.com"   # 国内 → 直连
bash "scripts/smart_fetch.sh" "https://github.com"      # 国外 → 走代理
NET_LOCALE=abroad bash "scripts/smart_fetch.sh" "https://github.com"  # 人在国外:国外直连
```

> **多次使用建议**:任务需多次访问外网时,用 `run_with_proxy.sh` 包住整个任务脚本,或程序化 `start.sh` 开头 / `stop.sh` 结尾——代理在整个任务期间保持开启,完成后统一关闭一次,避免每条命令反复开关。

> **智能分流(smart_fetch.sh)**:按目标域名自动选路——`NET_LOCALE=cn`(默认)国内直连、国外走代理;`NET_LOCALE=abroad` 反之。bash 内联分类毫秒级完成,直连失败自动回退代理。适用于「搜国内东西时不想走代理」的场景。

## 退出码约定

| 退出码 | 含义 | 处理建议 |
|---|---|---|
| 0 | 成功(直连或代理拿到内容;或 on/off/status 正常) | 继续原任务 |
| 1 | `start.sh`:`START_TIMEOUT`(拉起后端口/线路仍不可用);`stop.sh`:`STOP_ERROR/STOP_TIMEOUT` | 提示用户检查客户端/端口占用 |
| 2 | `NO_VPN_CLIENT` / `NO_PROXY_PORT` / `VPN_OFF`(恢复后仍不可用) | 提示用户开代理/切节点 |
| 3 | `fetch.sh`:`FETCH_FAIL`(代理在但重试后仍失败) | 提示检查线路/目标站点 |
| 4 | `NO_VPN_CLIENT`(本机没有安装 VPN 客户端) | **告知用户必须先自备 VPN**,停止 |

## 给 Agent 的执行要点

- **先用 status.sh 判断 VPN 是否真的开启**,再决定是否走代理——端口在监听 ≠ 线路通,必须看 `VERDICT`。
- **绝不主动 kill/停止 VPN 进程**;需要验证自动恢复时,先征求用户同意。
- `NO_VPN_CLIENT`(exit 4):明确告诉用户「本技能需要你自己拥有并运行 VPN 客户端」,**不要**假装能提供代理,也不要反复重试。
- 一次网络失败**不是**最终结果:status 通过后 fetch,结果成功就继续原任务,不要向用户重复报「网络错误」。
- 若输出 `VPN_OFF`/`FETCH_FAIL`,说明代理本身不可用——此时**不要**再重试,直接提示检查 VPN 客户端/节点。
- 禁止无超时地调用网络命令;禁止重试超过 5 次。
- 代理只用于请求命令本身(如 curl/git/wget),不要把它写进用户的全局配置文件(除非用户明确要求)。
- git 操作场景:`git -c http.proxy=http://127.0.0.1:10808 clone ...` 只对单条命令生效,安全。
- 脚本实现说明:`fetch.sh` 不创建临时文件(靠 curl 退出码判定),成功时 body 直接输出到 stdout;`status.sh` 支持 `VPN_SIM=no_client|no_port|no_conn` 环境变量模拟各异常分支(测试用)。
