#!/usr/bin/env bash
# DEP-04 host-firewall verification rig (docs/43 + binding errata F1-F4).
#
# Proves the HOST FORWARD path on a real Linux host (CI: an ubuntu-latest
# VM with its own kernel; target hosts: see README.md rollout mode):
#   - a routed netns+veth test target so container->target traffic truly
#     crosses FORWARD (never a host-local INPUT service) and every DROP
#     is proven by timeout + OUR rule's counter increment (F1);
#   - egress privilege bound to the gateway's static identity, with the
#     executor DELIBERATELY misattached to the routed network still
#     dropped (F2);
#   - DNAT (published port) and SNAT (outbound) evidenced via conntrack
#     and counters, kept separate from the labelled host INPUT probe (F3);
#   - CI mode rolls back to zero residue; address drift is FORCED and
#     proven, never assumed (F4). Production persistence is documented
#     separately and never touched by this script.
#
# Usage (root/sudo):  verify-host-firewall.sh [--skip-stack]
# Evidence:          deploy/host-firewall/evidence-<utc>.log (also stdout)
set -euo pipefail

cd "$(dirname "$0")/../.."
ROOT="$PWD"
HF="$ROOT/deploy/host-firewall"
EVIDENCE="$HF/evidence-$(date -u +%Y%m%dT%H%M%SZ).log"
RULES="$HF/rules.sh"
SKIP_STACK="${1:-}"

INTERNAL_NET="pp-switch_internal"
EGRESS_NET="pp-switch_egress"
INTERNAL_CIDR="172.28.0.0/24"
EGRESS_CIDR="172.29.0.0/24"
GATEWAY_IP="172.29.0.2"
APPROVED_IP="192.0.2.2"        # routed netns target (RFC5737 TEST-NET-1)
APPROVED_PORT="8443"
DENY_IP="198.51.100.2"         # routed netns target, never approved
DENY_PORT="8443"
DNAT_HOST_PORT="18080"
INPUT_PORT="18081"

PASS=0; FAIL=0; PENDING=()
SERVER_PIDS=()

log() { printf '%s\n' "$*" | tee -a "$EVIDENCE"; }
section() { log ""; log "=================================================================="; log "== $*"; log "=================================================================="; }

verdict() { # verdict <ok|bad> <label> <detail>
  if [ "$1" = ok ]; then PASS=$((PASS+1)); log "PASS  $2 :: $3"
  else FAIL=$((FAIL+1)); log "FAIL  $2 :: $3"; fi
}

pending() { PENDING+=("$1"); log "PENDING  $1 :: recorded as待补, NOT counted as pass (errata V5)"; }

cleanup() {
  local rc=$?
  set +e
  bash "$RULES" rollback >/dev/null 2>&1
  for pid in "${SERVER_PIDS[@]:-}"; do kill "$pid" >/dev/null 2>&1; done
  ip netns del dep04-approved >/dev/null 2>&1
  ip netns del dep04-deny >/dev/null 2>&1
  ip link del veth-dep04a >/dev/null 2>&1
  ip link del veth-dep04d >/dev/null 2>&1
  ip netns del dep04-v6 >/dev/null 2>&1
  ip link del veth-dep04v6 >/dev/null 2>&1
  docker rm -f dep04-dnat dep04-occupier >/dev/null 2>&1
  docker network rm dep04v6 >/dev/null 2>&1
  docker compose down --remove-orphans >/dev/null 2>&1
  [ "$rc" -eq 0 ] && bash "$RULES" residue >/dev/null 2>&1 || true
  exit "$rc"
}
trap cleanup EXIT INT TERM

