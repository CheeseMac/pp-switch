# pp switch

![pp switch cover](assets/pp-switch-github-cover.png)

> **Discover APIs. Switch Profiles. Protect Secrets. Empower Agents.**
>
> 通用 API 发现、连接切换、凭证保护与 Agent 安全能力平台。

**项目状态：开发态 Alpha（个人试用可上手）—— Gate R1 企业生产门禁进行中（2026-10-19）**  
**本仓库启动文档版本：v0.1.0，2026-10-13**  
**品牌名称：`pp switch`；仓库 / 包名称：`pp-switch`。**

## 当前状态

- **定位**：开发态 Alpha——个人开发者可在本机完整使用（发现 → 发布 →
  切换 → Agent 调用 → 撤权）；企业生产部署未放行（Gate R1 未关闭）。
- **已交付并验收**：API 发现（HAR/OpenAPI/浏览器采集）、发布向导、
  连接与档案一键切换、OS Keyring 凭证（个人 + POSIX 共享隔离）、
  只读 PostgreSQL 发现与固定参数化只读工具、Agent MCP 调用链、
  三层出口隔离 + 宿主机防火墙实测装置。
- **明确不支持**：Windows 共享 Keyring（启动即安全拒绝）；团队/生产
  敏感数据接入（等 Gate R1）。
- **Gate R1 剩余**：OIDC 身份（ID-07）、多实例与恢复演练（DATA-08）、
  生产 SecretProvider、目标部署主机实机证据（含 IPv6 补证）。
- 完整逐轮实现/加固记录与全部工程文档索引见
  **[docs/INDEX.md](docs/INDEX.md)**。

**demo 模式默认关闭**；**安全边界声明**：本仓库实现的是开发态安全
闭环（synthetic 数据 + mock 凭证 + fail-closed 默认值），不构成生产
安全认证。威胁模型见 [docs/05](docs/05-SECURITY.md) 与
[docs/18](docs/18-SECRETLESS-DEVELOPMENT.md)。

## 快速开始（本地演示）

```bash
# 1. 安装依赖（Python 3.12+ / Node 20+）
uv sync --all-packages && pnpm install

# 1.5 一键安装自检（全新库→迁移→真实服务→完整首用户旅程，仅回环流量）
#     预期末行 INSTALL VERIFIED —— 失败先修环境，不要跳过
uv run python scripts/verify-install.py

# 2. 启动全部服务（control 8911 / executor 8912 / mock CRM 8913 / console 5173）
uv run python scripts/dev-up.py --ui

# 3. 另开终端：初始化演示数据（ principals / service / connections / profiles ）
uv run python scripts/seed-demo.py

# 4. 打开 http://localhost:5173 —— 选择 Alice 登录，然后：
#    Discovery 导入 tests/fixtures/synthetic-har/crm.har.json
#    -> Capabilities 创建 crm.get_customer（Alice 为创建人）
#    -> 退出并以 Carol 登录完成 Review -> Verify -> Publish（审核≠创建人）
#    -> 回到 Alice：Profiles 一键切换 CRM Demo A/B
#    -> Invocations 调用并观察数据集随档案切换
```

测试：`uv run pytest`（370+ 用例：三服务真实 E2E、攻击组合矩阵 SEC-021…053、真实 PostgreSQL 层与宿主防火墙矩阵）+ `pnpm test`（浏览器扩展 31 项 vitest）；检查：`uv run ruff check . && uv run mypy packages apps`。

## 解决什么问题

人在日常工作中使用许多网页、内部系统和 API，但这些系统的接口通常缺少统一发现、统一目录和统一授权机制。Agent 既不知道有哪些能力，也不能安全地直接持有人的密钥。

`pp switch` 希望形成以下闭环：

**授权发现 → 本地脱敏 → 接口归集 → 契约验证 → 能力发布 → 选择连接档案 → 服务端授权执行 → 安全返回 Agent**

## 核心能力

1. **Discover**：导入 OpenAPI、HAR、Postman；从经用户授权的网页网络流量中识别候选 API；发现数据库 schema。
2. **Catalog**：将重复 API 合并为版本化的 `Service → Operation → Capability` 目录，支持个人/团队/企业共享。
3. **Switch**：类似“点击切换配置档案”的桌面工具，一个点击就切换当前工作区、目标服务使用的**连接配置档案**（账号授权 + 已审核端点），但绝不向模型暴露凭证。
4. **Secure**：凭证存储在受信任的本地/服务端；用户和 Agent 双重授权；敏感操作审批；日志脱敏和网络出口约束。**Secretless Development**：源代码只引用能力别名，应用通过 pp switch Broker/Executor 调用真实 API，避免把供应商密钥放在 AI Coding Agent 可读取的 `.env`。
5. **Expose**：把获批 Capability 通过受控 HTTP API 和 MCP 暴露给 Agent；未来兼容更多 Agent 工具协议。
6. **Extend**：新系统优先提供 OpenAPI + 标准身份协议 + 可选 `x-pp-switch` 扩展，实现低成本接入。

## 一键切换的准确含义

- 用户在 UI 中选择 **Workspace / Service / Profile**，例如 `CRM → 我的工作账号` 或 `CRM → 测试账号`。
- 后台只修改经过权限验证的**活动配置绑定**；不会把 Cookie、API Key 或明文密码复制进聊天上下文。
- 一次工具执行开始时固定其使用的档案快照。切换影响**后续**调用，不会改变已在运行的任务。
- 这里的 Profile 是 `endpoint + connection + policy scope`，不是绕过网页登录、替其他人登录或修改浏览器 Cookie 的工具。

