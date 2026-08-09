#!/usr/bin/env bash
# stop.sh — 关闭 VPN 代理(只停代理,不杀 v2rayN GUI 进程)
# 用法: bash stop.sh            # 关闭代理
#       bash stop.sh --check    # 预演:只报告将终止的进程,不真正关闭
# 行为: 终止监听代理端口(10808)的 xray 核心进程,v2rayN.exe 保留;等待端口释放
# 约束: 绝不 kill/停止 v2rayN GUI 进程;输出不含节点信息
set -u
SELF="${BASH_SOURCE[0]%/*}"; [ -n "$SELF" ] || SELF="."
PY="${PYTHON:-C:/Users/yansheng/.workbuddy/binaries/python/versions/3.13.12/python.exe}"
[ -x "$PY" ] || PY="python"
exec "$PY" "$SELF/vpnctl.py" off "$@"
