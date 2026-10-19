# DEP-04 host firewall：CI 模式与目标主机 runbook

`rules.sh` + `verify-host-firewall.sh` 构成 AUD-DEP-04 的验收装置
（docs/43 + 四项勘误）。**两种运行语义严格分离（勘误 F4）**：

## 1. CI 测试模式（默认）

```bash
sudo bash deploy/host-firewall/verify-host-firewall.sh
```

- 临时安装规则 → 全矩阵（iptables 与 nftables 双后端各完整跑一遍，
  含 F2 误接负向、DNAT/SNAT conntrack 证据、INPUT 补充项、强制地址
  漂移后重跑）→ **退出时 trap 回滚**并断言零残余；
- 证据写入 `evidence-<utc>.log`（CI 以 artifact 归档）；
- **绝不在正式主机上用这个模式清理生产规则**。

## 2. 企业目标主机模式（上线时点，人工执行）

### 2.1 安装持久化策略（经变更审批）

```bash
sudo bash deploy/host-firewall/rules.sh apply-iptables \
  --internal 172.28.0.0/24 --egress 172.29.0.0/24 \
  --gateway-ip 172.29.0.2 --approved <approved-ip>/32:443
# 持久化（重启存活，按发行版二选一）：
sudo netfilter-persistent save          # Debian/Ubuntu
sudo iptables-save | sudo tee /etc/sysconfig/iptables   # RHEL 系
```

- 目标（`--approved`）与 `deploy/.env` 的 `EGRESS_ALLOWED_HOSTS`
  **同源维护**——两道独立信任根的 allowlist 必须一致；
- 网段来自 compose 钉定值；若目标主机改网段，必须同步改规则并
  重跑验证（子网重分配 → 规则适配性重校验，勘误 F4）。

### 2.2 重启存活验证（Gate R1 生产证据）

```bash
sudo systemctl restart docker && sudo bash deploy/host-firewall/rules.sh counters-iptables
sudo reboot   # 之后再次：
sudo bash deploy/host-firewall/rules.sh counters-iptables
```

规则在 Docker 重启与宿主重启后仍存在且计数器继续累加，才构成
"重启存活"证据。

### 2.3 紧急恢复（预演过的破玻璃路径）

```bash
sudo bash deploy/host-firewall/rules.sh rollback    # 只删 ppswitch-dep04 标注规则
```

- 回滚**只删除带 `ppswitch-dep04` 注释的自有规则**，不触碰 Docker
  自身链——这是勘误 F4 认可的精确清理语义；
- 恢复后按 2.1 重装；恢复演练必须在上线前至少执行一次并记录。

### 2.4 后端说明（勿混淆）

- 本装置的 nftables 腿是**独立 inet 表**（forward hook），与 Docker
  自身防火墙后端并存：它验证的是**我们 nftables 规则的过滤效果**，
  **不等于**验证了 Docker 原生 nftables 后端（官方仍标注实验性）。
  证据头会记录 `iptables -V` 实际后端（legacy 或 nft）。
- 目标主机若使用防火墙管理器（ufw/firewalld），以管理器语法录入
  等价 FORWARD 规则后，同样用 `verify-host-firewall.sh --skip-stack`
  重跑矩阵取证。

## 3. 断言语义（勘误落点速查）

| 现象 | 是否构成证据 |
| --- | --- |
| 探测超时 | **否**——必须同时有 `ppswitch-dep04:*` 规则计数器增量（F1） |
| 宿主本地服务被拒 | 仅证明 INPUT 路径——标记为补充项，不算 FORWARD 证据（F3） |
| 网段放行后 gateway 可达 | **否**——放行必须绑定 gateway 静态身份；误接 executor 仍拒（F2） |
| force-recreate 后 IP 未变 | 该项**未完成**（F4），必须主动制造并记录变化 |
| IPv6 SKIPPED | 记为**待补**，绝不计为通过（V5） |
