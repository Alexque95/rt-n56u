#!/bin/sh
# 校园网自动登录（成都东软 WebCC）—— 固件内置版
# 用法：
#   campus.sh        单次检查（掉线则自动登录）
#   campus.sh loop   常驻循环（每 300 秒检查一次）
#   campus.sh relog  强制下线重连（供 iPhone 快捷指令 SSH 调用）
PORTAL="http://2.2.2.2/Auth.ashx"
CT='Content-Type: application/json'
LOG=/tmp/campus.log
FAILTS=/tmp/campus_fail.ts
PIDF=/tmp/campus_loop.pid
LOGIN='{"DoWhat":"Login","username":"24016020333","password":"64e1b98ca86d852c"}'
OPEN='{"DoWhat":"OpenNet","Package":"\u5b66\u751f-\u79fb\u52a8-200M"}'

trap '' HUP
POST()  { curl -s -m 8 -X POST -H "$CT" -d "$1" "$PORTAL"; }
log()   { echo "$(date '+%F %T') $1" >> "$LOG"; }
norm()  { tr -d ':.-' | tr 'A-Z' 'a-z'; }
field() { echo "$1" | grep -o "\"$2\":\"[^\"]*\"" | head -1 | cut -d'"' -f4; }
wanip() { ip addr show $(nvram get wan0_ifname 2>/dev/null) 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | head -1; }
mymac() { cat /sys/class/net/$(nvram get wan0_ifname 2>/dev/null)/address 2>/dev/null | norm; }

trim_log() {
    [ -f "$LOG" ] && [ "$(wc -l < "$LOG" 2>/dev/null)" -gt 300 ] && \
        tail -150 "$LOG" > /tmp/c.tmp && mv /tmp/c.tmp "$LOG"
}

do_login() {
    NOW=$(date +%s)
    FAIL=$(cat "$FAILTS" 2>/dev/null); [ -z "$FAIL" ] && FAIL=0
    [ $((NOW - FAIL)) -lt 300 ] && { [ "$1" = "force" ] || return; }

    L=$(POST "$LOGIN")
    case "$L" in
        *"身份验证成功"*) ;;
        *"上限"*|*"同时登录"*) log "occupied, yield"; return ;;
        *) echo "$NOW" > "$FAILTS"; log "login fail"; return ;;
    esac

    sleep 1
    R=$(POST "$OPEN")
    case "$R" in
        *"上线成功"*) rm -f "$FAILTS"; log "online";;
        *) echo "$NOW" > "$FAILTS"; log "open fail";;
    esac
}

do_relog() {
    IP=$(wanip)
    [ -z "$IP" ] && { log "relog: no wan ip"; return; }
    POST "{\"DoWhat\":\"CloseNet\",\"IP\":\"$IP\"}" >/dev/null
    sleep 2
    rm -f "$FAILTS"
    NOW=$(date +%s)
    L=$(POST "$LOGIN")
    case "$L" in
        *"身份验证成功"*) ;;
        *) echo "$NOW" > "$FAILTS"; log "relog: login fail"; return ;;
    esac
    sleep 1
    R=$(POST "$OPEN")
    case "$R" in
        *"上线成功"*) log "relog: online";;
        *) echo "$NOW" > "$FAILTS"; log "relog: open fail";;
    esac
}

check() {
    trim_log
    INFO=$(POST '{"DoWhat":"GetInfo"}')
    [ -z "$INFO" ] && return
    F=$(echo "$INFO" | tr -d '\n\r ')

    case "$F" in
        *needLogin*) log "needLogin"; do_login; return;;
    esac

    M=$(mymac)
    [ -z "$M" ] && return
    ONLINE=$(field "$F" MAC | norm)
    [ -z "$ONLINE" ] && { do_login; return; }
    [ "$ONLINE" != "$M" ] && return
    log "online"
}

case "$1" in
    loop)  echo $$ > "$PIDF"; while true; do check; sleep 300; done;;
    relog) do_relog;;
    *)     check;;
esac
