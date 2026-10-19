#!/usr/bin/env bash
# DEP-04 host FORWARD-path firewall rules (docs/43 + binding errata).
#
# Two backends, same semantics:
#   iptables   -> rules in the DOCKER-USER chain (Docker's documented
#                 user hook on the FORWARD path) + a labelled INPUT rule
#                 (explicitly supplementary, never FORWARD evidence)
#   nftables   -> an independent inet table with a forward hook
#
# Every rule carries the comment tag "ppswitch-dep04:<id>" so counters
# are machine-readable evidence (a DROP is proven by a timeout AND a
# counter increment on OUR rule, never by a timeout alone - errata F1).
#
# Rollback correctness note (learned in CI): iptables-nft only reliably
# accepts -D with the EXACT argv used at insertion - specs reconstructed
# from iptables-save are normalized (-m tcp appears, ordering changes)
# and can fail with "Bad rule". apply therefore records every insertion
# as a deletion argv line in a state file; rollback replays those
# verbatim, then sweeps *-save output for unrecorded leftovers and only
# treats a persisting leftover as fatal.
#
# Identity model (errata F2): egress privileges are granted to the
# gateway's STATIC address on the egress network (172.29.0.2, pinned in
# deploy/docker-compose.yml) - NOT to the subnet. Everything else from
# the internal or egress subnets is dropped, so an executor mistakenly
# attached to the routed egress network still fails closed.
#
# Production persistence (target host, errata F4) is NOT handled here:
# see deploy/host-firewall/README.md - never delete a validated
# production policy with the CI rollback path.
set -euo pipefail

TAG="ppswitch-dep04"
NFT_TABLE="inet ${TAG//-/_}"
STATE_FILE="${PPSWITCH_DEP04_STATE:-${TMPDIR:-/tmp}/ppswitch-dep04.state}"
SEP=$'\x1f'

INTERNAL=""
EGRESS=""
GATEWAY_IP=""
APPROVED=""
INPUT_PORT_VALUE=""

usage() { grep '^#' "$0" | sed -n '2,40p' >&2; exit 2; }

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --internal) INTERNAL="$2"; shift 2 ;;
      --egress) EGRESS="$2"; shift 2 ;;
      --gateway-ip) GATEWAY_IP="$2"; shift 2 ;;
      --approved) APPROVED="$2"; shift 2 ;;
      --port) INPUT_PORT_VALUE="$2"; shift 2 ;;
      *) usage ;;
    esac
  done
  for var in INTERNAL EGRESS GATEWAY_IP APPROVED; do
    [ -n "${!var:-}" ] || { echo "missing --$var" >&2; usage; }
  done
  APPROVED_PORT="${APPROVED##*:}"
  APPROVED_CIDR="${APPROVED%%:*}"
}

ipt() { command -v iptables >/dev/null 2>&1 && iptables -w "$@" || /usr/sbin/iptables -w "$@"; }

# insert_rule <chain> <position> <args...> via iptables; records the
# exact deletion argv in the state file
insert_rule() {
  local chain="$1" pos="$2"; shift 2
  ipt -I "$chain" "$pos" "$@"
  printf 'iptables%s-D%s%s' "$SEP" "$SEP" "$chain" >>"$STATE_FILE"
  local arg
  for arg in "$@"; do printf '%s%s' "$SEP" "$arg" >>"$STATE_FILE"; done
  printf '\n' >>"$STATE_FILE"
}

add_input_drop() {
  parse_args "$@"
  [ -n "$INPUT_PORT_VALUE" ] || { echo "missing --port" >&2; usage; }
  insert_rule INPUT 1 \
    -s "$INTERNAL" -p tcp --dport "$INPUT_PORT_VALUE" \
    -m comment --comment "$TAG:input-drop" -j DROP
  echo "labelled INPUT drop installed (supplementary host hardening)"
}

