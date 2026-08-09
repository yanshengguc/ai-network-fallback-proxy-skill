#!/usr/bin/env bash
# fetch.sh — 带超时 + 自动代理兜底 + 指数退避重试的请求工具
# 用法: bash fetch.sh <url> [max_retries=3]
# 流程: 先真直连(清代理环境变量,带超时) → 失败则检测/拉起代理 → 走代理 → 退避重试
# 输出: 成功时 HTTP body;失败时输出 NO_VPN_CLIENT / VPN_NOT_READY / FETCH_FAIL + 错误信息
# 说明: 无临时文件(靠 curl 退出码判断);延时走 python(环境可能无 sleep 命令)

set -u
URL="${1:?usage: fetch.sh <url> [max_retries=3]}"
MAX_RETRIES="${2:-3}"
CONNECT_TIMEOUT="${FETCH_CONNECT_TIMEOUT:-5}"
TOTAL_TIMEOUT="${FETCH_TOTAL_TIMEOUT:-20}"
LAST_ERR=""
PY="${PYTHON:-python}"

# 代理候选列表:优先 HTTP,再 SOCKS5 变体(10808 实测为混合端口,HTTP CONNECT 可用)
PROXIES=(
  "http://127.0.0.1:10808"
  "socks5h://127.0.0.1:10808"
  "http://127.0.0.1:10809"
  "socks5h://127.0.0.1:10809"
  "http://127.0.0.1:7890"
  "http://127.0.0.1:7891"
  "socks5h://127.0.0.1:1080"
)

nap() { "$PY" -c "import time; time.sleep($1)" 2>/dev/null || true; }

# 单次尝试:成功时 body 输出到 stdout 并返回 0,失败时记录 LAST_ERR 返回 1。$1=代理(空串=真直连)
try_once() {
  local px="$1" out rc
  if [ -z "$px" ]; then
    # 真直连:清空代理环境变量 + 短超时(直连失败要快速转代理,不能白等 20s)
    out=$(env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
        -u ALL_PROXY -u all_proxy \
        curl -fsS -m "${DIRECT_TIMEOUT:-8}" --connect-timeout "${DIRECT_CONNECT_TIMEOUT:-3}" \
        -w $'\n__RC=%{http_code}' "$URL" 2>&1)
  else
    out=$(curl -fsS -m "$TOTAL_TIMEOUT" --connect-timeout "$CONNECT_TIMEOUT" \
      -x "$px" -w $'\n__RC=%{http_code}' "$URL" 2>&1)
  fi
  rc=$?
  if [ "$rc" -eq 0 ]; then
    printf '%s\n' "$out" | sed '$d'
    return 0
  fi
  LAST_ERR="$out"
  return 1
}

# 直连尝试(真直连,国内目标通常一次成功)
if try_once ""; then
  exit 0
fi

# 直连失败 → 单次状态检测(QUICK:只查端口,不重复连通性探测,省 1-4s)
STATUS=$(QUICK=1 bash "$(dirname "$0")/status.sh" 2>/dev/null) || true
VERDICT=$(echo "$STATUS" | grep "^VERDICT=" | cut -d= -f2)
HINT=$(echo "$STATUS" | grep "^hint=" | cut -d= -f2-)
ACTIVE_PORT=$(echo "$STATUS" | grep "^port=" | cut -d= -f2)

if [ "$VERDICT" = "NO_VPN_CLIENT" ]; then
  echo "NO_VPN_CLIENT: 本技能需要你自己已安装并运行 VPN 客户端(v2rayN/Clash 等),且配置好节点。"
  echo "hint: $HINT"
  echo "last_error: $LAST_ERR"
  exit 4
fi
if [ "$VERDICT" != "VPN_ON" ]; then
  # VPN 未就绪 → 尝试自动开启代理(后台拉起核心,不越权)
  START_OUT=$(bash "$(dirname "$0")/start.sh" 2>&1 || true)
  if echo "$START_OUT" | grep -qE "STARTED|ALREADY_ON|sysproxy"; then
    ACTIVE_PORT=$(echo "$START_OUT" | grep "^port=" | cut -d= -f2)
    [ -z "$ACTIVE_PORT" ] || [ "$ACTIVE_PORT" = "NONE" ] && ACTIVE_PORT=10808
  else
    echo "VPN_NOT_READY: $VERDICT"
    echo "hint: $HINT"
    echo "start_result: $(echo "$START_OUT" | tail -3)"
    echo "last_error: $LAST_ERR"
    exit 2
  fi
fi

# 走代理 + 指数退避重试(只尝试实测可用的代理端口)
attempt=0
while [ "$attempt" -lt "$MAX_RETRIES" ]; do
  for px in "${PROXIES[@]}"; do
    # 精确匹配端口号,防止 10808 误匹配 1080
    port="${px##*:}"
    if [ "$port" != "$ACTIVE_PORT" ]; then
      continue
    fi
    if try_once "$px"; then
      exit 0
    fi
  done
  attempt=$((attempt + 1))
  if [ "$attempt" -lt "$MAX_RETRIES" ]; then
    nap $((2 ** attempt))
  fi
done

echo "FETCH_FAIL: direct + ${MAX_RETRIES} proxy retries failed for $URL (active_port: ${ACTIVE_PORT:-none})"
echo "last_error: $LAST_ERR"
exit 3
