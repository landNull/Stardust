#!/bin/sh
# apps/dnsmasq/install.sh — local wildcards + fast DNS for devel / --localhost
# Sourced by install-stardust.sh (STEP 25).
#
# devel and --localhost only. test/live use public DNS.
# Wildcards live in /etc/dnsmasq/dnsmasq.d/wildcards.conf
# Host dnsmasq is DNS-only and does not bind virbr*/docker*/tap*.

echo "STEP 25: dnsmasq (*.devel / *.knarr, QEMU-safe bind, cache)"

DNSMASQ_CONFDIR=/etc/dnsmasq/dnsmasq.d
DNSMASQ_WILDCARDS=$DNSMASQ_CONFDIR/wildcards.conf
DNSMASQ_TUNING=$DNSMASQ_CONFDIR/tuning.conf
DNSMASQ_HOSTS=${STARDUST:-/srv/stardust}/state/dnsmasq.hosts
DNSMASQ_INCLUDE=/etc/dnsmasq.d/00-stardust-confdir.conf
DNSMASQ_BIND=/etc/dnsmasq.d/99-stardust-bind.conf
DNSMASQ_LEGACY=/etc/dnsmasq.d/stardust.conf

dns_yes_devel() {
  [ "${LOCALHOST:-0}" -eq 1 ] && return 0
  [ "${ROLE:-}" = devel ] && return 0
  return 1
}

dns_iface_skip() {
  case $1 in
    lo|virbr*|docker*|br-[0-9a-f]*|lxcbr*|lxdbr*|cni*|flannel*|vnet*|tap*|tun*|veth*) return 0 ;;
  esac
  return 1
}

dns_iface_wg() {
  case $1 in wg*|star*) return 0 ;; esac
  return 1
}