apply_iptables() {
  parse_args "$@"
  rollback_quiet
  : >"$STATE_FILE"

  # physical order after insertion: intra, dns-udp, dns-tcp, gw-approved,
  # internal-drop, egress-subnet-drop - the gateway identity ACCEPT MUST
  # precede the subnet drops or the gateway drops itself (CI iteration 8)
  insert_rule DOCKER-USER 1 -s "$INTERNAL" -d "$INTERNAL" -m comment \
    --comment "$TAG:intra-internal" -j ACCEPT
  insert_rule DOCKER-USER 2 -s "$INTERNAL" -p udp --dport 53 -m comment \
    --comment "$TAG:dns-udp" -j ACCEPT
  insert_rule DOCKER-USER 3 -s "$INTERNAL" -p tcp --dport 53 -m comment \
    --comment "$TAG:dns-tcp" -j ACCEPT
  insert_rule DOCKER-USER 4 -s "$GATEWAY_IP/32" -d "$APPROVED_CIDR" -p tcp \
    --dport "$APPROVED_PORT" -m comment --comment "$TAG:gw-approved" -j ACCEPT
  insert_rule DOCKER-USER 5 -s "$INTERNAL" -m comment \
    --comment "$TAG:internal-drop" -j DROP
  insert_rule DOCKER-USER 6 -s "$EGRESS" -m comment \
    --comment "$TAG:egress-subnet-drop" -j DROP
  echo "iptables rules applied (DOCKER-USER, tag $TAG)"
}

apply_nftables() {
  parse_args "$@"
  rollback_quiet
  : >"$STATE_FILE"
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

rollback_quiet() {
  # 1) replay recorded deletion argv verbatim (iptables-nft only accepts
  #    -D with the exact insertion argv; per-line failures are tolerated
  #    here - the sweep below decides whether anything actually matters)
  if [ -f "$STATE_FILE" ]; then
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      IFS="$SEP" read -r -a argv <<<"$line"
      "${argv[@]}" 2>/dev/null || true
    done <"$STATE_FILE"
    rm -f "$STATE_FILE"
  fi
  # 2) sweep: anything still tagged that the state file did not cover is
  #    fatal (never silently left behind)
  local saver spec
  for saver in iptables-save ip6tables-save; do
    command -v "$saver" >/dev/null 2>&1 || continue
    spec=$($saver 2>/dev/null | grep -F -- "-m comment --comment \"$TAG" | head -1) || spec=""
    if [ -n "$spec" ]; then
      echo "rollback incomplete, tagged rule persists: $spec" >&2
      exit 1
    fi
  done
  # 3) nft table
  if nft list table "$NFT_TABLE" >/dev/null 2>&1; then
    nft delete table "$NFT_TABLE"
  fi
  return 0
}

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
  if command -v ip6tables-save >/dev/null 2>&1 \
      && ip6tables-save -c 2>/dev/null | grep -qF -- "-m comment --comment \"$TAG"; then
    echo "residue: tagged ip6tables rules remain" >&2; left=1
  fi
  if nft list table "$NFT_TABLE" >/dev/null 2>&1; then
    echo "residue: nft table $NFT_TABLE remains" >&2; left=1
  fi
  return "$left"
}

status() {
  echo "--- iptables (tagged, with counters) ---"
  counters_iptables || true
  echo "--- nftables $NFT_TABLE ---"
  nft list table "$NFT_TABLE" 2>/dev/null || echo "(absent)"
}

case "${1:-}" in
  apply-iptables) shift; apply_iptables "$@" ;;
  apply-nftables) shift; apply_nftables "$@" ;;
  add-input-drop) shift; add_input_drop "$@" ;;
  counters-iptables) counters_iptables ;;
  counters-nftables) counters_nftables ;;
  status) status ;;
  rollback)
    rollback_quiet
    echo "rollback complete (tagged rules only)"
    ;;
  residue) residue ;;
  *) usage ;;
esac
