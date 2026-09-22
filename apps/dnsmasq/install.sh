#!/bin/sh
# apps/dnsmasq/install.sh — STEP 25. devel / --localhost only.
# Conf files are written with one printf per line. Never embed \\n in a directive.
# DHCP is off. Starlink and qemu keep their own lease servers.

echo "STEP 25: dnsmasq (*.devel / *.knarr, QEMU-safe bind, cache, no DHCP)"

DNSMASQ_CONFDIR=/etc/dnsmasq/dnsmasq.d
DNSMASQ_WILDCARDS=$DNSMASQ_CONFDIR/wildcards.conf
DNSMASQ_TUNING=$DNSMASQ_CONFDIR/tuning.conf
DNSMASQ_NODHCP=$DNSMASQ_CONFDIR/nodhcp.conf
DNSMASQ_HOSTS=${STARDUST:-/srv/stardust}/state/dnsmasq.hosts
DNSMASQ_INCLUDE=/etc/dnsmasq.d/00-stardust-confdir.conf
DNSMASQ_BIND=/etc/dnsmasq.d/99-stardust-bind.conf
DNSMASQ_LEGACY=/etc/dnsmasq.d/stardust.conf
DNSMASQ_NM=/etc/NetworkManager/conf.d/90-stardust-dns.conf

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
  [ -n "$lan" ] && { printf '%s\n' "$lan"; return 0; }
  [ -n "$wg" ] && { printf '%s\n' "$wg"; return 0; }
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
  [ "$DRYRUN" -eq 1 ] && { echo "+ pkg_install dnsmasq"; return 0; }
  echo "packages to consider: dnsmasq"
  pkg_install dnsmasq || { echo "$PROG: dnsmasq package missing" >&2; return 1; }
}

dns_write_wildcards() {
  target=$1
  {
    printf '%s\n' "# Stardust wildcards *.knarr *.devel"
    printf '%s\n' "local=/devel/"
    printf '%s\n' "local=/knarr/"
    printf 'address=/devel/%s\n' "$target"
    printf 'address=/knarr/%s\n' "$target"
    if [ "${LOCALHOST:-0}" -eq 1 ] || [ "$target" = "127.0.0.1" ]; then
      printf '%s\n' "address=/devel/::1"
      printf '%s\n' "address=/knarr/::1"
    fi
    printf 'host-record=%s,%s,%s\n' "$(dns_fqdn_host)" "$(dns_short_host)" "$target"
  } | write_dropin "$DNSMASQ_WILDCARDS"
}