dns_pick_target_ip() {
  if [ -n "${DEV_DNS_IP:-}" ]; then printf '%s\n' "$DEV_DNS_IP"; return 0; fi
  if [ "${LOCALHOST:-0}" -eq 1 ]; then printf '%s\n' "127.0.0.1"; return 0; fi
  lan=""; wg=""
  if have ip; then
    while read -r _ iface _ cidr _; do
      [ -n "$iface" ] || continue
      ipaddr=${cidr%/*}
      case $ipaddr in 127.*|169.254.*) continue ;; esac
      dns_iface_skip "$iface" && continue
      if dns_iface_wg "$iface"; then [ -z "$wg" ] && wg=$ipaddr; continue; fi
      [ -z "$lan" ] && lan=$ipaddr
    done <<EOF
$(ip -4 -o addr show scope global 2>/dev/null || true)
EOF
  fi
  if [ -n "$lan" ]; then printf '%s\n' "$lan"; return 0; fi
  if [ -n "$wg" ]; then printf '%s\n' "$wg"; return 0; fi
  first=$(hostname -I 2>/dev/null | awk '{print $1}')
  case $first in ''|127.*|169.254.*) printf '%s\n' "127.0.0.1" ;; *) printf '%s\n' "$first" ;; esac
}

dns_listen_ips() {
  printf '%s\n' "127.0.0.1"
  [ "${LOCALHOST:-0}" -eq 1 ] && return 0
  if have ip; then
    while read -r _ iface _ cidr _; do
      [ -n "$iface" ] || continue
      ipaddr=${cidr%/*}
      case $ipaddr in 127.*|169.254.*) continue ;; esac
      dns_iface_skip "$iface" && continue
      printf '%s\n' "$ipaddr"
    done <<EOF
$(ip -4 -o addr show scope global 2>/dev/null || true)
EOF
  fi
}

dns_upstream_servers() {
  seen=" 127.0.0.1 ::1 "; gw=""
  have ip && gw=$(ip -4 route show default 2>/dev/null | awk '{print $3; exit}')
  [ -z "$gw" ] && have ip && gw=$(ip route show default 2>/dev/null | awk '{print $3; exit}')
  case $gw in ''|127.*|::1) ;; *) printf '%s\n' "$gw"; seen="$seen $gw " ;; esac
  if [ -f /etc/resolv.conf ]; then
    while read -r key val _; do
      [ "$key" = nameserver ] || continue
      case $val in ''|127.*|::1) continue ;; esac
      case $seen in *" $val "*) continue ;; esac
      printf '%s\n' "$val"; seen="$seen $val "
    done < /etc/resolv.conf
  fi
  for pub in 1.1.1.1 9.9.9.9; do
    case $seen in *" $pub "*) ;; *) printf '%s\n' "$pub" ;; esac
  done
}

dns_short_host() { hostname -s 2>/dev/null || hostname 2>/dev/null || echo starhq; }
dns_fqdn_host() { hostname -f 2>/dev/null || hostname 2>/dev/null || echo starhq.knarr; }

dns_ensure_pkg() {
  if have dnsmasq || [ -x /usr/sbin/dnsmasq ]; then echo "package ok: dnsmasq"; return 0; fi
  if [ "$DRYRUN" -eq 1 ]; then echo "+ pkg_install dnsmasq"; return 0; fi
  echo "packages to consider: dnsmasq"
  pkg_install dnsmasq || { echo "$PROG: dnsmasq package missing; install it by hand" >&2; return 1; }
}

dns_write_wildcards() {
  target=$1
  host_short=$(dns_short_host)
  host_fqdn=$(dns_fqdn_host)
  extra_aaaa=""
  if [ "${LOCALHOST:-0}" -eq 1 ] || [ "$target" = "127.0.0.1" ]; then
    extra_aaaa="address=/devel/::1\naddress=/knarr/::1"
  fi
  body="# Stardust wildcards — *.knarr and *.devel
# Written by apps/dnsmasq/install.sh (STEP 25). Re-run is safe.
# Override the target IP with DEV_DNS_IP= on the installer.

local=/devel/
local=/knarr/
address=/devel/${target}
address=/knarr/${target}
${extra_aaaa}
host-record=${host_fqdn},${host_short},${target}
"
  printf '%s\n' "$body" | write_dropin "$DNSMASQ_WILDCARDS"
}

dns_write_tuning() {
  servers=$(dns_upstream_servers)
  listen=$(dns_listen_ips)
  listen_uniq=""
  for a in $listen; do
    case " $listen_uniq " in *" $a "*) ;; *) listen_uniq="$listen_uniq $a" ;; esac
  done
  listen_lines=""
  for a in $listen_uniq; do listen_lines="${listen_lines}listen-address=${a}\n"; done
  [ "${LOCALHOST:-0}" -eq 1 ] && listen_lines="${listen_lines}listen-address=::1\n"
  server_lines=""
  for s in $servers; do server_lines="${server_lines}server=${s}\n"; done
  body="# Stardust dnsmasq — speed + coexist with qemu/libvirt
# DNS only. No dhcp-range. Bind specific addresses so port 53 on virbr*/tap* stays free.

bind-dynamic
${listen_lines}except-interface=virbr0
except-interface=virbr1
except-interface=virbr2
except-interface=docker0
except-interface=docker1
except-interface=lxcbr0
except-interface=lxdbr0
except-interface=cni0
except-interface=flannel.1
except-interface=vnet0
except-interface=vnet1
except-interface=tap0
except-interface=tap1

domain=knarr
expand-hosts
domain-needed
bogus-priv
stop-dns-rebind
rebind-localhost-ok
rebind-domain-ok=/devel/
rebind-domain-ok=/knarr/

no-resolv
no-poll
${server_lines}cache-size=10000
neg-ttl=60
local-ttl=30
dns-forward-max=250
edns-packet-max=1232
dns-loop-detect

addn-hosts=${DNSMASQ_HOSTS}
"
  printf '%s\n' "$body" | write_dropin "$DNSMASQ_TUNING"
}

dns_write_includes() {
  printf '%s\n' "# Stardust — also read ${DNSMASQ_CONFDIR}/*.conf" "conf-dir=${DNSMASQ_CONFDIR}/,*.conf" | write_dropin "$DNSMASQ_INCLUDE"
  printf '%s\n' "# Stardust — win over libvirt bind-interfaces" "bind-dynamic" "except-interface=virbr0" "except-interface=virbr1" "except-interface=docker0" "except-interface=lxcbr0" "except-interface=lxdbr0" | write_dropin "$DNSMASQ_BIND"
  if [ -f "$DNSMASQ_LEGACY" ] || [ "$DRYRUN" -eq 1 ]; then
    printf '%s\n' "# Moved to ${DNSMASQ_WILDCARDS}" "# (included via ${DNSMASQ_INCLUDE}). This file is inert." | write_dropin "$DNSMASQ_LEGACY"
  fi
}

dns_write_hosts_file() {
  if [ "$DRYRUN" -eq 1 ]; then echo "+ write $DNSMASQ_HOSTS"; return 0; fi
  as_root mkdir -p "$(dirname "$DNSMASQ_HOSTS")"
  if [ -f "$DNSMASQ_HOSTS" ]; then echo "exists: $DNSMASQ_HOSTS (unchanged)"; return 0; fi
  tmp=$(mktemp)
  printf '%s\n' "# Stardust extra hosts (dnsmasq addn-hosts)" "# 192.168.1.120  extra.devel extra.knarr" "" > "$tmp"
  as_root install -m 0644 "$tmp" "$DNSMASQ_HOSTS"
  rm -f "$tmp"
  echo "wrote $DNSMASQ_HOSTS"
}

dns_pin_resolv() {
  marker="# stardust-dnsmasq"
  line="nameserver 127.0.0.1"
  if [ "$DRYRUN" -eq 1 ]; then echo "+ pin nameserver 127.0.0.1"; return 0; fi
  head=/etc/resolvconf/resolv.conf.d/head
  if [ -d /etc/resolvconf/resolv.conf.d ]; then
    if [ ! -f "$head" ] || ! grep -q "stardust-dnsmasq" "$head" 2>/dev/null; then
      tmp=$(mktemp)
      [ -f "$head" ] && cat "$head" > "$tmp"
      printf '%s\n%s\n' "$marker" "$line" >> "$tmp"
      as_root install -m 0644 "$tmp" "$head"
      rm -f "$tmp"
      echo "wrote $head"
    else
      echo "exists: $head"
    fi
    have resolvconf && as_root resolvconf -u >/dev/null 2>&1 || true
  fi
  if [ -f /etc/resolv.conf ] && [ ! -L /etc/resolv.conf ]; then
    if grep -q "stardust-dnsmasq" /etc/resolv.conf 2>/dev/null || grep -q '^nameserver 127.0.0.1$' /etc/resolv.conf 2>/dev/null; then
      echo "resolv.conf already lists 127.0.0.1"
    else
      tmp=$(mktemp)
      printf '%s\n%s\n' "$marker" "$line" > "$tmp"
      cat /etc/resolv.conf >> "$tmp"
      as_root install -m 0644 "$tmp" /etc/resolv.conf
      rm -f "$tmp"
      echo "wrote /etc/resolv.conf (127.0.0.1 first)"
    fi
  fi
  if [ -f /etc/dhcp/dhclient.conf ] && ! grep -q 'prepend domain-name-servers 127.0.0.1' /etc/dhcp/dhclient.conf 2>/dev/null; then
    tmp=$(mktemp)
    printf '%s\n%s\n' "$marker" "prepend domain-name-servers 127.0.0.1;" > "$tmp"
    cat /etc/dhcp/dhclient.conf >> "$tmp"
    as_root install -m 0644 "$tmp" /etc/dhcp/dhclient.conf
    rm -f "$tmp"
    echo "wrote /etc/dhcp/dhclient.conf prepend 127.0.0.1"
  fi
}

dns_default_file() {
  def=/etc/default/dnsmasq
  [ -f "$def" ] || return 0
  if [ "$DRYRUN" -eq 1 ]; then echo "+ tune $def"; return 0; fi
  tmp=$(mktemp)
  grep -v 'stardust-dnsmasq' "$def" | grep -v '^DNSMASQ_EXCEPT=' > "$tmp" || true
  if grep -q '^ENABLED=' "$tmp"; then sed -i 's/^ENABLED=.*/ENABLED=1/' "$tmp" 2>/dev/null || true; else printf '%s\n' "ENABLED=1" >> "$tmp"; fi
  if grep -q '^IGNORE_RESOLVCONF=' "$tmp"; then sed -i 's/^IGNORE_RESOLVCONF=.*/IGNORE_RESOLVCONF=yes/' "$tmp" 2>/dev/null || true; else printf '%s\n' "IGNORE_RESOLVCONF=yes" >> "$tmp"; fi
  printf '%s\n' "# stardust-dnsmasq" "DNSMASQ_EXCEPT=\"virbr0 virbr1 docker0 lxcbr0 lxdbr0 vnet0 tap0\"" >> "$tmp"
  as_root install -m 0644 "$tmp" "$def"
  rm -f "$tmp"
  echo "wrote $def"
}

dns_enable_boot() {
  [ "$DRYRUN" -eq 1 ] && { echo "+ enable dnsmasq at boot ($INIT)"; return 0; }
  case $INIT in
    systemd) as_root systemctl enable dnsmasq >/dev/null 2>&1 || true ;;
    openrc) as_root rc-update add dnsmasq default >/dev/null 2>&1 || true ;;
    sysv|unknown) have update-rc.d && as_root update-rc.d dnsmasq defaults >/dev/null 2>&1 || true ;;
  esac
}

