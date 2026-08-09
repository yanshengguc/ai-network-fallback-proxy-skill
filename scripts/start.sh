#!/usr/bin/env bash
# start.sh — 开启 VPN 代理(薄封装,核心逻辑在 vpnctl.py)
# 用法: bash start.sh
# 行为: 代理端口已开 → ALREADY_ON;未开 → 后台拉起 xray 核心(无窗口),轮询等待端口
# 约束: 绝不 kill/停止 v2rayN GUI 进程;输出不含节点信息
set -u
SELF="$(cd "$(dirname "$0")" && pwd -W 2>/dev/null || pwd)"
PY="${PYTHON:-python}"
[ -x "$PY" ] || PY="python"
exec "$PY" "$SELF/vpnctl.py" on
