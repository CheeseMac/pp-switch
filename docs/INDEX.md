# 工程文档总索引与实现状态全记录

> 本页是 `docs/` 全部工程文档的唯一完整索引，以及逐轮实现/加固的
> 详细状态记录。README 首页只保留概览——找任何一份工程文档或任何
> 一条加固明细，以本页为准。

## 1. 文档导航（完整）

### 蓝图与规范（00–20）

| 想了解的内容 | 文件 |
|---|---|
| 先从哪里开始编码 | [00-START-HERE](00-START-HERE.md) |
| 产品理念、用户角色、需求与范围 | [01-PRODUCT-VISION-PRD](01-PRODUCT-VISION-PRD.md) |
| 核心架构、信任边界、部署形态 | [02-ARCHITECTURE](02-ARCHITECTURE.md) |
| 网页 API 自动发现、HAR / 数据库处理 | [03-API-DISCOVERY](03-API-DISCOVERY.md) |
| 能力模型、契约格式、状态机 | [04-CAPABILITY-CONTRACT](04-CAPABILITY-CONTRACT.md) |
| 密钥、权限、威胁模型与安全规则 | [05-SECURITY](05-SECURITY.md) |
| 数据库 ERD、SQL 结构与多租户规则 | [06-DATABASE](06-DATABASE.md) |
| REST / MCP 接口与错误码 | [07-API-SPEC](07-API-SPEC.md) |
| Monorepo 目录结构与模块职责 | [08-REPOSITORY-STRUCTURE](08-REPOSITORY-STRUCTURE.md) |
| 阶段任务、依赖、开发顺序与验收 | [09-IMPLEMENTATION-PLAN](09-IMPLEMENTATION-PLAN.md) |
| 本地、内网和服务器部署 | [10-DEPLOYMENT](10-DEPLOYMENT.md) |
| 测试矩阵与可验证安全目标 | [11-TEST-PLAN](11-TEST-PLAN.md) |
| UI 交互、一键切换与接入向导 | [12-UX-FLOWS](12-UX-FLOWS.md) |
| 技术决策、待确认事项、权衡 | [13-DECISIONS](13-DECISIONS.md) |
| 开源协作与企业采纳 | [14-OPEN-SOURCE](14-OPEN-SOURCE.md) |
| 一手资料与相关开源项目 | [15-REFERENCES](15-REFERENCES.md) |
| 给开发 Agent 的执行规则 | [16-AGENT-DEVELOPMENT-RULES](16-AGENT-DEVELOPMENT-RULES.md) |
| 故障与操作手册 | [17-OPERATIONS-RUNBOOK](17-OPERATIONS-RUNBOOK.md) |
| AI 编码助手与 `.env` 密钥隔离（核心） | [18-SECRETLESS-DEVELOPMENT](18-SECRETLESS-DEVELOPMENT.md) |
| 首批可直接交给编码 Agent 的任务 | [19-FIRST-CODING-TASKS](19-FIRST-CODING-TASKS.md) |

### 评审与生产就绪（20–31）

| 内容 | 文件 |
|---|---|
| v0.1.0 首竖切实现审核报告（送审） | [20-IMPLEMENTATION-REVIEW](20-IMPLEMENTATION-REVIEW.md) |
| 技术评审回复与安全加固记录（v0.1.1） | [21-REVIEW-RESPONSE](21-REVIEW-RESPONSE.md) |
| 第二轮复核回复与 v0.1.2 加固记录 | [22-REVIEW-RESPONSE-2](22-REVIEW-RESPONSE-2.md) |
| 第三轮复审回复与 v0.1.3 加固记录 | [23-REVIEW-RESPONSE-3](23-REVIEW-RESPONSE-3.md) |
| 第四轮复审回复与撤销不变量补丁 | [24-REVIEW-RESPONSE-4](24-REVIEW-RESPONSE-4.md) |
| 第五轮复审回复与 PR-DATA-12 记录 | [25-REVIEW-RESPONSE-5](25-REVIEW-RESPONSE-5.md) |
| 第六轮复审回复与 PR-NET-13 记录 | [26-REVIEW-RESPONSE-6](26-REVIEW-RESPONSE-6.md) |
| 第七轮复审回复与 PR-DEP-14 记录 | [27-REVIEW-RESPONSE-7](27-REVIEW-RESPONSE-7.md) |
| 部署与出口强制控制 | [28-DEPLOYMENT-AND-EGRESS](28-DEPLOYMENT-AND-EGRESS.md) |
| 第八轮复审回复与 PR-QA-06 记录 | [29-REVIEW-RESPONSE-8](29-REVIEW-RESPONSE-8.md) |
| 生产就绪 Gate R1 进度 | [30-GATE-R1-PROGRESS](30-GATE-R1-PROGRESS.md) |
| 交接文档（架构地图/踩坑/红线/日常操作） | [31-HANDOVER](31-HANDOVER.md) |