dns_test_and_start() {
  if [ "$DRYRUN" -eq 1 ]; then echo "+ dnsmasq --test && svc_start dnsmasq"; return 0; fi
  bin=/usr/sbin/dnsmasq
  have dnsmasq && bin=$(command -v dnsmasq)
  [ -x "$bin" ] || bin=/usr/sbin/dnsmasq
  if [ -x "$bin" ]; then
    if as_root "$bin" --test >/dev/null 2>&1; then echo "dnsmasq --test: ok"
    else echo "note: dnsmasq --test failed; starting anyway" >&2; fi
  fi
  dns_enable_boot
  svc_start dnsmasq
  case $INIT in
    systemd) as_root systemctl reload dnsmasq >/dev/null 2>&1 || as_root systemctl restart dnsmasq >/dev/null 2>&1 || true ;;
    openrc) as_root rc-service dnsmasq reload >/dev/null 2>&1 || as_root rc-service dnsmasq restart >/dev/null 2>&1 || true ;;
    sysv|unknown)
      if [ -x /etc/init.d/dnsmasq ]; then
        as_root /etc/init.d/dnsmasq force-reload >/dev/null 2>&1 || as_root /etc/init.d/dnsmasq restart >/dev/null 2>&1 || true
      fi ;;
  esac
}

