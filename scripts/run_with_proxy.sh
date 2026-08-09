#!/usr/bin/env bash
# run_with_proxy.sh — 临时开启代理执行命令,结束后自动还原到操作前的代理状态
# 用法: bash run_with_proxy.sh <command...>
#   bash run_with_proxy.sh git push origin main
#   bash run_with_proxy.sh curl -s https://github.com
#
# 行为:
#   1. 记录操作前代理状态(系统代理 ProxyEnable + 环境变量)
#   2. 确保代理端口可用(vpnctl.py on,幂等)
#   3. 给子命令注入代理环境变量(HTTP_PROXY/HTTPS_PROXY → 10808),执行命令
#   4. 若操作前代理是关闭的 → 自动关闭(vpnctl.py off),恢复原状
#   5. 返回命令的退出码
#
# 关键:curl/git 不读 Windows 系统代理,只认环境变量 —— 所以必须注入
#      HTTP_PROXY/HTTPS_PROXY,否则子命令根本不会走代理。
# 安全性:全程不读取/打印节点信息;只动系统代理开关 + 子进程环境变量,
#         不改 git 全局配置,不杀任何进程;命令结束后必然还原(trap 保证)。
set -u
SELF="${BASH_SOURCE[0]%/*}"; [ -n "$SELF" ] || SELF="."
PY="${PYTHON:-C:/Users/yansheng/.workbuddy/binaries/python/versions/3.13.12/python.exe}"
[ -x "$PY" ] || PY="python"

[ $# -ge 1 ] || { echo "usage: run_with_proxy.sh <command...>"; exit 64; }

# 读取操作前系统代理状态
PROXY_BEFORE=$("$PY" -c "
import winreg
k = winreg.OpenKey(winreg.HKEY_CURRENT_USER, r'Software\Microsoft\Windows\CurrentVersion\Internet Settings')
try:
    print(winreg.QueryValueEx(k, 'ProxyEnable')[0])
except FileNotFoundError:
    print(0)
" 2>/dev/null || echo 0)

# 确保代理端口可用(幂等:已开则 ALREADY_ON)
bash "$SELF/start.sh" >/dev/null 2>&1 || { echo "RUN_WITH_PROXY: 无法开启代理"; exit 2; }

# 代理端点(从环境变量取已配置的,否则默认 10808)
PROXY_URL="${HTTP_PROXY:-http://127.0.0.1:10808}"

# 执行命令并记录退出码(trap 保证还原即使中途退出)
CMD_RC=0
restore() {
  if [ "${PROXY_BEFORE:-0}" = "0" ]; then
    bash "$SELF/stop.sh" >/dev/null 2>&1
    echo "restored: 操作前代理为关闭,已自动关闭代理"
  fi
  # 清理 smart_fetch 的任务状态文件,保证下次任务从干净状态开始
  rm -f "$SELF/.proxy_state" 2>/dev/null
}
trap restore EXIT

# 注入代理环境变量后执行(仅对子命令生效,不污染当前 shell)
HTTP_PROXY="$PROXY_URL" HTTPS_PROXY="$PROXY_URL" \
http_proxy="$PROXY_URL" https_proxy="$PROXY_URL" \
ALL_PROXY="$PROXY_URL" all_proxy="$PROXY_URL" \
NO_PROXY="localhost,127.0.0.1,::1" no_proxy="localhost,127.0.0.1,::1" \
"$@"
CMD_RC=$?
exit $CMD_RC