## 明确的非目标（v0.1）

- 不做 GUI / RPA / 桌面软件操作。
- 不静默监听用户访问的所有网站，不窃取浏览器会话。
- 不保证发现的私有 HTTP 接口都可长期、合法地独立调用。
- 不给 Agent 提供 `read_secret`、`execute_any_sql`、`call_any_url`、`run_shell`。
- 不开发新的加密算法，不替代 OAuth/OIDC、OpenBao 或成熟 KMS。

## 文档导航

**上手与试用**

| 内容 | 文件 |
|---|---|
| 试用日一页清单 + 实机验收剧本（Chrome / Claude·Cursor） | [40-ALPHA-QUICKSTART](docs/40-ALPHA-QUICKSTART.md) |
| 推荐的第一个演示 | 见下方 §推荐的第一个演示 |

**核心规范**

| 内容 | 文件 |
|---|---|
| 先从哪里开始编码 | [00-START-HERE](docs/00-START-HERE.md) |
| 密钥、权限、威胁模型与安全规则 | [05-SECURITY](docs/05-SECURITY.md) |
| AI 编码助手与 `.env` 密钥隔离（核心） | [18-SECRETLESS-DEVELOPMENT](docs/18-SECRETLESS-DEVELOPMENT.md) |
| 架构、能力契约、API 规格、数据库、部署 | [02](docs/02-ARCHITECTURE.md) / [04](docs/04-CAPABILITY-CONTRACT.md) / [07](docs/07-API-SPEC.md) / [06](docs/06-DATABASE.md) / [10](docs/10-DEPLOYMENT.md) |
| 交接文档（最新状态/踩坑/待办） | [45-HANDOVER-M2-TRIAL](docs/45-HANDOVER-M2-TRIAL.md) |

**工程过程记录**（评审回应、功能交付记录、设计提案、Gate R1 进度、
完整蓝图 00–20 等 40+ 份）：全部收录于
**[docs/INDEX.md](docs/INDEX.md)**——实现状态全记录也在该页。

## 技术基线（提案）

- **Backend**：Python 3.12+、FastAPI、Pydantic v2、SQLAlchemy 2、Alembic、httpx。
- **Web UI**：TypeScript、React、Vite。
- **Discovery browser extension**：TypeScript、Chrome Manifest V3；**已交付 FEAT-01**（docs/32）——chrome.debugger 授权采集 Fetch/XHR，零值样本脱敏（值不出浏览器），一次性配对码换取受限 collector token，上传仅生成草稿。
- **Storage**：SQLite 用于单机开发和 demo；PostgreSQL 为团队/企业正式部署基线。
- **Secrets**：可插拔 `SecretProvider`；单机 OS Keyring / 企业 OpenBao 或托管 KMS。控制平面不能获取明文。
- **Agent**：官方 MCP Python SDK（v2 系列）实现 MCP Adapter，HTTP 统一调用保持为内部稳定契约。
- **Optional**：Redis/NATS/OPA 仅在具体规模和治理需求出现后引入。

以上为**计划依赖**，不是已经安装或实现的功能；首次落地应锁定经过 CI 验证的具体版本。

## 安全的初始化配置样例

仓库内附带 [`.env.example`](.env.example)、[`pp-switch.example.yaml`](pp-switch.example.yaml) 和 [`.gitignore`](.gitignore)。这些**只是非秘密配置示例**；`.gitignore` 只能降低误提交风险，不能阻止拥有文件系统权限的 AI 编码助手读取文件。因此真正的生产 Key 仍必须留在独立 Broker/Executor 的 SecretProvider 中。

## 给 AI 编码助手的入口

使用根目录 [`AGENTS.md`](AGENTS.md) 作为开发规则入口。具体编码分工看 [19-FIRST-CODING-TASKS](docs/19-FIRST-CODING-TASKS.md)；真实密钥迁移和隔离策略看 [18-SECRETLESS-DEVELOPMENT](docs/18-SECRETLESS-DEVELOPMENT.md)。AI 编码环境只使用 mock Profile，不拥有生产 Broker 身份。

## 推荐的第一个演示

使用一个不含真实客户数据的模拟 CRM：

1. 在 UI 中导入两条脱敏的 HAR API 观察记录；
2. 识别出 `GET /api/customers/{customer_id}`，生成候选操作；
3. 审核发布 `crm.get_customer`；
4. 创建两个不同的模拟连接档案；
5. 点击切换活动档案；
6. Agent 通过 MCP 调用 `crm.get_customer`，Executor 使用所选档案访问 mock backend；
7. 执行日志记录 `profile_id` 等非秘密标识，但模型输出无凭证；
8. 换成无权限的 Agent 时必须得到拒绝。

## 文档承诺与限制

`docs/` 交付的是完整开发蓝图与规范；本仓库已按蓝图实现上述"当前实现状态"清单中的第一竖切。示例 SQL / JSON / YAML 中尚未落地的部分（浏览器采集、企业特性）仍需配套代码、迁移和测试之后才能投产。安全边界需要独立测试验证，不能仅凭文档宣称"绝对不会泄漏"。

欢迎贡献，但不得上传真实凭证、真实用户 HAR、客户数据或未获授权的第三方私有接口样本。

## License

Apache-2.0（见 [LICENSE](LICENSE)）。依赖均为宽松许可证（MIT/BSD/Apache）：FastAPI、Pydantic、SQLAlchemy、Alembic、httpx、jsonschema、mcp、React、Vite。
