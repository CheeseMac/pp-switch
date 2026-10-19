#!/usr/bin/env bash
# DEP-04 host FORWARD-path firewall rules (docs/43 + binding errata).
#
# Two backends, same semantics:
#   iptables   -> rules in the DOCKER-USER chain (Docker's documented
#                 user hook on the FORWARD path)
#   nftables   -> an independent inet table with a forward hook
#
# Every rule carries the comment tag "ppswitch-dep04:<id>" so that:
#   - counters are machine-readable evidence (iptables-save -c /
#     nft list chain) - a DROP is proven by a timeout AND a counter
#     increment on OUR rule, never by a timeout alone (errata F1);
#   - rollback removes EXACTLY our rules, never Docker's own chains.
#
# Identity model (errata F2): egress privileges are granted to the
# gateway's STATIC address on the egress network (172.29.0.2, pinned in
# deploy/docker-compose.yml) - NOT to the subnet. Everything else from
# the internal or egress subnets is dropped, so an executor mistakenly
# attached to the routed egress network still fails closed.
#
# Usage:
#   rules.sh apply-iptables  --internal <cidr> --egress <cidr> \
#          --gateway-ip <ip> --approved <ip>/<masklen>:<port>
#   rules.sh apply-nftables  (same arguments)
#   rules.sh counters-iptables | counters-nftables   # id=packets lines
#   rules.sh rollback        # removes ONLY tagged rules (idempotent)
#   rules.sh residue         # exits 1 if any tagged rule remains
#
# Production persistence (target host, errata F4) is NOT handled here:
# see deploy/host-firewall/README.md - never delete a validated
# production policy with the CI rollback path.
set -euo pipefail

TAG="ppswitch-dep04"
NFT_TABLE="inet ${TAG//-/_}"

INTERNAL=""
EGRESS=""
GATEWAY_IP=""
APPROVED=""

usage() { sed -n '2,30p' "$0" >&2; exit 2; }

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --internal) INTERNAL="$2"; shift 2 ;;
      --egress) EGRESS="$2"; shift 2 ;;
      --gateway-ip) GATEWAY_IP="$2"; shift 2 ;;
      --approved) APPROVED="$2"; shift 2 ;;
      *) usage ;;
    esac
  done
  for var in INTERNAL EGRESS GATEWAY_IP APPROVED; do
    [ -n "${!var:-}" ] || { echo "missing --$var" >&2; usage; }
  done
  APPROVED_IP="${APPROVED%%/*}"
  APPROVED_PORT="${APPROVED##*:}"
  APPROVED_CIDR="${APPROVED%%:*}"
}

# ---------------------------------------------------------------------------
# iptables backend (DOCKER-USER). Insertion order matters: ACCEPTs first,
# then the subnet drops; every rule is tagged for exact rollback.
# ---------------------------------------------------------------------------
apply_iptables() {
  parse_args "$@"
  local IPT=iptables
  command -v iptables >/dev/null || IPT="/usr/sbin/iptables"

  # fail closed first (idempotent): remove any previous tagged rules
  rollback_iptables_quiet

  $IPT -w -I DOCKER-USER 1 -s "$INTERNAL" -d "$INTERNAL" -m comment \
    --comment "$TAG:intra-internal" -j ACCEPT
  $IPT -w -I DOCKER-USER 2 -s "$INTERNAL" -p udp --dport 53 -m comment \
    --comment "$TAG:dns-udp" -j ACCEPT
  $IPT -w -I DOCKER-USER 3 -s "$INTERNAL" -p tcp --dport 53 -m comment \
    --comment "$TAG:dns-tcp" -j ACCEPT
  # errata F2: egress privilege bound to the gateway's static identity
  $IPT -w -I DOCKER-USER 4 -s "$GATEWAY_IP/32" -d "$APPROVED_CIDR" -p tcp \
    --dport "$APPROVED_PORT" -m comment --comment "$TAG:gw-approved" -j ACCEPT
  # subnet drops: everyone else on either subnet fails closed
  $IPT -w -I DOCKER-USER 5 -s "$INTERNAL" -m comment \
    --comment "$TAG:internal-drop" -j DROP
  $IPT -w -I DOCKER-USER 6 -s "$EGRESS" -m comment \
    --comment "$TAG:egress-subnet-drop" -j DROP
  echo "iptables rules applied (DOCKER-USER, tag $TAG)"
}

