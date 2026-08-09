#!/usr/bin/env bash
# probe.sh — 探测本机代理端口是否可用
# 用法: bash probe.sh
# 输出: 每行一个开放端口,格式: OPEN <port> <type>

PORTS=(10808 10809 7890 7891 7897 1080 8888)
FOUND=0

for p in "${PORTS[@]}"; do
  if (exec 3<>"/dev/tcp/127.0.0.1/$p") 2>/dev/null; then
    exec 3>&- 3<&- 2>/dev/null
    echo "OPEN $p tcp"
    FOUND=1
  fi
done

if [ "$FOUND" -eq 0 ]; then
  echo "NO_PROXY_FOUND"
  exit 1
fi
