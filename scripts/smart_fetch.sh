#!/usr/bin/env bash
# smart_fetch.sh — 智能分流拉取 + 任务内代理状态跟随
# 用法: bash smart_fetch.sh <url> [max_retries=3]
#   bash smart_fetch.sh "https://www.baidu.com"     # 国内 → 直连;若代理是本工具开的则先关闭
#   bash smart_fetch.sh "https://github.com"        # 国外 → 自动开启并走代理
#   NET_LOCALE=abroad bash smart_fetch.sh "https://github.com"  # 人在国外:国外直连,国内走代理
#
# 分流规则:
#   NET_LOCALE=cn(默认):   国内目标直连;国外目标走代理;未知目标先直连失败再代理
#   NET_LOCALE=abroad:     国外目标直连;国内目标走代理;未知目标先直连失败再代理
#
# 任务跟随(核心新增):同一任务内多次调用时,代理状态随目标动态切换
#   - 目标国外:确保代理开启(记录 tool_opened=1)
#   - 目标国内:若代理是「本工具刚开的」(tool_opened=1),自动关闭回到直连;
#              若代理是用户手动开的,保持不动,绝不误关
#   - 状态文件 .proxy_state 记录任务起始状态 + 是否本工具开启
#   - 与 run_with_proxy.sh 搭配:任务结束统一还原并清理状态文件
#
# 速度策略:
#   - 分类 bash 内联(零 fork、零 Python);目录用 BASH_SOURCE 免 fork
#   - 直连时显式清空代理环境变量
#   - 状态判断用 bash 读文件(毫秒级),仅在需要开关时才调 vpnctl
# 退出码: 0=成功;2=需代理但代理不可用;3=全部失败;4=无 VPN 客户端
set -u
SELF="${BASH_SOURCE[0]%/*}"
[ -n "$SELF" ] || SELF="."
URL="${1:?usage: smart_fetch.sh <url> [max_retries=3]}"
MAX_RETRIES="${2:-3}"
LOCALE="${NET_LOCALE:-cn}"
STATE_FILE="$SELF/.proxy_state"

# ---------- 状态文件读写(bash,毫秒级) ----------
state_load() {
  # 返回: task_started=0/1  tool_opened=0/1
  task_started=0; tool_opened=0
  [ -f "$STATE_FILE" ] || return 0
  # shellcheck disable=SC1090
  . "$STATE_FILE" 2>/dev/null || true
}
state_save() {
  printf 'task_started=%s\ntool_opened=%s\n' "$task_started" "$tool_opened" > "$STATE_FILE"
}

# ---------- 域名分类(bash 内联) ----------
HOST="${URL#*://}"
HOST="${HOST%%/*}"
HOST="${HOST%%\?*}"
HOST="${HOST%%\#*}"
case "$HOST" in *:[0-9]*) HOST="${HOST%:*}" ;; esac

CLASS="unknown"
case "$HOST" in
  *.cn|*.中国) CLASS=cn ;;
  *.*.*.*)
    if [[ "$HOST" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then CLASS=foreign; fi ;;
esac
if [ "$CLASS" = "unknown" ]; then
  main="${HOST##*.}"
  main2="${HOST%.$main}"
  main2="${main2##*.}.$main"
  case "$main2" in
    baidu.com|taobao.com|tmall.com|jd.com|qq.com|weibo.com|zhihu.com|bilibili.com|douyin.com|163.com|126.com|sina.com.cn|sohu.com|csdn.net|aliyun.com|alibaba.com|tencent.com|youku.com|iqiyi.com|meituan.com|ctrip.com|12306.cn|gitee.com|aliyuncs.com|myqcloud.com|wps.cn|cnblogs.com|juejin.cn|nowcoder.com|oschina.net|douban.com|zhipin.com|ximalaya.com|kuaishou.com|xiaohongshu.com|cctv.com|people.com.cn|hupu.com|acfun.cn)
      CLASS=cn ;;
    github.com|githubusercontent.com|github.io|gitlab.com|bitbucket.org|google.com|googleapis.com|gstatic.com|youtube.com|ytimg.com|googlevideo.com|twitter.com|x.com|twimg.com|facebook.com|instagram.com|telegram.org|t.me|stackoverflow.com|npmjs.com|pypi.org|python.org|docker.com|docker.io|kubernetes.io|microsoft.com|apple.com|icloud.com|amazon.com|cloudflare.com|cloudfront.net|openai.com|anthropic.com|huggingface.co|vercel.com|netlify.com|jetbrains.com|wikipedia.org|wikimedia.org|medium.com|reddit.com|linkedin.com|paypal.com|notion.so|slack.com|discord.com|zoom.us|mozilla.org|kernel.org|debian.org|ubuntu.com|apache.org|spring.io|redis.io|mongodb.com|mysql.com|postgresql.org|rust-lang.org|golang.org|nodejs.org|v2ray.com|v2fly.org)
      CLASS=foreign ;;
  esac
fi

echo "route: $URL [$CLASS] locale=$LOCALE" >&2

# 决定是否走代理
use_proxy=0
if [ "$LOCALE" = "cn" ]; then
  [ "$CLASS" = "foreign" ] && use_proxy=1
elif [ "$LOCALE" = "abroad" ]; then
  [ "$CLASS" = "cn" ] && use_proxy=1
fi

# ---------- 任务跟随:按需开关系统代理 ----------
state_load
if [ "$use_proxy" = "1" ]; then
  # 需要代理:确保开启(幂等;记录为本工具开启)
  OUT=$(bash "$SELF/start.sh" 2>&1) || { echo "smart: 无法开启代理: $OUT" >&2; exit 2; }
  tool_opened=1
  task_started=1
  state_save
else
  # 不需要代理:若代理是本工具刚开的 → 关掉回到直连;用户手动开的则不碰
  if [ "${tool_opened:-0}" = "1" ]; then
    bash "$SELF/stop.sh" >/dev/null 2>&1
    tool_opened=0
    state_save
    echo "smart: 切回直连(本任务开的代理已关闭)" >&2
  fi
fi

# ---------- 拉取 ----------
if [ "$use_proxy" = "0" ]; then
  if env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
      -u ALL_PROXY -u all_proxy \
      curl -fsS -m "${FETCH_TOTAL_TIMEOUT:-20}" --connect-timeout "${FETCH_CONNECT_TIMEOUT:-5}" \
      "$URL" 2>/dev/null; then
    exit 0
  fi
  # 直连失败 → 回退 fetch.sh(自动检测/拉起代理 + 退避重试)
  exec bash "$SELF/fetch.sh" "$URL" "$MAX_RETRIES"
fi

# 走代理(复用 fetch.sh)
exec bash "$SELF/fetch.sh" "$URL" "$MAX_RETRIES"