dns_write_nodhcp() {
  {
    printf '%s\n' "# Stardust — DNS only. Do not serve DHCP."
    printf '%s\n' "port=53"
    printf '%s\n' "no-dhcp-interface=*"
    if have ip; then
      ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | cut -d@ -f1 | while read -r ifc; do
        [ -n "$ifc" ] || continue
        printf 'no-dhcp-interface=%s\n' "$ifc"
      done
    fi
  } | write_dropin "$DNSMASQ_NODHCP"
  if [ "$DRYRUN" -eq 1 ]; then return 0; fi
  for f in /etc/dnsmasq.conf /etc/dnsmasq.d/*.conf; do
    [ -f "$f" ] || continue
    grep -q '^[[:space:]]*dhcp-range=' "$f" 2>/dev/null || continue
    tmp=$(mktemp)
    sed 's/^[[:space:]]*dhcp-range=/# stardust-nodhcp &/' "$f" > "$tmp"
    as_root install -m 0644 "$tmp" "$f"
    rm -f "$tmp"
    echo "commented dhcp-range in $f"
  done
}

dns_write_tuning() {
  servers=$(dns_upstream_servers)
  listen=$(dns_listen_ips)
  listen_uniq=""
  for a in $listen; do
    case " $listen_uniq " in *" $a "*) ;; *) listen_uniq="$listen_uniq $a" ;; esac
  done
  {
    printf '%s\n' "# Stardust dnsmasq tuning"
    printf '%s\n' "bind-dynamic"
    printf '%s\n' "port=53"
    for a in $listen_uniq; do
      [ -n "$a" ] || continue
      printf 'listen-address=%s\n' "$a"
    done
    [ "${LOCALHOST:-0}" -eq 1 ] && printf '%s\n' "listen-address=::1"
    printf '%s\n' "except-interface=virbr0"
    printf '%s\n' "except-interface=virbr1"
    printf '%s\n' "except-interface=docker0"
    printf '%s\n' "except-interface=lxcbr0"
    printf '%s\n' "except-interface=vnet0"
    printf '%s\n' "except-interface=tap0"
    printf '%s\n' "domain=knarr"
    printf '%s\n' "expand-hosts"
    printf '%s\n' "domain-needed"
    printf '%s\n' "bogus-priv"
    printf '%s\n' "stop-dns-rebind"
    printf '%s\n' "rebind-localhost-ok"
    printf '%s\n' "rebind-domain-ok=/devel/"
    printf '%s\n' "rebind-domain-ok=/knarr/"
    printf '%s\n' "no-resolv"
    printf '%s\n' "no-poll"
    for s in $servers; do
      [ -n "$s" ] || continue
      printf 'server=%s\n' "$s"
    done
    printf '%s\n' "cache-size=10000"
    printf '%s\n' "neg-ttl=60"
    printf '%s\n' "local-ttl=30"
    printf '%s\n' "dns-forward-max=250"
    printf 'addn-hosts=%s\n' "$DNSMASQ_HOSTS"
  } | write_dropin "$DNSMASQ_TUNING"
}

dns_write_includes() {
  printf '%s\n' "# Stardust include" "conf-dir=${DNSMASQ_CONFDIR}/,*.conf" | write_dropin "$DNSMASQ_INCLUDE"
  printf '%s\n' "# Stardust bind" "bind-dynamic" "except-interface=virbr0" "except-interface=docker0" | write_dropin "$DNSMASQ_BIND"
  if [ -f "$DNSMASQ_LEGACY" ] || [ "$DRYRUN" -eq 1 ]; then
    printf '%s\n' "# Moved to ${DNSMASQ_WILDCARDS}" | write_dropin "$DNSMASQ_LEGACY"
  fi
}

dns_write_hosts_file() {
  [ "$DRYRUN" -eq 1 ] && { echo "+ write $DNSMASQ_HOSTS"; return 0; }
  as_root mkdir -p "$(dirname "$DNSMASQ_HOSTS")"
  [ -f "$DNSMASQ_HOSTS" ] && { echo "exists: $DNSMASQ_HOSTS"; return 0; }
  tmp=$(mktemp)
  printf '%s\n' "# Stardust extra hosts" "" > "$tmp"
  as_root install -m 0644 "$tmp" "$DNSMASQ_HOSTS"
  rm -f "$tmp"
}

dns_pin_networkmanager() {
  [ -d /etc/NetworkManager ] || have nmcli || [ -x /etc/init.d/network-manager ] || return 0
  [ "$DRYRUN" -eq 1 ] && { echo "+ write $DNSMASQ_NM"; return 0; }
  as_root mkdir -p "$(dirname "$DNSMASQ_NM")"
  printf '%s\n' "[main]" "dns=none" "rc-manager=unmanaged" | write_dropin "$DNSMASQ_NM"
  have nmcli && as_root nmcli general reload >/dev/null 2>&1 || true
}

dns_pin_resolv() {
  marker="# stardust-dnsmasq"
  line="nameserver 127.0.0.1"
  dns_pin_networkmanager
  [ "$DRYRUN" -eq 1 ] && { echo "+ pin 127.0.0.1"; return 0; }
  if [ -f /etc/resolv.conf ] && [ ! -L /etc/resolv.conf ]; then
    if ! grep -q "stardust-dnsmasq" /etc/resolv.conf 2>/dev/null && ! grep -q '^nameserver 127.0.0.1$' /etc/resolv.conf; then
      tmp=$(mktemp)
      printf '%s\n%s\n' "$marker" "$line" > "$tmp"
      cat /etc/resolv.conf >> "$tmp"
      as_root install -m 0644 "$tmp" /etc/resolv.conf
      rm -f "$tmp"
    fi
  fi
}

dns_test_and_start() {
  [ "$DRYRUN" -eq 1 ] && { echo "+ dnsmasq --test && svc_start dnsmasq"; return 0; }
  bin=/usr/sbin/dnsmasq
  have dnsmasq && bin=$(command -v dnsmasq)
  [ -x "$bin" ] && as_root "$bin" --test >/dev/null 2>&1 && echo "dnsmasq --test: ok"
  have update-rc.d && as_root update-rc.d dnsmasq defaults >/dev/null 2>&1 || true
  svc_start dnsmasq
  [ -x /etc/init.d/dnsmasq ] && as_root /etc/init.d/dnsmasq force-reload >/dev/null 2>&1 || true
}

if ! dns_yes_devel; then
  echo "VPS ${ROLE:-unknown}: skip dnsmasq (use public DNS)"
  return 0 2>/dev/null || exit 0
fi

dns_ensure_pkg || true
target=$(dns_pick_target_ip)
echo "wildcard target: *.devel *.knarr → $target"
[ "$DRYRUN" -eq 1 ] || as_root mkdir -p "$DNSMASQ_CONFDIR" /etc/dnsmasq.d
dns_write_includes
dns_write_wildcards "$target"
dns_write_tuning "$target"
dns_write_nodhcp
dns_write_hosts_file
dns_pin_resolv
dns_test_and_start
echo "dnsmasq: $DNSMASQ_WILDCARDS → $target (DHCP off)"