### 功能冲刺交付记录（32–40）

| 内容 | 文件 |
|---|---|
| FEAT-01 浏览器 API Collector 交付记录 | [32-FEAT-01-COLLECTOR](32-FEAT-01-COLLECTOR.md) |
| FEAT-02 发布向导交付记录 | [33-FEAT-02-WIZARD](33-FEAT-02-WIZARD.md) |
| FEAT-05A Agent 一键接入交付记录 | [34-FEAT-05A-AGENT-ACCESS](34-FEAT-05A-AGENT-ACCESS.md) |
| FEAT-03 本地 Keyring 交付记录 | [35-FEAT-03-KEYRING](35-FEAT-03-KEYRING.md) |
| 评审交接包入库（含 FEAT-03 验收剧本） | [36-REVIEW-HANDOFF](36-REVIEW-HANDOFF-2026-10-15.md) |
| 评审回应：连接所有权 + Agent 组合验收 | [37-REVIEW-RESPONSE](37-REVIEW-RESPONSE-2026-10-16.md) |
| 交接文档（FEAT-04 会话入口） | [38-HANDOVER-FEAT04](38-HANDOVER-FEAT04.md) |
| FEAT-04 只读 PostgreSQL 发现交付记录 | [39-FEAT04-DB-DISCOVERY](39-FEAT04-DB-DISCOVERY.md) |
| Alpha 快速上手与实机验收剧本（含试用日清单） | [40-ALPHA-QUICKSTART](40-ALPHA-QUICKSTART.md) |

### 共享 Keyring 隔离与宿主防火墙（41–45）

| 内容 | 文件 |
|---|---|
| SECRET-06 Keyring 隔离设计（已批复实施，含勘误） | [41-PROPOSAL-SECRET-06-KEYRING-ISOLATION](41-PROPOSAL-SECRET-06-KEYRING-ISOLATION.md) |
| SECRET-06 交付记录 | [42-SECRET-06-DELIVERY](42-SECRET-06-DELIVERY.md) |
| DEP-04 宿主机防火墙设计（已批复实施，含勘误） | [43-PROPOSAL-DEP-04-HOST-FIREWALL](43-PROPOSAL-DEP-04-HOST-FIREWALL.md) |
| DEP-04 交付记录 | [44-DEP-04-HOST-FIREWALL-DELIVERY](44-DEP-04-HOST-FIREWALL-DELIVERY.md) |
| 交接文档（M2 试用/归档会话入口，最新） | [45-HANDOVER-M2-TRIAL](45-HANDOVER-M2-TRIAL.md) |

## 2. 实现状态全记录（诚实清单·完整版）

**已实现并可在本仓库运行：**

