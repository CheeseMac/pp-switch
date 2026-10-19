# 43 · 设计提案：DEP-04 真实宿主机网络策略实测（待审批）

> **状态：待审批**（2026-10-19 提交，基线 `55d2e68`）。获批前不写
> 实现代码。范围：**仅** Gate R1 的 AUD-DEP-04（宿主机防火墙实测），
> 不动应用层/网关已验收逻辑，不涉及 ID-07/DATA-08/生产
> SecretProvider。

## 0. 一句话结论

把 docs/28 §1.3 的 FORWARD 路径样例（iptables `DOCKER-USER` 与
nftables `forward` hook 双后端）落成**可重复执行的验收装置**：
`deploy/host-firewall/` 规则脚本（幂等 + trap 回滚）+ 探针编排
`verify-host-firewall.sh`（正/负探测矩阵 + 容器重启漂移 + DNAT 场景
+ IPv6）+ 专用 CI job（ubuntu-latest runner 是带独立内核与 sudo 的
完整 VM，DOCKER-USER/nftables 规则正落在其宿主 netns——即一台
**可复现的真实 Linux 主机**）+ 同一脚本供目标部署主机在上线时点
重跑并归档证据。

## 1. 缺口（Gate R1 原文口径）

AUD-DEP-04：样例已就绪但**从未在真实主机上实测**——现有 CI 只覆盖
容器级（compose 网络隔离），宿主机 FORWARD 路径的 DOCKER-USER /
nftables 规则没有任何执行证据，因此"三层出口隔离"的第三层在企业
部署语境下仍是纸面承诺（docs/30 §状态表、docs/31 §3）。

需证明的具体行为（来自审计与 docs/28 §1.3 注释）：

| # | 行为 | 为什么难 |
| --- | --- | --- |
| F1 | internal 网段容器出站到未批准目标在**宿主 FORWARD 路径**被 DROP；网段内互访与已批准目标放行 | Docker 桥接流量不走主机 OUTPUT 链——挂错链=形同虚设（DEP-14-F2 的教训） |
| F2 | egress-gateway 经规则放行后可达已批准目标 | 白名单要与网关 allowlist 同源 |
| F3 | executor 直连出站被 DROP（即使被误挂到有路由网络） | 纵深防御第二层 |
| F4 | **IPv6 同等覆盖**（ip6tables DOCKER-USER / nftables inet 族） | v4 样例无 v6 证据；NAT64/v4-mapped 归一是网关层已有的坑 |
| F5 | **容器重启地址漂移**后规则仍成立 | 按容器单 IP 立规则会在 recreate 后失效——规则必须按网段 |
| F6 | **DNAT/SNAT 场景**：发布端口 DNAT 流量与出站 SNAT 路径不被规则意外放行/误伤 | FORWARD 链在 DNAT 后遍历，语义易错 |
| F7 | 规则装置本身可安全回滚（trap 清理，不留残余 DROP） | 测试装置不能把主机搞坏 |

## 2. 威胁模型与不变式

- 攻击面：**已攻陷的容器**（executor/control/mock 任一）试图绕过
  编排层网络隔离直接出站（含经 IPv6、经发布端口反射、经重启换
  地址）。宿主防火墙是第二道独立信任根——即使 compose 配置被误改
  （如容器被误挂 egress 网络），FORWARD 规则仍拒绝。
- 不变式：只有 egress-gateway 网段可去往已批准目标:443；internal
  网段互访与 DNS（udp/53，Docker 内嵌 DNS 转发）放行；其余 FORWARD
  一律 DROP；v4/v6 同规则。
- 不在范围：Windows 宿主（docs/28 已单列文档化承诺）、rootless
  Docker（不同链路径）、K8s、生产路由器策略、网关自身 allowlist
  逻辑（已验收）。

## 3. 装置设计

### 3.1 规则脚本 `deploy/host-firewall/rules.sh`

- 子命令：`apply-iptables` / `apply-nftables` / `rollback`；
- **只插入自有规则**（iptables 用 `DOCKER-USER` 精确 spec 插入、
  rollback 按同 spec 删除；nftables 建独立表 `inet ppswitch_egress_test`，
  rollback 整表删除）——不触碰 Docker 自身链；
- 参数化：internal 网段（默认取 compose 实际网段，**按网段而非
  单 IP**，即 F5 的结构性答案）、已批准目标（测试装置用 runner
  宿主自身起的本地 TCP 服务，绝不出真实外网——`--approved
  <ip>:<port>`）；
- `rollback` 幂等；脚本自带 `set -euo pipefail` + 用法自检。

### 3.2 探针编排 `deploy/host-firewall/verify-host-firewall.sh`

阶段化执行，任一断言失败即非零退出：

1. **准备**：起 deploy 栈（复用 `deploy/docker-compose.yml`）+
   宿主上起"已批准目标"（python 一行 TCP 回显服务，绑定非 8911-8914
   端口）+ 记录各容器 IP；
