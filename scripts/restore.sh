#!/usr/bin/env bash
# restore.sh — 一键恢复代理(防断联):启动 v2rayN 后立即拉起核心,不等
# 用法: bash restore.sh
# 行为:
#   1. 若 10808 已监听且连通 → 直接 OK(幂等)
#   2. 若 v2rayN 没跑 → 后台启动(无窗口),**不 sleep**,立即进入第 3 步
#   3. 立即 start.sh 拉起核心(端口就绪前系统代理可能短暂指向死端口,
#      但启动后立即拉起把窗口压到最小,不再有 8s 空窗)
#   4. 轮询端口就绪 → 确保系统代理 → 验证连通
#
# 关键修复:之前「启动 v2rayN → sleep 8s → start.sh」的空窗期,
#           v2rayN 已开系统代理但核心没起 → 全网断联。本脚本消除空窗。
set -u
SELF="${BASH_SOURCE[0]%/*}"
[ -n "$SELF" ] || SELF="."
PY="${PYTHON:-python}"

echo "restore: 开始恢复代理..."

# 1. 幂等检查:端口已监听 + 系统代理已开 → 完成
PORT_OK=$("$PY" -c "
import socket
s = socket.socket(); s.settimeout(0.3)
try:
    print(1 if s.connect_ex(('127.0.0.1', 10808)) == 0 else 0)
finally:
    s.close()
" 2>/dev/null || echo 0)
if [ "$PORT_OK" = "1" ]; then
  bash "$SELF/start.sh" >/dev/null 2>&1
  echo "restore: 代理已就绪(端口 10808 监听中)"
  exit 0
fi

# 2. v2rayN 是否在跑
CLIENT_RUN=$("$PY" -c "
import subprocess
r = subprocess.run(['tasklist'], capture_output=True, text=True, errors='replace')
print(1 if 'v2rayN.exe' in r.stdout else 0)
" 2>/dev/null || echo 0)

if [ "$CLIENT_RUN" = "0" ]; then
  echo "restore: v2rayN 未运行,后台启动(无窗口)..."
  "$PY" -c "
import subprocess
subprocess.Popen(
    [r'C:\v2rayN-windows-64\v2rayN-windows-64\v2rayN.exe'],
    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    creationflags=0x08000000,
)
print('v2rayN 启动中')
" 2>/dev/null
fi

# 3. 立即拉起核心(不等!消除空窗)
bash "$SELF/start.sh"

# 4. 轮询端口就绪(最多 15s)
for i in $(seq 1 15); do
  if "$PY" -c "
import socket
s = socket.socket(); s.settimeout(0.3)
exit(0 if s.connect_ex(('127.0.0.1', 10808)) == 0 else 1)
" 2>/dev/null; then
    echo "restore: 端口 10808 就绪(第 ${i}s)"
    # 确保系统代理
    bash "$SELF/start.sh" >/dev/null 2>&1
    echo "restore: 完成 — 代理已恢复"
    exit 0
  fi
  "$PY" -c "import time; time.sleep(1)" 2>/dev/null || true
done

echo "restore: 15s 内端口未就绪,请检查 v2rayN 是否已连接节点"
exit 1