- Monorepo（`uv` Python workspace + `pnpm`）：`packages/core|db|discovery-sdk|policy-engine|secret-provider|python-sdk` 与 `apps/control-api|executor|mcp-adapter|demo-mock-crm|web-console`
- 领域契约：Pydantic v2 模型、错误码、能力状态机（draft → reviewed → verified → published，发布版不可变）
- 数据层：SQLAlchemy 2 ORM + Alembic 迁移（SQLite 开发 / PostgreSQL 生产基线），含复合外键租户约束与乐观锁并发切换
- 发现管道：清洗校验的 HAR / OpenAPI 导入、路径模板归一化、指纹去重、JSON Schema 推断；未脱敏上传直接 422 拒绝
- 能力注册与审核发布：review → verify → publish 工作流 + 输出白名单
- 连接与档案：Connection（仅存 `secret_ref`，不存明文）、Profile（同 Service 对齐校验）、一键切换（409 版本冲突保护）
- 受信执行器：HMAC 签名的执行计划 + 防重放 + 二次参数校验 + SSRF 网络策略（默认拒绝私网/元数据地址）+ 响应守卫（白名单投影、密钥形状脱敏、大小限额）
- Secretless 公开 SDK `import ppswitch`：仅 `invoke / list_capabilities / profile_status`，无任何 `get_secret` 面
- MCP 适配器（官方 `mcp` v2 SDK，stdio）：`tools/list` 按发布能力过滤，`tools/call` 走同一调用链
- React 控制台：Services / Discovery / Capabilities / Connections / Profiles（一键切换）/ Invocations / Security 七页
- 安全测试：docs/00 的 10 个验收场景、P0 安全用例（蜜罐不落库、未发布 404、保留参数 422、越权 403、密钥失联 fail-closed、在途快照等）与仓库密钥扫描脚本
- CI：lint / typecheck / 全量测试（双 OS）/ 密钥扫描 / PostgreSQL 矩阵 / Docker 部署验收 / M2 安装自检 / DEP-04 宿主防火墙矩阵（`.github/workflows`）
- 安全加固第一轮（技术评审后）：Connection 所有权三段校验、管理 API 仅限人类且审核≠创建人、审批绑定不可变 Proposal（请求人+版本+档案+参数摘要+15 分钟时效）并原子消费、幂等键绑定主体（冲突 409 而非泄漏）、执行器路径段校验+最终 URL 复检+强制主机白名单+元数据段不可豁免+请求时 DNS 复验+流式限长、响应守卫输出 Schema 递归白名单投影、执行快照脱敏（不存参数/secret_ref/目标地址）、demo 模式默认关闭且生产配置不完整拒绝启动（对应攻击组合测试 SEC-021…030）
- 安全加固第二轮 v0.1.2（复核后）：全路由权限矩阵（Agent 默认仅可见已授予的已发布能力并可调用；member/reviewer/admin 角色）、User→Agent 委托表与按委托人隔离的 Agent Profile 绑定（共享 Agent 互不覆盖，SEC-033）、连接层 IP 钉扎（解析-校验-连接同一地址，DNS 检查后不可被二次解析改道）、响应守卫类型门先行 + 未知对象默认拒绝 + allow_fields 与 Schema 取交集、OpenAPI 导入期 Schema 清洗（example/default 等注解与密钥形状字符串不落库不进工具目录）、grant/connection/delegation scopes 交集授权、幂等回放前重新鉴权、上传分块限额读取、MCP 必填参数前置与工具名冲突双端拒绝、private/team/organization 可见性过滤、YAML 导入（对应回归测试 SEC-031…042）
- 安全加固第三轮 v0.1.3（复审后）：幂等回放绑定委托用户（共享 Agent 不能跨用户复用缓存结果）、Capability required_scopes 显式授权链（空链不满足 scoped 能力）、Agent 目录公共视图（仅 published 版本、无内部 execution/allow_fields、过期 grant 剔除）、签名式 Delegation Context 票据取代参数选身份（ADR-005）、高风险审批与 Endpoint 审批提升至 reviewer 角色、响应守卫拒绝无 items 数组与未解析 $ref、endpoint 默认强制 HTTPS、手动创建 Capability 过导入级元数据清洗（对应回归测试 SEC-043…048 与共享 Agent 综合攻击场景）
- 安全加固第四轮 v0.1.3.1（复审后）：幂等回放前重验完整 scope 链与 connection 存活（授权缩小/撤销后缓存不可再取）、Agent 历史查询强制委托票据并按委托用户过滤（撤销即刻生效）、输出 Schema 根节点 $ref 一律拒绝、委托票据生产强制独立签名密钥（ADR-005 修订/ADR-007）（对应回归测试 SEC-049…051 与撤销不变量四路径）
- 数据生命周期 PR-DATA-12（第五轮批准后）：调用结果存储前数据分级（high/critical 默认 metadata-only）、保留期 TTL（过期读取为空）、Fernet 静态加密（生产强制密钥）、启动自动清理 + admin 清理 API；历史读取按记录重校验完整授权链（缩小未撤销同样不可读，SEC-052）；委托授权代际 generation 使撤销→重授权后的旧票据立即失效（SEC-053）；allOf/oneOf/anyOf 组合 schema 在受限解析器落地前一律 fail-closed（ADR-008：结果读取单一出口）
- 生产就绪与受限解析（第六轮）：升级时清空存量明文结果（迁移 f3a62c8e1b47 + 运行时无期限明文兜底清扫）、结果清理按 Workspace 隔离（全局清扫仅限内部启动任务）且启动失败告警、Fernet 密钥轮换读写窗口（MultiFernet）+ 租户内重加密 API + 解密失败日志分类（DATA-15..17）；OpenAPI 本地 $ref 有界解析（外部引用不解引用、循环/深度上限、失败进人工审核）与响应守卫 allOf 纯对象分支受限合并（PR-NET-13，ADR-009）
- 出口强制与部署（第七轮 PR-DEP-14）：allOf 重复属性一律拒绝、解析器四类资源预算（结构深度/节点数/数组长度/内联体积）与 $ref 兄弟键拒绝（NET-13-F1/F2）；IPv6 包装地址（IPv4-mapped/NAT64）按内嵌 IPv4 判定实现元数据段硬拒；三层出口隔离（应用层策略 + Compose executor 无出口网络 + 主机防火墙样例）、密钥轮换分页重加密与多实例运维规程、升级不可逆与备份加密说明（deploy/ + docs/28）
- 受控出口网关与验收矩阵（第八轮 PR-QA-06）：egress-gateway（CONNECT-only 正向代理，独立 allowlist、canonical_ip 归一、元数据段硬拒、端到端 TLS 不解密、全量审计日志）使隔离的 executor 具备真实外部 API 调用能力（DEP-14-F1）；防火墙样例修正至 FORWARD/DOCKER-USER 路径，control 默认仅绑定回环、mock-crm 移入 demo profile；测试数据库参数化（PP_SWITCH_TEST_DB_URL），CI 新增 PostgreSQL 矩阵（QA-PG-01..05）与 Docker 部署验收（QA-DEP-01..05，deploy/verify-deployment.sh）
- 生产就绪 Gate R1（综合审计后）：永久拒绝策略集覆盖非 link-local 云元数据端点（阿里云 100.100.100.200 / AWS fd00:ec2::254，allowlist 亦不可豁免）、出口端口边界（裸主机名仅 443，非标准端口需显式 host:port）、网关工作负载认证（Proxy-Authorization）与并发/速率/时长配额、control 移出出口网络并加容器加固（read_only/cap_drop/限额）、PostgreSQL 部署模板（deploy/docker-compose.postgres.yml）、部署验收升级为完整 Agent→Executor→Gateway→外部后端→响应守卫全链路 + 网关审计日志断言 + 可达性对照 + 全链合成凭证 canary（docs/30）
- 功能冲刺 FEAT-04 首切片（只读 PostgreSQL 数据库发现，docs/39）：db-target 独立审批类型（reviewer 级、不可自审，与 HTTP endpoint 审批互不可代用）→ executor 以 keyring 只读账号（激活实连并拒 superuser 级）发现 approved schemas 元数据（仅列名+类型，未批 schema 双层不可见）→ FEAT-02 向导 db 变体人工确认参数与字段 → 既有 review/verify/publish → Agent 授权调用固定参数化只读工具：execution 为结构化 spec（无任何 SQL 文本面，语句由 executor psycopg 标识符合成，签名计划也无法夹带），超时/行数/大小三重限额，撤销 target 或连接即刻 403，DB 口令全程只在 keyring 与 executor
- SECRET-06 共享 Keyring 隔离（docs/41/42，`55d2e68` 无保留开发态验收）：机器级名字 claim（双件属主证明：一次性码 + executor 本机 attestation 经 OS 保护本地通道）、全长 HMAC 材质钉扎、代际撤销（墓碑防 ABA）、409 显式轮换状态机；个人模式体验不变；**Windows shared 按批准策略启动即安全拒绝**（R13，ACL 实现另案）
- DEP-04 宿主机防火墙实测装置（docs/43/44，`6b5b362` 矩阵 64 PASS/0 FAIL/1 PENDING）：iptables DOCKER-USER 与 nftables 双后端完整矩阵、FORWARD 真路径（netns+veth 受控目标）+ 规则计数器证据、gateway 静态身份放行（误接 executor 仍拒）、DNAT/SNAT/INPUT 证据分离、强制地址漂移重跑、回滚零残余；CI `AUD-DEP-04 host firewall matrix` job 每次 run 产出宿主级证据；IPv6 待目标主机补证（PENDING≠PASS）