2. **apply-iptables → 矩阵探测**：
   - P1 网段内互访（executor→control 8911）= 通；
   - P2 gateway→已批准目标（宿主测试服务）= 通（F2）；
   - P3 executor 直连已批准目标 = **DROP/超时**（F1/F3）；
   - P4 executor 直连任意未批准外网地址 = DROP（用不存在网段
     198.51.100.10:443，RFC5737，零真实外联）；
   - P5 外部探针容器→发布端口 DNAT = 仅预期端口可达（F6 正向），
     其余 DROP；
   - P6 内部容器→宿主非批准端口 = DROP（F6 SNAT 路径反向）；
3. **重启漂移**（F5）：`docker compose up -d --force-recreate`
   全栈 → 断言容器 IP 已变化 → **完整重跑 P1–P6**（规则未随 IP
   失效即通过）；
4. **rollback → 断言残余为零**（`iptables -S DOCKER-USER` 无自有
   spec、`nft list table` 报不存在）（F7）；
5. **apply-nftables → 重跑矩阵（P1–P6）→ rollback**（双后端同证）；
6. **IPv6（F4）**：优先在测试 compose 里启用 v6 子网（自定义
   `ipam` v6 段 + 宿主 `sysctl net.ipv6.conf.default...` runner 通常
   已满足）→ ip6tables/ inet 族同矩阵；**若 runner 内核/网桥不支持
   v6 容器网络**（探测步骤自动判定），本阶段自动标记 SKIPPED-v6
   并在证据中显式记录——v6 证据转由 §3.4 的人工主机跑一次补齐，
   该降级在批复时请评审裁定是否接受；
7. **证据**：全程 tee 到 `evidence-<utc-ts>.log`（含规则 dump、
   每探针的期望/实际/判定、容器 IP 前后对照），CI 另以
   `upload-artifact` 归档。

### 3.3 CI job `host-firewall (AUD-DEP-04)`

- `runs-on: ubuntu-latest`（完整 VM：自有内核、sudo、Docker in
  Docker 不需要——runner 自带 docker daemon）；
- 步骤：checkout → `sudo bash deploy/host-firewall/verify-host-firewall.sh`
  → upload-artifact(evidence)；
- **与现有 docker-deploy job 的分工**：docker-deploy 验证栈内行为，
  host-firewall 验证宿主 FORWARD 层；互不替代。

### 3.4 目标部署主机的人工证据（上线时点）

同一 `verify-host-firewall.sh` 在企业目标主机跑一次（runbook 步骤
写入 docs/28 §1.3 末尾），产出的 evidence 日志归入部署审计材料。
开发门禁以 CI 证据为准；上线门禁以目标主机证据为准——两层都指向
同一装置，无第二套代码。

## 4. 验收标准（获批后的实施定义）

| # | 必须证明 | 证据形态 |
| --- | --- | --- |
| V1 | F1/F3：internal 直连出站在宿主层 DROP（双后端） | evidence 日志 P3/P4 判定行 |
| V2 | F2：gateway 放行路径可用 | P2 |
| V3 | F5：force-recreate 换 IP 后矩阵全绿 | 漂移段完整重跑记录 |
| V4 | F6：DNAT/SNAT 场景无意外放行 | P5/P6 |
| V5 | F4：v6 同矩阵（或显式 SKIPPED-v6 + 人工主机补证记录） | v6 段或降级标注 |
| V6 | F7：rollback 零残余 | 步骤 4 断言 |
| V7 | 装置可重复：CI 每次运行均产出 evidence artifact | CI 历史 |
| 回归 | 六 job + Security gates 不回退；deploy/verify-deployment.sh 不受影响 | CI |

## 5. 开放问题（请评审裁定）

1. **证据主体**：以 ephemeral CI VM 为开发门禁证据 + 目标主机跑同
   脚本为上线证据（本提案推荐），还是 AUD-DEP-04 必须以持久化真实
   主机的一次实测为准（CI 仅辅助）？
2. **IPv6 降级口径**：runner 若不支持 v6 容器网络，"SKIPPED-v6 +
   人工主机补证"是否可接受为开发门禁？
3. **双后端覆盖深度**：iptables 与 nftables 各跑全矩阵（本提案，
   时长约 +3–4 分钟）还是轮换执行？
4. 测试用的"已批准目标"以 runner 宿主自起的本地服务充当（零真实
   外联、可断言），是否满足"已批准目标"语义，或要求至少一次对
   CI 允许的真实 HTTPS 端点（如 GitHub API）的放行验证？

## 6. 获批后实施拆分

1. `deploy/host-firewall/rules.sh`（双后端 + rollback）；
2. `verify-host-firewall.sh`（矩阵/漂移/DNAT/v6/证据）；
3. `.github/workflows/ci.yml` 新增 host-firewall job + artifact；
4. docs/28 §1.3 附 runbook 步骤；docs/44 交付记录（V1–V7 映射）；
   docs/30 状态表更新；
5. 本地无法验证（Windows 开发机）——实现后直接以 CI job 首跑为
   验证场，失败迭代如实记录（FEAT-04 PG 层同款节奏）。

预估：2 个脚本 + 1 个 job + 文档；无应用代码改动。
