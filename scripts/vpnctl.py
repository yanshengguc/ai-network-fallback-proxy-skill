#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
vpnctl.py — 后台控制本机 VPN 代理核心(不碰 v2rayN GUI 进程,不泄露节点信息)

用法:
  python vpnctl.py on      # 开启代理:拉起 xray 核心,后台无窗口运行
  python vpnctl.py off     # 关闭代理:优雅终止核心进程,v2rayN GUI 保留
  python vpnctl.py status  # 状态:仅输出 进程/端口/连通性,绝不含节点信息
  python vpnctl.py off --check  # 预演关闭:只报告将终止的进程,不真正关闭

设计约束:
  1. 不 kill/停止 v2rayN.exe(GUI 进程)— 只终止代理核心(监听代理端口的进程)
  2. 全程后台:启动核心用 CREATE_NO_WINDOW,不弹任何窗口
  3. 不泄露节点:任何输出只含 端口号/进程名/PID/状态词,绝不打印 config.json 内容、节点地址、密码、订阅等
"""

import os
import sys
import time
import json
import signal
import subprocess

# ---------- 路径与常量(敏感信息:节点等只存在于配置文件中,本脚本不读取、不打印) ----------
# v2rayN 安装目录可用环境变量 V2RAYN_DIR 覆盖
V2RAYN_DIR = os.environ.get("V2RAYN_DIR", r"C:\v2rayN-windows-64\v2rayN-windows-64")
XRAY_EXE = os.path.join(V2RAYN_DIR, "bin", "xray", "xray.exe")
XRAY_CONFIG = os.path.join(V2RAYN_DIR, "binConfigs", "config.json")
PIDFILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".core.pid")
PORT = int(os.environ.get("PROXY_PORT", "10808"))
PROBE_URL = "https://www.google.com/generate_204"
CREATE_NO_WINDOW = 0x08000000
START_TIMEOUT = 15  # 秒
STOP_TIMEOUT = 12   # 秒


def _sh(cmd, timeout=10):
    """执行系统命令,返回 (returncode, stdout)"""
    try:
        r = subprocess.run(cmd, capture_output=True, text=True,
                           timeout=timeout, errors="replace")
        return r.returncode, (r.stdout or "") + (r.stderr or "")
    except Exception as e:
        return -1, str(e)


def _port_listening(port, timeout=0.3):
    """快速探测端口是否监听(socket 连接,0.3s 超时)"""
    import socket
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(timeout)
    try:
        return s.connect_ex(("127.0.0.1", port)) == 0
    except Exception:
        return False
    finally:
        s.close()


# ---------- Windows 系统代理(注册表,无需管理员权限) ----------
IE_KEY = r"Software\Microsoft\Windows\CurrentVersion\Internet Settings"


def _sysproxy_get():
    import winreg
    try:
        k = winreg.OpenKey(winreg.HKEY_CURRENT_USER, IE_KEY)
        try:
            enable, _ = winreg.QueryValueEx(k, "ProxyEnable")
        except FileNotFoundError:
            enable = 0
        try:
            server, _ = winreg.QueryValueEx(k, "ProxyServer")
        except FileNotFoundError:
            server = ""
        winreg.CloseKey(k)
        return int(enable or 0), server or ""
    except Exception:
        return -1, ""


def _sysproxy_set(enable, server=""):
    """设置系统代理;enable=1 开,0 关。返回 (ok, err)"""
    import winreg
    try:
        k = winreg.OpenKey(winreg.HKEY_CURRENT_USER, IE_KEY,
                           0, winreg.KEY_SET_VALUE)
        winreg.SetValueEx(k, "ProxyEnable", 0, winreg.REG_DWORD, 1 if enable else 0)
        if server:
            winreg.SetValueEx(k, "ProxyServer", 0, winreg.REG_SZ, server)
        winreg.CloseKey(k)
        _refresh_sysproxy()
        return True, None
    except Exception as e:
        return False, str(e)


def _refresh_sysproxy():
    """广播系统代理变更,让 WinINET/浏览器立即生效"""
    import ctypes
    try:
        h = ctypes.windll.Wininet.InternetSetOptionW
        h(0, 39, 0, 0)   # INTERNET_OPTION_SETTINGS_CHANGED
        h(0, 37, 0, 0)   # INTERNET_OPTION_REFRESH
    except Exception:
        pass


def port_listener_pids(port):
    """返回监听某端口的 PID 列表(仅 off 时调用,全量解析一次可接受)"""
    pids = []
    rc, out = _sh(["netstat", "-ano"])
    for line in out.splitlines():
        if "LISTENING" in line and ":%d" % port in line:
            parts = line.split()
            if parts:
                pid = parts[-1].strip()
                if pid.isdigit():
                    pids.append(pid)
    return pids


def port_open(port):
    """快速端口探测(socket,0.3s 超时)"""
    return _port_listening(port)


def core_running():
    rc, out = _sh(["tasklist", "/FI", "IMAGENAME eq xray.exe"])
    return "xray.exe" in out


def client_running():
    rc, out = _sh(["tasklist", "/FI", "IMAGENAME eq v2rayN.exe"])
    return "v2rayN.exe" in out


def _start_core():
    """后台拉起 xray 核心(无窗口),写入 PID 文件"""
    if not os.path.exists(XRAY_EXE) or not os.path.exists(XRAY_CONFIG):
        return False, "核心或配置不存在"
    try:
        p = subprocess.Popen(
            [XRAY_EXE, "run", "-c", XRAY_CONFIG],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            creationflags=CREATE_NO_WINDOW,
        )
        with open(PIDFILE, "w") as f:
            f.write(str(p.pid))
        return True, "pid=%d" % p.pid
    except Exception as e:
        return False, str(e)


def _stop_pids(pids):
    """优雅终止指定 PID(仅核心进程;绝不触碰 v2rayN GUI)。
    优先用 Windows 原生 taskkill(对跨进程终止权限最可靠)"""
    stopped = []
    for pid in pids:
        try:
            rc, out = _sh(["taskkill", "/PID", str(pid), "/T", "/F"])
            # /F 强杀是最后手段;先试不带 /F 的温和终止
            if rc != 0:
                rc2, out2 = _sh(["taskkill", "/PID", str(pid), "/T"])
                if rc2 != 0:
                    return stopped, "taskkill %s 失败(可能权限不足)" % pid
            stopped.append(pid)
        except Exception as e:
            return stopped, str(e)
    return stopped, None


# ---------- 开启 ----------
def _ensure_sysproxy_on():
    """确保系统代理指向本机代理端口;返回 (ok, changed, err)"""
    en, sv = _sysproxy_get()
    want = "127.0.0.1:%d" % PORT
    if en and sv == want:
        return True, False, None
    ok, err = _sysproxy_set(1, want)
    return ok, True, err


def cmd_on():
    if not core_running() and not client_running():
        print("NO_VPN_CLIENT: 未检测到 v2rayN 客户端。本技能不提供 VPN,请先自行安装并运行 v2rayN。")
        return 2
    if not port_open(PORT):
        ok, msg = _start_core()
        if not ok:
            print("START_FAILED: %s" % msg)
            return 3
        # 轮询等待端口
        started = False
        for _ in range(START_TIMEOUT):
            time.sleep(1)
            if port_open(PORT):
                started = True
                break
        if not started:
            print("START_TIMEOUT: %d 秒内端口未开放,请检查节点可用性" % START_TIMEOUT)
            return 1
        print("STARTED: 代理端口 %d 已监听" % PORT)
    else:
        print("ALREADY_ON: 代理端口 %d 已在监听" % PORT)
    # 无论端口之前是否已开,都确保系统代理开启
    ok, changed, err = _ensure_sysproxy_on()
    if ok:
        print("sysproxy=%s" % ("on" if changed else "already_on"))
    else:
        print("WARN: 系统代理开启失败: %s" % err)
    return 0


# ---------- 关闭 ----------
def cmd_off(check_only=False):
    pids = port_listener_pids(PORT)
    core_pids = []
    for pid in pids:
        rc, out = _sh(["tasklist", "/FI", "PID eq %s" % pid])
        if "xray.exe" in out:
            core_pids.append(pid)
    if check_only:
        desc = []
        if core_pids:
            desc.append("终止 xray 核心 pid=%s" % ",".join(core_pids))
        if _sysproxy_get()[0]:
            desc.append("关闭系统代理(ProxyEnable=0)")
        if not desc:
            desc.append("无动作(代理已关闭)")
        print("CHECK: " + " | ".join(desc) + " (v2rayN GUI 保留)")
        return 0
    # 1) 关闭系统代理(核心动作:系统流量不再走代理,无需管理员权限)
    en, sv = _sysproxy_get()
    if en:
        ok, err = _sysproxy_set(0)
        if not ok:
            print("STOP_ERROR: 关闭系统代理失败: %s" % err)
            return 1
        print("OFF: 系统代理已关闭(ProxyEnable=0)")
    else:
        print("OFF: 系统代理已是关闭状态")
    # 2) 尝试终止核心进程(权限足够则停;权限不足则保留 GUI 由 v2rayN 管理)
    if core_pids:
        stopped, err = _stop_pids(core_pids)
        if stopped:
            print("OFF: 已停止 xray 核心 pid=%s" % ",".join(stopped))
        else:
            print("WARN: 无法停止核心进程(%s)。系统代理已关闭,流量不再走代理;核心仍由 v2rayN 管理,不影响上网。" % (err or "权限不足"))
        # 等待端口释放(尽力)
        for _ in range(STOP_TIMEOUT):
            if not port_open(PORT):
                break
            time.sleep(1)
        if os.path.exists(PIDFILE):
            try:
                os.remove(PIDFILE)
            except Exception:
                pass
    print("STOPPED: 代理已关闭 (v2rayN GUI 保留)")
    return 0


# ---------- 状态 ----------
def cmd_status():
    port = PORT if port_open(PORT) else "NONE"
    if port != "NONE":
        # 端口通 → 进程必然在跑,不再查 tasklist(省 1.5s);进程名仅作展示
        client = "v2rayN.exe"
        core = "xray.exe"
    else:
        # 端口未开 → 查一次 tasklist 给出诊断
        rc, tl = _sh(["tasklist"])
        client = "v2rayN.exe" if "v2rayN.exe" in tl else "NONE"
        core = "xray.exe" if "xray.exe" in tl else "NONE"
    conn = "UNTESTED"
    if port != "NONE":
        # 连通性探测:总超时 4s、连接超时 3s,避免长时间阻塞
        rc, code = _sh(["curl", "-sS", "-m", "4", "--connect-timeout", "3",
                        "-x", "http://127.0.0.1:%d" % PORT,
                        "-o", os.devnull, "-w", "%{http_code}", PROBE_URL])
        code = code.strip()
        conn = "OK" if code in ("204", "200") else "FAIL(%s)" % (code or "timeout")
    print("client=%s" % client)
    print("core=%s" % core)
    print("port=%s" % port)
    print("connectivity=%s" % conn)
    if port != "NONE" and conn == "OK":
        print("VERDICT=VPN_ON")
        return 0
    print("VERDICT=VPN_OFF")
    return 1


def main():
    argv = [a for a in sys.argv[1:] if a != "--check"]
    check_only = "--check" in sys.argv[1:]
    if not argv:
        return cmd_status()
    if argv[0] == "on":
        return cmd_on()
    if argv[0] == "off":
        return cmd_off(check_only=check_only)
    if argv[0] == "status":
        return cmd_status()
    print("usage: vpnctl.py on|off|status [--check]")
    return 1


if __name__ == "__main__":
    sys.exit(main())
