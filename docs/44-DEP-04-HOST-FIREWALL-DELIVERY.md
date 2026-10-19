# 44 · DEP-04 交付记录：宿主机 FORWARD 路径防火墙实测

> 实施依据：docs/43（`4b4354b` 批准 + 四项约束性勘误，勘误已回写
> docs/43 §8）。开发门禁证据 = CI `AUD-DEP-04 host firewall matrix`
> job（ubuntu-latest 完整 VM，规则落在真实宿主 netns）；企业生产
> Gate 仍需目标部署主机按 `deploy/host-firewall/README.md` 跑同装置
> 并归档证据。

## 0. 交付物

| 文件 | 职责 |
| --- | --- |
| `deploy/host-firewall/rules.sh` | 双后端规则（iptables DOCKER-USER / nftables inet forward hook），每条带 `ppswitch-dep04:<id>` 注释标签；counters/residue/rollback 子命令（回滚只删自有标签规则，覆盖 DOCKER-USER/INPUT × iptables/ip6tables + nft 表） |
| `deploy/host-firewall/verify-host-firewall.sh` | 全矩阵编排：netns 受控目标搭建、基线可达性预证、双后端各完整矩阵（P1 网段内、P2 gateway 放行、P3/P3b executor 直连 DROP+计数器、F2 误接负向、F3 DNAT/SNAT conntrack、INPUT 补充项）、强制地址漂移 + 漂移后重跑、IPv6 真测或 PENDING、回滚零残余 + 复原断言；证据 tee 至 `evidence-<utc>.log` |
| `deploy/host-firewall/README.md` | 目标主机 runbook：持久化安装、重启存活验证、紧急恢复预演、后端说明 |
| `.github/workflows/ci.yml` | 新增 `AUD-DEP-04 host firewall matrix` job（装 conntrack → sudo 跑装置 → upload-artifact 归档证据） |
| `deploy/docker-compose.yml` | 钉定 internal/egress 网段；gateway 静态身份 172.29.0.2 且 egress 网为默认路由所有者（F2 身份基础，同时对生产确定性有益） |

## 1. 勘误 → 断言映射（V1–V7 修订口径）

| 验收 | 装置内断言 |
| --- | --- |
| V1 | P3/P3b：executor→approved 与 executor→deny（均预证可达）超时 **且** `internal-drop` 计数器增量 >0；双后端各跑 |
| V2 | P2：gateway→approved 可达 **且** `gw-approved` 计数器增量 >0（真实 FORWARD 命中） |
| V3 | 漂移阶段记录前后 IP；无法制造变化判未完成；漂移后完整重跑含 F2 误接负向（executor 接上 egress 网仍被拒 + `egress-subnet-drop` 计数器增量） |
| V4 | DNAT（发布端口，外部视点 + conntrack）、SNAT（gateway 流 conntrack）、INPUT（带标签规则 + 计数器，标注为补充项）三类证据各自独立成节，互不引用 |
| V5 | IPv6 真测通过；不具备条件输出 `PENDING`（待补），summary 明示"pending 不计为 pass" |
| V6 | CI：rollback 后 `residue` 为零 **且** executor→approved 恢复可达；目标主机：runbook 的持久化/重启存活/紧急恢复与 CI 模式严格分离 |
| V7 | 双后端各有完整矩阵（含漂移重跑）；evidence 日志 artifact 归档；证据头记录 `iptables -V` 实际后端并注明 nftables 腿 ≠ Docker 原生 nft 后端 |

## 2. CI 迭代记录（如实，随首跑更新）

- 首跑及修复过程在本节按轮记录（FEAT-04 PG 层同款节奏）。

## 3. 边界

- 开发门禁证据来自 ephemeral CI VM（评审裁决①认可）；企业生产
  Gate R1 仍需目标主机实测（含 IPv6 边界、持久化与恢复演练）。
- nftables 腿验证本装置规则效果，不验证 Docker 原生 nftables
  后端（实验性）。
- compose 网段变更必须同步规则并重跑（README §2.1）。
