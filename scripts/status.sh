#!/usr/bin/env bash
# status.sh — VPN 状态检测(薄封装,核心逻辑在 vpnctl.py)
# 用法: bash status.sh
# 输出: client= / core= / port= / connectivity= / VERDICT=VPN_ON|VPN_OFF|NO_VPN_CLIENT
# 约束: 输出不含节点信息
set -u
SELF="${BASH_SOURCE[0]%/*}"; [ -n "$SELF" ] || SELF="."
PY="${PYTHON:-C:/Users/yansheng/.workbuddy/binaries/python/versions/3.13.12/python.exe}"
[ -x "$PY" ] || PY="python"
OUT=$("$PY" "$SELF/vpnctl.py" status) || true
RC=$?
echo "$OUT"
# 兼容旧接口:补 client 为 NONE 时的 NO_VPN_CLIENT 判定
if echo "$OUT" | grep -q "^client=NONE"; then
  echo "VERDICT=NO_VPN_CLIENT"
  echo "hint=本机未检测到运行中的 VPN 客户端(v2rayN/Clash 等)。本技能不提供 VPN 服务,请先自行安装并启动 VPN 客户端、配置好节点后再试。"
  exit 2
fi
exit $RC
