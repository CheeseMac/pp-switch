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

## 2. CI 迭代记录（如实，2026-10-19，共 15 轮至全绿）

本机为 Windows 开发环境，装置以 CI 首跑为验证场。全部失败原因与
修复逐轮记录（`2c89bd7 → 6b5b362`）：

| 轮 | 失败点 | 根因与修复 |
| --- | --- | --- |
| 1 | 脚本秒退 | 仓库根路径差一级（`cd ../..`） |
| 2 | docker inspect 模板错 | Go 模板不认带连字符的 map 键 → index 函数 + printf 构造 |
| 3 | 同上 | 双引号内层嵌套终止了外层串 → printf 单引号构造 |
| 4 | 预证不可达 + 回滚 Bad rule | **设计修正**：internal:true 网络本就无路由——直连出站视点改为"误接 egress 网的同镜像替身容器 dep04-misexec"（恰为勘误 F2 场景的诚实形态）；executor 本体保留"无路由 layer-1"断言（不主张计数器）；spec 匹配 -D 不稳定 → 行号删除（后续再改状态文件法，见轮 7） |
| 5 | 镜像名错 | compose 项目前缀 pp-switch-control（少了连字符） |
| 6 | 残留+回滚后仍被阻 | iptables -L 不显示注释标签（需 -v）→ 行号法空转；nft 链 policy 子句解析失败 → 去掉显式 policy |
| 7 | INPUT 规则删不掉 | **iptables-nft 的 -D 只认插入时的原始 argv**，save 归一化 spec（多 -m tcp 等）会 Bad rule → 插入时把删除 argv 记入状态文件，回滚原样重放 + 致命清扫兜底 |
| 8 | 网关自拒 | 规则重写时插入顺序颠倒，egress-subnet-drop 排在身份放行前 → 恢复 intra/dns/gw/drop 顺序 |
| 9 | usage 退出 | add-input-drop 被强制四参校验 → 独立解析器 |
| 10 | 同上回归 | parse_args 的 require_all 参数吃掉首个 flag → 拆 parse_input_args |
| 11 | 残留断言反了 / 回滚后视点错 / nft 表名单参 | residue 语义极性修正（clean=exit 0）；回滚后可达性改用 misexec 视点；$NFT_TABLE 两词去引号 |
| 12 | nft 链定义解析失败 | 改 `nft -f` 文件输入 |
| 13 | 仍然失败（同一 token） | **`fwd` 是新版 nft 的保留语句关键字**（fwd to）→ 链改名 dep04fwd |
| 14 | nft 计数器读 0 / 漂移未变 / layer-2 检查引用旧链名 | 计数解析改按行取 packets；漂移加 disconnect+connect --ip 运行时重定址兜底；layer-2 检查改 list 表 |
| 15 | 顶层 `local` | bash 只允许函数内 local → 去掉 |

**终态**：64 PASS / 0 FAIL / 1 PENDING（IPv6 在 runner 无 v6 容器网络，
按勘误②记为待补、不计为通过，目标主机实机补证）。

设计层面的两处诚实修正（已并入装置语义，docs/43 §8 同步）：
- **直连出站的可测视点**：正确拓扑下 executor 在 internal:true 网上
  根本没有路由——"executor 直连被宿主规则 DROP"的宿主层证据只能来
  自有路由的误接视点（dep04-misexec，同镜像、仅挂 egress 网）；
  executor 本体的阻断是编排层隔离（layer-1，不主张 FORWARD 计数器）。
- **internal-drop 计数器不主张增量**：正确拓扑下 internal 网段根本
  不产生跨 FORWARD 流量（零流量才是健康态），该规则作为纵深防御
  仅断言"已安装"。

## 3. 边界

- 开发门禁证据来自 ephemeral CI VM（评审裁决①认可）；企业生产
  Gate R1 仍需目标主机实测（含 IPv6 边界、持久化与恢复演练）。
- nftables 腿验证本装置规则效果，不验证 Docker 原生 nftables
  后端（实验性）。
- compose 网段变更必须同步规则并重跑（README §2.1）。
