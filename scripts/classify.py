#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
classify.py — 本地域名分类:判断目标是国内还是国外(纯本地,毫秒级)
用法: python classify.py <host 或 url>
输出: cn | foreign | unknown(exit 0)
说明: 通过 后缀规则 + 常见域名列表 判断,不做网络请求,速度极快。
      用于智能分流:国内目标直连,国外目标走代理;人在国外则反转。
"""
import sys

# 国内域名后缀
CN_SUFFIXES = (
    ".cn", ".com.cn", ".net.cn", ".org.cn", ".edu.cn",
    ".gov.cn", ".ac.cn", ".中国",
)

# 常见国内域名(主域名即可,子域自动继承)
CN_DOMAINS = {
    "baidu.com", "taobao.com", "tmall.com", "jd.com", "qq.com", "weixin.qq.com",
    "weibo.com", "zhihu.com", "bilibili.com", "douyin.com", "163.com", "126.com",
    "sina.com.cn", "sohu.com", "csdn.net", "aliyun.com", "alibaba.com", "taobao.org",
    "tencent.com", "qq.com.cn", "bing.com.cn", "youku.com", "iqiyi.com", "vip.com",
    "meituan.com", "dianping.com", "ele.me", "ctrip.com", "12306.cn", "zol.com.cn",
    "hupu.com", "acfun.cn", "ximalaya.com", "kuaishou.com", "xiaohongshu.com",
    "cctv.com", "people.com.cn", "xinhuanet.com", "chinadaily.com.cn", "gitee.com",
    "aliyuncs.com", "myqcloud.com", "wps.cn", "kingsoft.com", "youdao.com",
    "cnblogs.com", "juejin.cn", "nowcoder.com", "luogu.com.cn", "oschina.net",
    "qq.com.cn", "douban.com", "smzdm.com", "zhipin.com", "liepin.com",
}

# 常见国外域名
FOREIGN_DOMAINS = {
    "github.com", "githubusercontent.com", "github.io", "gitlab.com", "bitbucket.org",
    "google.com", "googleapis.com", "gstatic.com", "google.com.hk", "youtube.com",
    "ytimg.com", "googlevideo.com", "twitter.com", "x.com", "twimg.com",
    "facebook.com", "instagram.com", "whatsapp.com", "telegram.org", "t.me",
    "stackoverflow.com", "stackexchange.com", "npmjs.com", "pypi.org", "python.org",
    "docker.com", "docker.io", "kubernetes.io", "microsoft.com", "msn.com",
    "apple.com", "icloud.com", "amazon.com", "aws.amazon.com", "cloudflare.com",
    "cloudfront.net", "openai.com", "anthropic.com", "huggingface.co", "vercel.com",
    "netlify.com", "herokuapp.com", "jetbrains.com", "jetbrains.net", "oracle.com",
    "ibm.com", "intel.com", "nvidia.com", "amd.com", "adobe.com", "spotify.com",
    "netflix.com", "wikipedia.org", "wikimedia.org", "medium.com", "reddit.com",
    "quora.com", "linkedin.com", "paypal.com", "stripe.com", "figma.com",
    "notion.so", "slack.com", "discord.com", "zoom.us", "dropbox.com",
    "v2ray.com", "v2fly.org", "xtls.github.io", "rust-lang.org", "golang.org",
    "nodejs.org", "reactjs.org", "vuejs.org", "typescriptlang.org", "deno.land",
    "mozilla.org", "gnu.org", "kernel.org", "debian.org", "ubuntu.com",
    "archlinux.org", "fedora.org", "jenkins.io", "grafana.com", "elastic.co",
    "mongodb.com", "mysql.com", "postgresql.org", "redis.io", "apache.org",
    "maven.apache.org", "spring.io", "jetbrains.com", "kotlinlang.org", "flutter.dev",
    "dart.dev", "swift.org", "ruby-lang.org", "php.net", "perl.org", "lua.org",
    "torproject.org", "proton.me", "duckduckgo.com", "brave.com", "opera.com",
}


def classify(host):
    host = host.strip().lower()
    # 去掉协议和路径
    if "://" in host:
        host = host.split("://", 1)[1]
    host = host.split("/", 1)[0].split("?", 1)[0].split("#", 1)[0]
    # 去掉端口
    if ":" in host and host.count(":") == 1:
        host = host.split(":", 1)[0]
    # IP 地址:默认 foreign(国外 IP 走代理更稳)
    parts = host.split(".")
    if all(p.isdigit() for p in parts) and len(parts) == 4:
        return "foreign"
    # 后缀判断(取最后两级)
    for suf in CN_SUFFIXES:
        if host.endswith(suf):
            return "cn"
    # 主域名判断(取最后两级)
    if len(parts) >= 2:
        main = ".".join(parts[-2:])
        if main in CN_DOMAINS:
            return "cn"
        if main in FOREIGN_DOMAINS:
            return "foreign"
        # 三级域名再试一次(如 www.bilibili.com → bilibili.com 已在上面覆盖)
        if len(parts) >= 3:
            sub = ".".join(parts[-3:])
            if sub in CN_DOMAINS:
                return "cn"
            if sub in FOREIGN_DOMAINS:
                return "foreign"
    return "unknown"


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("usage: classify.py <host|url>")
        sys.exit(1)
    print(classify(sys.argv[1]))