**计划中、尚未实现（请勿当作已有能力）：**

- Windows 共享 Keyring 多用户隔离（当前启动即安全拒绝；需 NTFS ACL 实现 + 跨用户测试）
- 生产 SecretProvider（OpenBao 腿，Gate R1 SECRET-06 生产部分）
- OIDC / JWT audience 生产认证（Gate R1 ID-07）；多实例密钥轮换与备份恢复演练（Gate R1 DATA-08）
- 宿主防火墙的目标主机实机证据与 IPv6 补证（Gate R1 DEP-04 生产侧）
- FEAT-04 多行/列表查询工具、其他数据库引擎、经 egress-gateway 的数据库出口
- PostgreSQL RLS、配额与预算、审批工作台 UI、Contract drift 告警、Edge Connector / mTLS
- SDK 的传输级生产认证（见 `packages/python-sdk` 文档中的安全声明）

**demo 模式默认关闭**：`PP_SWITCH_DEMO_MODE` 仅由 `scripts/dev-up.py` 显式开启；非 demo 下 dev 登录目录/mock 凭证/默认内部 token 均不可用，生产配置不完整时服务拒绝启动。

**安全边界声明：** 本仓库实现的是开发态安全闭环（synthetic 数据 + mock 凭证 + fail-closed 默认值），不构成生产安全认证。威胁模型与限制见 [docs/05](05-SECURITY.md) 与 [docs/18](18-SECRETLESS-DEVELOPMENT.md)。
