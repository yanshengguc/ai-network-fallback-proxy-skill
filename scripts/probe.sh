#!/usr/bin/env bash
# probe.sh — 快速探测本机代理端口是否可用(并行 socket 探测,0.3s 超时)
# 用法: bash probe.sh
# 输出: 每行一个开放端口,格式: OPEN <port> tcp;全关则 NO_PROXY_FOUND,exit 1
set -u
PY="${PYTHON:-python}"

"$PY" -c "
import socket
import threading

PORTS = [10808, 10809, 7890, 7891, 7897, 1080, 8888]
found = []

def check(p):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(0.3)
    try:
        if s.connect_ex(('127.0.0.1', p)) == 0:
            found.append(p)
    except Exception:
        pass
    finally:
        s.close()

threads = [threading.Thread(target=check, args=(p,)) for p in PORTS]
for t in threads: t.start()
for t in threads: t.join()

for p in sorted(found):
    print('OPEN %d tcp' % p)
if not found:
    print('NO_PROXY_FOUND')
    raise SystemExit(1)
" || exit $?