# container probe: probe <container> <host> <port> <open|blocked>
probe() {
  local container="$1" host="$2" port="$3" expect="$4" got
  got=$(docker exec "$container" python -c '
import socket, sys
s = socket.socket(); s.settimeout(4)
try:
    s.connect((sys.argv[1], int(sys.argv[2]))); print("open")
except Exception:
    print("blocked")
' "$host" "$port" 2>/dev/null) || got="blocked"
  [ "$got" = "$expect" ]
}

# host/netns probe (python3 on the host)
probe_netns() {
  local netns="$1" host="$2" port="$3" expect="$4" got
  got=$(ip netns exec "$netns" python3 -c '
import socket, sys
s = socket.socket(); s.settimeout(4)
try:
    s.connect((sys.argv[1], int(sys.argv[2]))); print("open")
except Exception:
    print("blocked")
' "$host" "$port" 2>/dev/null) || got="blocked"
  [ "$got" = "$expect" ]
}

# rule counter (iptables backend): counter_ipt <id>
counter_ipt() {
  iptables-save -c 2>/dev/null | grep -F -- "--comment \"ppswitch-dep04:$1\"" \
    | head -1 | sed -E 's/^\[([0-9]+):.*/\1/' | grep -E '^[0-9]+$' || echo 0
}
counter_nft() {
  nft list chain inet ppswitch_dep04 fwd 2>/dev/null \
    | grep -F -- "comment \"ppswitch-dep04:$1\"" \
    | grep -oE 'packets [0-9]+' | head -1 | awk '{print $2}' || echo 0
}

assert_counter_delta() { # <backend ipt|nft> <id> <before> <label>
  local backend="$1" id="$2" before="$3" label="$4" now
  if [ "$backend" = ipt ]; then now=$(counter_ipt "$id"); else now=$(counter_nft "$id"); fi
  if [ "$now" -gt "$before" ]; then
    verdict ok "$label" "rule ppswitch-dep04:$id counter $before -> $now (real FORWARD hit)"
  else
    verdict bad "$label" "rule ppswitch-dep04:$id counter did not move ($before -> $now): timeout alone is NOT DROP evidence (errata F1)"
  fi
}

container_id() { docker compose ps -q "$1"; }

# ===========================================================================
section "DEP-04 evidence header"
{
  echo "utc: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "kernel: $(uname -r)"
  echo "docker: $(docker version --format '{{.Server.Version}}')"
  echo "docker firewall backend: $(iptables --version 2>/dev/null || echo n/a)"
  echo "note: the nftables leg runs an independent inet forward-hook table"
  echo "      alongside Docker's firewall backend; it validates OUR nftables"
  echo "      filter effect, NOT Docker's experimental native nft backend"
  echo "      (docs/43 errata, acceptance note V7)."
  echo "iptables legacy/nft: $(iptables -V 2>/dev/null || true)"
  echo "conntrack: $(command -v conntrack >/dev/null && conntrack --version || echo missing)"
} | tee -a "$EVIDENCE"

# ===========================================================================
section "phase 0: stack bring-up (real deploy topology)"

export COMPOSE_FILE="deploy/docker-compose.yml"
export PP_SWITCH_INTERNAL_TOKEN="ci-internal-token-0123456789abcdef"
export PP_SWITCH_DELEGATION_SIGNING_KEY="ci-ticket-key-0123456789abcdef"
export PP_SWITCH_RESULT_ENCRYPTION_KEY="$(python3 -c 'import base64,os;print(base64.urlsafe_b64encode(os.urandom(32)).decode())')"
export EGRESS_PROXY_TOKEN="ci-egress-token-0123456789abcdef"
export PP_SWITCH_DEMO_MODE="false"

if [ "$SKIP_STACK" != "--skip-stack" ]; then
  docker compose build >/dev/null 2>&1 || docker compose build
  docker compose up -d control executor egress-gateway
  for _ in $(seq 1 60); do
    docker exec "$(container_id control)" python -c \
      "import urllib.request;urllib.request.urlopen('http://127.0.0.1:8911/healthz')" 2>/dev/null && break
    sleep 2
  done
fi
EXEC_CID=$(container_id executor); GATE_CID=$(container_id egress-gateway)
log "executor=$EXEC_CID gateway=$GATE_CID"

# pinned-subnet assertions (rules depend on deterministic CIDRs)
INT_SUBNET=$(docker network inspect "$INTERNAL_NET" -f '{{(index .IPAM.Config 0).Subnet}}')
EG_SUBNET=$(docker network inspect "$EGRESS_NET" -f '{{(index .IPAM.Config 0).Subnet}}')
[ "$INT_SUBNET" = "$INTERNAL_CIDR" ] && verdict ok "internal subnet pinned" "$INT_SUBNET" \
  || verdict bad "internal subnet pinned" "expected $INTERNAL_CIDR got $INT_SUBNET"
[ "$EG_SUBNET" = "$EGRESS_CIDR" ] && verdict ok "egress subnet pinned" "$EG_SUBNET" \
  || verdict bad "egress subnet pinned" "expected $EGRESS_CIDR got $EG_SUBNET"
GATE_ACTUAL=$(docker inspect -f "{{.NetworkSettings.Networks.${EGRESS_NET}.IPAddress}}" "$GATE_CID")
[ "$GATE_ACTUAL" = "$GATEWAY_IP" ] && verdict ok "gateway static identity" "$GATE_ACTUAL" \
  || verdict bad "gateway static identity" "expected $GATEWAY_IP got $GATE_ACTUAL (F2 identity broken)"

# ===========================================================================
section "phase 1: routed netns test targets (errata F1)"

ip netns del dep04-approved >/dev/null 2>&1 || true
ip link del veth-dep04a >/dev/null 2>&1 || true
ip netns add dep04-approved
ip link add veth-dep04a type veth peer name eth0 netns dep04-approved
ip addr add 192.0.2.1/24 dev veth-dep04a
ip link set veth-dep04a up
ip netns exec dep04-approved ip addr add 192.0.2.2/24 dev eth0
ip netns exec dep04-approved ip link set eth0 up
ip netns exec dep04-approved ip link set lo up
ip netns exec dep04-approved ip route add default via 192.0.2.1
ip netns exec dep04-approved python3 -m http.server "$APPROVED_PORT" --bind "$APPROVED_IP" >/dev/null 2>&1 &
SERVER_PIDS+=($!)

ip netns del dep04-deny >/dev/null 2>&1 || true
ip link del veth-dep04d >/dev/null 2>&1 || true
ip netns add dep04-deny
ip link add veth-dep04d type veth peer name eth0 netns dep04-deny
ip addr add 198.51.100.1/24 dev veth-dep04d
ip link set veth-dep04d up
ip netns exec dep04-deny ip addr add 198.51.100.2/24 dev eth0
ip netns exec dep04-deny ip link set eth0 up
ip netns exec dep04-deny ip link set lo up
ip netns exec dep04-deny ip route add default via 198.51.100.1
ip netns exec dep04-deny python3 -m http.server "$DENY_PORT" --bind "$DENY_IP" >/dev/null 2>&1 &
SERVER_PIDS+=($!)

log "routed targets: approved=$APPROVED_IP:$APPROVED_PORT deny=$DENY_IP:$DENY_PORT (both via veth, host FORWARD path)"

# PRE-PROOF (errata F1): with no rules applied, every target is genuinely
# reachable - later blocks therefore mean firewall, not missing routing
if probe "$EXEC_CID" "$APPROVED_IP" "$APPROVED_PORT" open; then
  verdict ok "pre-proof executor->approved reachable (rules off)" "destination genuinely routable"
else
  verdict bad "pre-proof executor->approved reachable (rules off)" "target unreachable BEFORE rules: rig broken, all later DROPs meaningless (errata F1)"
fi
probe "$GATE_CID" "$APPROVED_IP" "$APPROVED_PORT" open \
  && verdict ok "pre-proof gateway->approved reachable" "baseline" \
  || verdict bad "pre-proof gateway->approved reachable" "rig broken"
probe "$EXEC_CID" "$DENY_IP" "$DENY_PORT" open \
  && verdict ok "pre-proof executor->deny-target reachable" "baseline" \
  || verdict bad "pre-proof executor->deny-target reachable" "rig broken"

# ===========================================================================
section "phase 2: DNAT published-port rig (errata F3)"

docker rm -f dep04-dnat >/dev/null 2>&1 || true
docker run -d --name dep04-dnat -p "$DNAT_HOST_PORT:8080" \
  pp-switch-control python -m http.server 8080 >/dev/null
DNAT_CIP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' dep04-dnat)
log "dnat container ip=$DNAT_CIP published host port=$DNAT_HOST_PORT (PREROUTING DNAT -> FORWARD -> container)"

# host INPUT supplementary target (errata F3: labelled, NOT FORWARD evidence)
python3 -m http.server "$INPUT_PORT" --bind 0.0.0.0 >/dev/null 2>&1 &
SERVER_PIDS+=($!)

# ===========================================================================
# matrix runner (both backends run the FULL matrix, errata ruling 3)
# ===========================================================================
run_matrix() {
  local backend="$1"
  section "matrix [$backend]: apply rules"

  if [ "$backend" = ipt ]; then
    bash "$RULES" apply-iptables \
      --internal "$INTERNAL_CIDR" --egress "$EGRESS_CIDR" \
      --gateway-ip "$GATEWAY_IP" \
      --approved "$APPROVED_IP/32:$APPROVED_PORT"
  else
    bash "$RULES" apply-nftables \
      --internal "$INTERNAL_CIDR" --egress "$EGRESS_CIDR" \
      --gateway-ip "$GATEWAY_IP" \
      --approved "$APPROVED_IP/32:$APPROVED_PORT"
  fi

  local c_int c_gw c_esub
  if [ "$backend" = ipt ]; then
    c_int=$(counter_ipt internal-drop); c_gw=$(counter_ipt gw-approved); c_esub=$(counter_ipt egress-subnet-drop)
  else
    c_int=$(counter_nft internal-drop); c_gw=$(counter_nft gw-approved); c_esub=$(counter_nft egress-subnet-drop)
  fi
  log "counters before probes: internal-drop=$c_int gw-approved=$c_gw egress-subnet-drop=$c_esub"

  section "matrix [$backend]: P1 intra-subnet service reachability"
  probe "$EXEC_CID" 172.28.0.3 8912 open \
    && verdict ok "P1 executor->executor:8912 (intra internal)" "bridge-local, unaffected by FORWARD rules" \
    || verdict bad "P1 intra" "internal service unreachable"

  section "matrix [$backend]: P2 gateway egress to APPROVED target (F1+F2)"
  if probe "$GATE_CID" "$APPROVED_IP" "$APPROVED_PORT" open; then
    verdict ok "P2 gateway->approved open" "FORWARD path"
  else
    verdict bad "P2 gateway->approved open" "expected allow via gateway static identity"
  fi
  assert_counter_delta "$backend" gw-approved "$c_gw" "P2-counter [$backend]"

  section "matrix [$backend]: P3 executor direct egress is DROPPED (F1+F3 scope)"
  probe "$EXEC_CID" "$APPROVED_IP" "$APPROVED_PORT" blocked \
    && verdict ok "P3 executor->approved blocked" "internal-drop" \
    || verdict bad "P3 executor->approved blocked" "LEAK: direct egress works"
  assert_counter_delta "$backend" internal-drop "$c_int" "P3-counter [$backend]"

  section "matrix [$backend]: P3b never-approved routed target"
  probe "$EXEC_CID" "$DENY_IP" "$DENY_PORT" blocked \
    && verdict ok "P3b executor->deny-target blocked" "no allowlist entry, counter-proven below" \
    || verdict bad "P3b executor->deny-target blocked" "LEAK"
  assert_counter_delta "$backend" internal-drop "$c_int" "P3b-counter [$backend] (routed, pre-proven reachable)"

  section "matrix [$backend]: F2 executor misattached to the routed egress network"
  docker network connect "$EGRESS_NET" "$EXEC_CID" 2>/dev/null || true
  if probe "$EXEC_CID" "$APPROVED_IP" "$APPROVED_PORT" blocked; then
    verdict ok "F2 misattached executor still blocked" "subnet allow would have leaked (errata F2)"
  else
    verdict bad "F2 misattached executor still blocked" "CRITICAL: subnet-wide allow leaked to misattached executor"
  fi
  assert_counter_delta "$backend" egress-subnet-drop "$c_esub" "F2-counter [$backend]"
  probe "$GATE_CID" "$APPROVED_IP" "$APPROVED_PORT" open \
    && verdict ok "F2 gateway unaffected during misattach" "identity rule matched" \
    || verdict bad "F2 gateway unaffected during misattach" "regression"
  docker network disconnect "$EGRESS_NET" "$EXEC_CID" || true

  section "matrix [$backend]: F3 DNAT published port (external vantage via netns)"
  if probe_netns dep04-approved 192.0.2.1 "$DNAT_HOST_PORT" open; then
    verdict ok "F3 DNAT external->published port open" "PREROUTING DNAT -> FORWARD -> container"
  else
    verdict bad "F3 DNAT external->published port open" "published port unreachable from external vantage"
  fi
  if command -v conntrack >/dev/null; then
    if conntrack -L -p tcp --dport "$DNAT_HOST_PORT" 2>/dev/null | grep -q "dport=$DNAT_HOST_PORT"; then
      verdict ok "F3 DNAT conntrack evidence" "$(conntrack -L -p tcp --dport "$DNAT_HOST_PORT" 2>/dev/null | head -1)"
    else
      verdict bad "F3 DNAT conntrack evidence" "no conntrack entry for dport=$DNAT_HOST_PORT"
    fi
  else
    pending "F3 DNAT conntrack listing (conntrack tool absent; counter+reachability recorded)"
  fi
  if probe_netns dep04-approved "$DNAT_CIP" 8080 blocked; then
    verdict ok "F3 unpublished container port blocked from external" "DNAT scope only"
  else
    verdict bad "F3 unpublished container port blocked from external" "unpublished port reachable"
  fi

  section "matrix [$backend]: F3 SNAT outbound evidence (gateway flow)"
  if command -v conntrack >/dev/null; then
    if conntrack -L -p tcp --dport "$APPROVED_PORT" 2>/dev/null | grep -q "$APPROVED_IP"; then
      verdict ok "F3 SNAT conntrack evidence" "$(conntrack -L -p tcp --dport "$APPROVED_PORT" 2>/dev/null | grep "$APPROVED_IP" | head -1)"
    else
      verdict bad "F3 SNAT conntrack evidence" "no flow to approved target recorded"
    fi
  else
    pending "F3 SNAT conntrack listing (conntrack tool absent)"
  fi

  section "matrix [$backend]: F3 host INPUT hardening (supplementary, NOT FORWARD evidence)"
  local c_input
  c_input=$(iptables-save -c 2>/dev/null | grep -F -- '--comment "ppswitch-dep04:input-drop"' \
    | head -1 | sed -E 's/^\[([0-9]+):.*/\1/' || echo 0)
  if [ "$c_input" = "" ]; then c_input=0; fi
  iptables -w -I INPUT -s "$INTERNAL_CIDR" -p tcp --dport "$INPUT_PORT" -m comment \
    --comment "ppswitch-dep04:input-drop" -j DROP
  if probe "$EXEC_CID" 172.28.0.1 "$INPUT_PORT" blocked; then
    verdict ok "INPUT container->host service blocked" "labelled INPUT-path host hardening"
  else
    verdict bad "INPUT container->host service blocked" "host INPUT open to internal subnet"
  fi
  local c_input_after
  c_input_after=$(iptables-save -c 2>/dev/null | grep -F -- '--comment "ppswitch-dep04:input-drop"' \
    | head -1 | sed -E 's/^\[([0-9]+):.*/\1/' || echo 0)
  if [ "$c_input_after" -gt "$c_input" ]; then
    verdict ok "INPUT counter evidence" "input-drop $c_input -> $c_input_after"
  else
    verdict bad "INPUT counter evidence" "counter did not move ($c_input)"
  fi

  section "matrix [$backend]: rollback + zero residue (F4/F7)"
  bash "$RULES" rollback
  if bash "$RULES" residue >/dev/null 2>&1; then
    verdict bad "zero residue [$backend]" "tagged rules remain after rollback"
  else
    verdict ok "zero residue [$backend]" "no ppswitch-dep04 rules in iptables/ip6tables/nft"
  fi
  # post-rollback reachability restored (proves the DROPs were OUR rules)
  probe "$EXEC_CID" "$APPROVED_IP" "$APPROVED_PORT" open \
    && verdict ok "post-rollback executor->approved reachable again" "DROPs were caused by the tested rules" \
    || verdict bad "post-rollback reachability" "still blocked after rollback"
}

# ===========================================================================
section "phase 3: full matrix, iptables backend (DOCKER-USER)"
run_matrix ipt

section "phase 4: full matrix, nftables backend (inet forward hook)"
run_matrix nft

# ===========================================================================
section "phase 5: forced address drift (F4 - V3, proven not assumed)"

declare -A IP_BEFORE
for svc in executor egress-gateway control; do
  IP_BEFORE[$svc]=$(docker inspect -f "{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}" "$(container_id $svc)")
done
docker compose up -d --force-recreate control executor egress-gateway >/dev/null 2>&1
# force a change where force-recreate alone kept the lease: occupy then recreate
for svc in executor egress-gateway; do
  new_ip=$(docker inspect -f "{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}" "$(container_id $svc)")
  if [ "$new_ip" = "${IP_BEFORE[$svc]}" ]; then
    docker rm -f dep04-occupier >/dev/null 2>&1 || true
    docker run -d --name dep04-occupier --network "$INTERNAL_NET" \
      pp-switch-control sleep 300 >/dev/null
    docker compose up -d --force-recreate "$svc" >/dev/null 2>&1
    new_ip=$(docker inspect -f "{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}" "$(container_id $svc)")
  fi
  if [ "$new_ip" != "${IP_BEFORE[$svc]}" ]; then
    verdict ok "drift [$svc] address changed" "${IP_BEFORE[$svc]} -> $new_ip"
  else
    verdict bad "drift [$svc] address changed" "could not force a change: item INCOMPLETE per errata F4"
  fi
done
GATE_ACTUAL=$(docker inspect -f "{{.NetworkSettings.Networks.${EGRESS_NET}.IPAddress}}" "$(container_id egress-gateway)")
[ "$GATE_ACTUAL" = "$GATEWAY_IP" ] \
  && verdict ok "gateway static identity survives recreate" "$GATE_ACTUAL" \
  || verdict bad "gateway static identity survives recreate" "got $GATE_ACTUAL"
EXEC_CID=$(container_id executor); GATE_CID=$(container_id egress-gateway)

section "phase 5b: matrix rerun after drift (iptables backend)"
run_matrix ipt

# ===========================================================================
section "phase 6: IPv6 parity (V5 - real pass or PENDING, never silent skip)"

V6_OK=1
if ! sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null | grep -q '^0$'; then
  V6_OK=0; pending "IPv6: host disables IPv6 (net.ipv6.conf.all.disable_ipv6!=0)"
fi
if [ "$V6_OK" = 1 ]; then
  ip netns del dep04-v6 >/dev/null 2>&1 || true
  ip link del veth-dep04v6 >/dev/null 2>&1 || true
  docker network rm dep04v6 >/dev/null 2>&1 || true
  if ip netns add dep04-v6 \
     && ip link add veth-dep04v6 type veth peer name eth0 netns dep04-v6 \
     && ip addr add fd00:db8:cafe::1/64 dev veth-dep04v6 \
     && ip link set veth-dep04v6 up \
     && ip netns exec dep04-v6 ip addr add fd00:db8:cafe::2/64 dev eth0 \
     && ip netns exec dep04-v6 ip link set eth0 up \
     && ip netns exec dep04-v6 ip link set lo up \
     && ip netns exec dep04-v6 ip route add default via fd00:db8:cafe::1 \
     && ip netns exec dep04-v6 python3 -m http.server "$APPROVED_PORT" --bind fd00:db8:cafe::2 >/dev/null 2>&1 \
     && docker network create --ipv6 --subnet fd00:db8:fee::/64 dep04v6 >/dev/null 2>&1 \
     && docker network connect dep04v6 "$(container_id executor)" 2>/dev/null; then
    # pre-proof
    if probe "$EXEC_CID" fd00:db8:cafe::2 "$APPROVED_PORT" open; then
      ip6tables -w -I DOCKER-USER 1 -s fd00:db8:fee::/64 -d fd00:db8:cafe::/64 -m comment \
        --comment "ppswitch-dep04:v6-intra" -j ACCEPT 2>/dev/null || true
      ip6tables -w -I DOCKER-USER 2 -s fd00:db8:fee::/64 -m comment \
        --comment "ppswitch-dep04:v6-internal-drop" -j DROP
      if probe "$EXEC_CID" fd00:db8:cafe::2 "$APPROVED_PORT" blocked; then
        verdict ok "IPv6 executor direct egress DROPPED" "ip6tables DOCKER-USER"
      else
        verdict bad "IPv6 executor direct egress DROPPED" "v6 leak"
      fi
      bash "$RULES" rollback
    else
      pending "IPv6: pre-proof unreachable (runner v6 container networking limited) - target-host evidence required"
    fi
    docker network disconnect dep04v6 "$(container_id executor)" 2>/dev/null || true
  else
    pending "IPv6: v6 rig unavailable on this host - target-host evidence required"
  fi
fi

# ===========================================================================
section "summary"
log "pass=$PASS fail=$FAIL pending=${#PENDING[@]}"
for item in "${PENDING[@]:-}"; do [ -n "$item" ] && log "  PENDING: $item"; done
log "evidence: $EVIDENCE"
if [ "$FAIL" -gt 0 ]; then
  log "DEP-04 host-firewall verification: FAILED"
  exit 1
fi
log "DEP-04 host-firewall verification: PASSED (pending items are recorded as待补, not passes)"