rollback_iptables_quiet() {
  # drive off *-save output (comments are ALWAYS printed there, unlike
  # iptables -L) and delete by chain + argv spec; covers DOCKER-USER and
  # the labelled INPUT hardening on iptables and ip6tables
  local saver tool spec chain
  for saver in iptables-save ip6tables-save; do
    command -v "$saver" >/dev/null 2>&1 || continue
    tool="${saver%-save}"
    while spec=$($saver 2>/dev/null | grep -F -- "-m comment --comment \"$TAG" | head -1); [ -n "$spec" ]; do
      chain=$(printf '%s\n' "$spec" | awk '{print $2}')
      # shellcheck disable=SC2086
      if ! $tool -w -D "$chain" $(printf '%s\n' "$spec" | cut -d' ' -f3-); then
        echo "failed to remove: $spec" >&2
        exit 1
      fi
    done
  done
}

# ---------------------------------------------------------------------------
# nftables backend (independent inet table, forward hook). Runs alongside
# Docker's own firewall backend - this validates OUR nftables filter
# effect; it does NOT validate Docker's experimental native nft backend
# (docs/43 errata note, recorded in evidence).
# ---------------------------------------------------------------------------
apply_nftables() {
  parse_args "$@"
  rollback_nftables_quiet
  nft add table "$NFT_TABLE"
  nft add chain "$NFT_TABLE" fwd '{ type filter hook forward priority 0; }'
  nft add rule "$NFT_TABLE" fwd ip saddr "$INTERNAL" ip daddr "$INTERNAL" \
    counter accept comment \""$TAG:intra-internal"\"
  nft add rule "$NFT_TABLE" fwd ip saddr "$INTERNAL" udp dport 53 \
    counter accept comment \""$TAG:dns-udp"\"
  nft add rule "$NFT_TABLE" fwd ip saddr "$INTERNAL" tcp dport 53 \
    counter accept comment \""$TAG:dns-tcp"\"
  nft add rule "$NFT_TABLE" fwd ip saddr "$GATEWAY_IP" ip daddr "$APPROVED_CIDR" \
    tcp dport "$APPROVED_PORT" counter accept comment \""$TAG:gw-approved"\"
  nft add rule "$NFT_TABLE" fwd ip saddr "$INTERNAL" \
    counter drop comment \""$TAG:internal-drop"\"
  nft add rule "$NFT_TABLE" fwd ip saddr "$EGRESS" \
    counter drop comment \""$TAG:egress-subnet-drop"\"
  echo "nftables rules applied (table $NFT_TABLE)"
}

rollback_nftables_quiet() {
  nft list table "$NFT_TABLE" >/dev/null 2>&1 && nft delete table "$NFT_TABLE" || true
}

# ---------------------------------------------------------------------------
# counters / residue
# ---------------------------------------------------------------------------
counters_iptables() {
  iptables-save -c 2>/dev/null | grep -F -- "-m comment --comment \"$TAG" \
    | sed -E 's/^\[([0-9]+):([0-9]+)\].*--comment "([^"]+)".*/\3 packets=\1/' \
    | sort
}

counters_nftables() {
  nft list table "$NFT_TABLE" 2>/dev/null \
    | grep -oE 'counter packets [0-9]+ bytes [0-9]+ comment "[^"]+"' \
    | sed -E 's/counter packets ([0-9]+) bytes [0-9]+ comment "([^"]+)"/\2 packets=\1/' \
    | sort
}

residue() {
  local left=0
  if iptables-save -c 2>/dev/null | grep -qF -- "-m comment --comment \"$TAG"; then
    echo "residue: tagged iptables rules remain" >&2; left=1
  fi
  if command -v ip6tables-save >/dev/null 2>&1       && ip6tables-save -c 2>/dev/null | grep -qF -- "-m comment --comment \"$TAG"; then
    echo "residue: tagged ip6tables rules remain" >&2; left=1
  fi
  if nft list table "$NFT_TABLE" >/dev/null 2>&1; then
    echo "residue: nft table $NFT_TABLE remains" >&2; left=1
  fi
  return "$left"
}

case "${1:-}" in
  apply-iptables) shift; apply_iptables "$@" ;;
  apply-nftables) shift; apply_nftables "$@" ;;
  counters-iptables) counters_iptables ;;
  counters-nftables) counters_nftables ;;
  rollback)
    rollback_iptables_quiet
    rollback_nftables_quiet
    echo "rollback complete (tagged rules only)"
    ;;
  residue) residue ;;
  *) usage ;;
esac