dns_selfcheck() {
  if [ "$DRYRUN" -eq 1 ]; then echo "+ getent hosts www.devel starhq.knarr"; return 0; fi
  okc=0
  for name in www.devel devel starhq.knarr knarr; do
    if getent hosts "$name" >/dev/null 2>&1; then
      echo "resolves: $name → $(getent hosts "$name" | awk '{print $1; exit}')"
      okc=$((okc + 1))
    else
      echo "note: $name does not resolve yet (nameserver 127.0.0.1 + /etc/init.d/dnsmasq status)"
    fi
  done
  [ "$okc" -gt 0 ] && echo "dnsmasq: $okc wildcard names visible from this host"
}

if ! dns_yes_devel; then
  echo "VPS ${ROLE:-unknown}: skip dnsmasq (use public DNS / Cloudflare)"
  return 0 2>/dev/null || exit 0
fi

dns_ensure_pkg || true
target=$(dns_pick_target_ip)
echo "wildcard target: *.devel *.knarr → $target"
echo "  (override with DEV_DNS_IP=x.x.x.x)"

if [ "$DRYRUN" -eq 1 ]; then echo "+ mkdir -p $DNSMASQ_CONFDIR /etc/dnsmasq.d"
else as_root mkdir -p "$DNSMASQ_CONFDIR" /etc/dnsmasq.d
fi

dns_write_includes
dns_write_wildcards "$target"
dns_write_tuning "$target"
dns_write_hosts_file
dns_pin_resolv
dns_default_file
dns_test_and_start
dns_selfcheck

echo "dnsmasq: $DNSMASQ_WILDCARDS  (*.devel / *.knarr → $target)"
echo "         ping www.devel and ping starhq.knarr from knarr should hit $target"
echo "         qemu/libvirt keep port 53 on virbr*/tap* (we bind lo + LAN/WG only)"
