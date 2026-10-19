# 45 · 交接文档（面向 M2 实机试用与会话归档）

> 写给下一个开发会话与归档后的任何人。本会话（FEAT-04 → SECRET-06 →
> DEP-04 全链）已归档；本文是**唯一入口**：项目现状、待办、入口
> 指针全在这。通用架构地图/踩坑/红线仍见
> [docs/31-HANDOVER.md](31-HANDOVER.md)，其状态快照以本文为准。

## 0. 状态快照（2026-10-19，基线见 §1）

- **CI：七个 job + Security gates 双绿**（双平台 Python / 前端 /
  PostgreSQL matrix / Docker deploy / M2 install smoke /
  AUD-DEP-04 host firewall matrix）。本地全量 pytest 376 通过 /
  23 跳过（Windows 本机跳过项=shared-keyring POSIX 专属用例）。
- **已正式关闭（不重审）**：
  - FEAT-01 浏览器 Collector、FEAT-02 发布向导、FEAT-05A Agent
    一键接入（docs/32/33/34）；
  - FEAT-03 本地 Keyring（docs/35 + 37）；
  - FEAT-04 只读 PostgreSQL 发现首切片（`78576c7`，docs/39）；
  - M2 第一腿：安装自检 + Quickstart + 验收剧本（`f2ecc6a`，docs/40）；
  - SECRET-06 共享 Keyring 隔离（`55d2e68`，docs/41/42）——
    个人模式与 POSIX shared 无保留验收；**Windows shared 主动
    拒启**（R13 守门，ACL 实现另案）。
- **已实施待验收**：
  - DEP-04 宿主机 FORWARD 路径防火墙实测装置（docs/43/44，
    矩阵 64 PASS/0 FAIL/1 PENDING——IPv6 待目标主机实机补证，
    按批复口径 PENDING≠PASS）。评审复核后可申请开发态验收。
- **进行中（用户本人，非开发任务）**：
  - **M2 实机试用**：Chrome 扩展（docs/40 §3）与 Claude Desktop/
    Cursor MCP（docs/40 §4）两剧本 + §6 记录表回传 → M2 整体
    签收。试用日一页清单在 docs/40 §0（T1–T13）。
- **未开工（需独立提案/批复）**：
  - Gate R1 剩余：ID-07（OIDC/身份）、DATA-08（多实例/恢复演练）、
    企业生产侧目标主机实机证据（含 DEP-04 IPv6 补证）；
  - SECRET-06 生产腿（OpenBao SecretProvider）；Windows shared
    ACL 实现；FEAT-04 多行查询（先定义行集授权语义）。

## 1. 提交链基线

| 里程碑 | 提交 | 文档 |
| --- | --- | --- |
| FEAT-04 首切片验收关闭 | `78576c7` | docs/38/39 |
| M2 第一腿验收关闭 | `f2ecc6a` | docs/40 |
| SECRET-06 提案→批复 | `7404fbe`/`b767e2b` | docs/41 |
| SECRET-06 实施+定向修复关闭 | `9e2f5c9`/`26e64b2`/`55d2e68` | docs/42 |
| DEP-04 提案→批复 | `4b4354b` | docs/43 |
| DEP-04 装置全绿（15 轮迭代） | `6b5b362`，记录 `1d4bfbe` | docs/44 |
| 试用就绪（本会话收尾） | 见 git log（docs/40 §0 + MCP trust_env 修复） | docs/40/45 |

## 2. 下一个会话怎么接手

1. **若用户带回答用证据**：核对 docs/40 §6 记录表 → 全通过则整理
   M2 整体签收申请（材料=记录表+截图说明）；有失败项按现象定位
   （对照 docs/40 §0 的三个 Windows 坑）。
2. **若评审复核 DEP-04**：对照 docs/44 §1 的 V1–V7 映射与 §2 的
   15 轮迭代记录应答；注意装置语义的两处诚实修正（misexec 视点、
   internal-drop 不主张计数器增量）已在 docs/43 §8 备案。
3. **开新门禁（ID-07/DATA-08）**：按 SECRET-06/DEP-04 的节奏——
   先写设计提案（docs/NN-PROPOSAL）→ 评审批复（含勘误）→ 实施 →
   交付记录（验收矩阵+CI 迭代如实记录）。
4. 日常操作速查：docs/31 §4（uv sync --all-packages / pytest /
     ruff / mypy / check-no-secrets / pnpm 三连 / dev-up）。

## 3. 本会话新增的坑（补进长期清单，docs/31 §5 之上）

1. **iptables-nft 的 `-D` 只认插入时的原始 argv**——从 iptables-save
   重建的 spec 会被归一化（多出 `-m tcp` 等）而 Bad rule；回滚要
   状态文件记录删除 argv 重放（deploy/host-firewall/rules.sh）。
2. **`fwd` 是新版 nft 的保留语句关键字**，不能做链名（"unexpected
   fwd, expecting string"）。
3. **docker IPAM 确定性复用低址**：force-recreate 不保证换 IP；
   漂移测试用 disconnect+connect --ip 强制重定址。
4. **internal:true 网络根本没有路由**："executor 直连被宿主 DROP"
   的宿主层证据只能来自有路由的误接视点（同镜像替身容器）。
5. **Go template 不认带连字符的 map 键**：docker inspect -f 需要
   `index .NetworkSettings.Networks "带-的名字"`，且 bash 双引号
   嵌套要用 printf 构造模板。
6. **GUI 启动的客户端不继承终端 PATH**：Claude Desktop/Cursor 的
   MCP 配置可能需要 uv 绝对路径 + `--directory` 指向仓库。
7. **MCP/HTTP 客户端一律 trust_env=False**：本会话补掉了 MCP 适配
   器内部 client 的遗漏（Windows 系统代理拦 127.0.0.1 会毁首次
   实机试用）。
8. 写 bash 装置时**顶层循环里不能用 `local`**；heredoc 长内容在
   Git Bash 会静默截断（老坑，又踩两次——一律用 Write 工具写
   补丁文件再执行）。

## 4. 文档索引（本阶段新增）

- docs/38 FEAT-04 交接 / 39 FEAT-04 交付 / 40 Alpha 试用（§0 试用
  日清单 + §3/§4 剧本 + §6 记录表）/ 41-42 SECRET-06（提案+交付）/
  43-44 DEP-04（提案+交付）/ 45 本文。
- 评审批复链：36/37（FEAT-03 收口）→ 38 批复 FEAT-04 → 40 批复
  M2 第一腿 → 41 批复 SECRET-04…06 三轮（设计→定向修复→限定范围
  →最终关闭）→ 43 批复 DEP-04（含四勘误）。
- 全部历史：README 文档导航表。

## 5. 待用户手动（长期挂着）

1. **M2 实机两剧本**（docs/40 §3/§4 + §0 清单）——当前最高优先。
2. Chrome 实机装扩展采集（FEAT-01 遗留，与 M2 §3 同一件事）。
3. 企业目标主机跑 DEP-04 装置（README runbook：持久化+重启存活+
   紧急恢复演练+IPv6 补证）→ Gate R1 生产侧证据。
