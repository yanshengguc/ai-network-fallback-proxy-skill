#!/usr/bin/env bash
# smart_fetch.sh — 智能分流拉取:国内直连(快),国外走代理;人在国外则反转
# 用法: bash smart_fetch.sh <url> [max_retries=3]
#   bash smart_fetch.sh "https://www.baidu.com"     # 国内 → 直连,最快
#   bash smart_fetch.sh "https://github.com"        # 国外 → 自动走代理
#   NET_LOCALE=abroad bash smart_fetch.sh "https://github.com"  # 人在国外:国外直连
#
# 分流规则:
#   NET_LOCALE=cn(默认):   国内目标直连;国外目标走代理;未知目标先直连失败再代理
#   NET_LOCALE=abroad:     国外目标直连;国内目标走代理;未知目标先直连失败再代理
#
# 速度策略:
#   - 分类用 bash 内联(零 fork、零 Python 启动,毫秒级)
#   - 目录用 ${BASH_SOURCE[0]} 直接取,避免 cd/pwd 的 fork 开销(Windows Git Bash 极慢)
#   - 直连时显式清空代理环境变量,不做任何代理探测
#   - 走代理复用 fetch.sh(含超时+退避重试)
# 退出码: 0=成功;2=需代理但代理不可用;3=全部失败;4=无 VPN 客户端
set -u
# 用 BASH_SOURCE 取脚本目录(避免 cd/pwd fork 开销)
SELF="${BASH_SOURCE[0]%/*}"
[ -n "$SELF" ] || SELF="."
URL="${1:?usage: smart_fetch.sh <url> [max_retries=3]}"
MAX_RETRIES="${2:-3}"
LOCALE="${NET_LOCALE:-cn}"

# ---------- 域名分类(bash 内联,零启动开销) ----------
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

# 决定是否走代理:cn 环境国内直连国外代理;abroad 环境相反;unknown 先直连
use_proxy=0
if [ "$LOCALE" = "cn" ]; then
  [ "$CLASS" = "foreign" ] && use_proxy=1
elif [ "$LOCALE" = "abroad" ]; then
  [ "$CLASS" = "cn" ] && use_proxy=1
fi

if [ "$use_proxy" = "0" ]; then
  # 直连:显式清空代理环境变量(curl 会读 HTTP_PROXY,否则「直连」名不副实且慢)
  if env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
      -u ALL_PROXY -u all_proxy \
      curl -fsS -m "${FETCH_TOTAL_TIMEOUT:-20}" --connect-timeout "${FETCH_CONNECT_TIMEOUT:-5}" \
      "$URL" 2>/dev/null; then
    exit 0
  fi
  # 直连失败 → 回退到 fetch.sh(自动检测/拉起代理 + 退避重试)
  exec bash "$SELF/fetch.sh" "$URL" "$MAX_RETRIES"
fi

# 走代理(复用 fetch.sh:内部 status → 自动开 → 注入环境变量 → 退避重试)
exec bash "$SELF/fetch.sh" "$URL" "$MAX_RETRIES"
