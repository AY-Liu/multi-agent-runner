# multi-agent-runner

[![English](https://img.shields.io/badge/lang-English-blue.svg)](README.md)
[![中文](https://img.shields.io/badge/lang-中文-red.svg)](README.zh-CN.md)

multi-agent-runner 是一个轻量的多 Agent 调度框架，可以用同一套控制逻辑运行 Codex 或 Claude Code。

这个项目的目标不是做复杂平台，而是提供一个可以直接 clone、直接运行、方便改造的脚本型 agent team harness。它把任务编排、状态管理、重试、输出收集放在共享层，把 Codex 和 Claude 的差异收敛到 `providers/` 目录里。

## 设计原则

- **直接使用 Codex 和 Claude Code。** multi-agent-runner 采用的是 Codex 和 Claude Code 的 non-API、non-SDK CLI 工作流，不需要接 API 或 SDK。对于已经习惯在本地使用 Codex 和 Claude Code 的人来说，可以很自然地迁移到 agent team 工作流。
- **周期性唤醒调度 agent。** 设计借鉴了 OpenClaw 的原则：每隔一段时间唤醒一次负责调度的 leader。leader 会检查 agent 状态、处理已完成或卡住的 worker、启动后续任务，让整个 agent team 可以持续运行，而不是依赖一次很长的阻塞式提示。

## 最简单用法

如果你只是想让一个 agent team 开始干活：

1. 打开 `leader.md`。
2. 在里面写初始任务和调度方法：你要完成什么、希望 leader 创建哪些 subagent、怎样拆任务、怎样验收结果。
3. 运行一个命令：

```bash
./run.sh --provider codex
```

或者：

```bash
./run.sh --provider claude
```

如果想从干净状态开始，先执行一次 reset：

```bash
./run.sh --provider codex --reset
./run.sh --provider codex
```

第一次任务结束后，如果你想继续对话或追加新要求，把后续指令写进 `inbox.md`，再运行 harness。

一句话：`leader.md` 写初始任务和团队调度方法，`inbox.md` 用于任务结束后的继续对话，`run.sh` 启动整个 harness。

## 试试 Demo

最快理解这个项目的方法，是跑一下迷你密室逃脱 demo。它会让 leader 调度三个并行小组：

- `puzzle_group`：设计谜题、答案和提示。
- `story_group`：设计剧情、线索顺序和主持人台词。
- `operations_group`：设计布置、时间安排和兜底规则。

在一个新 clone 的项目里，进入示例目录，把示例任务文件复制到根目录：

```bash
cd examples/mini-escape-room
cp leader.md ../../leader.md
cp inbox.md ../../inbox.md
cd ../..
```

用 Codex 运行：

```bash
./run.sh --provider codex --reset
./run.sh --provider codex --effort low
```

或者用 Claude 运行：

```bash
./run.sh --provider claude --reset
./run.sh --provider claude
```

这就是正常用法：把初始任务和调度方法写到根目录 `leader.md`，把后续输入写到根目录 `inbox.md`，然后运行 `run.sh`。

预期输出：

```text
output/mini_escape_room_demo.md
```

仓库里也保留了一份 Codex 参考输出：`examples/mini-escape-room/codex-output.md`。

## 功能

- 一个 leader agent 按 `leader.md` 拆解任务并调度 subagent。
- subagent 在后台运行，完成后写入统一格式的结果。
- 支持 `codex` 和 `claude` 两种 provider。
- 记录每个 agent 的状态、会话 id、最新输出和历史运行记录。
- 支持在 Codex 和 Claude 之间切换 provider 时做上下文交接。
- 对常见的 provider 临时失败做重试。
- 包含 reset、provider 选择、重试策略、JSONL 转换、session handoff 等单元测试。

## 依赖

- Bash
- Python 3.10 或更高版本
- 至少安装一种 provider CLI：
  - 使用 `--provider codex` 时需要 `codex`
  - 使用 `--provider claude` 时需要 `claude`

你需要提前在本机安装并登录对应 CLI。本项目不管理 API key，也不会要求你把密钥写入仓库。

## 快速开始

克隆项目并进入目录：

```bash
git clone https://github.com/<your-name>/multi-agent-runner.git
cd multi-agent-runner
```

把初始任务和调度方法写进 `leader.md`。例如可以在文件末尾追加：

```markdown
## Initial Task

Analyze this repository and write a short improvement plan to output/report.md.

## Coordination Method

Create a researcher to inspect the repository, a validator to check the findings, and a deliverer to write the final report.
```

使用 Codex：

```bash
./run.sh --provider codex --reset
./run.sh --provider codex
```

使用 Claude Code：

```bash
./run.sh --provider claude --reset
./run.sh --provider claude
```

只唤醒一次 leader，适合调试：

```bash
./run.sh --provider codex --once
./run.sh --provider claude --once
```

停止正在运行的 harness 或 agent，但保留已有状态和输出：

```bash
./stop.sh --provider codex
./stop.sh --provider claude
```

## 工作方式

`leader.md` 同时定义协调者角色、初始任务和调度方法。每次唤醒时，harness 会把下面这些内容组合成 leader prompt：

- `leader.md` 中的 leader 说明、初始任务和调度方法
- `inbox.md` 中的后续对话或追加指令
- `notes.md` 中的可选用户备注
- 当前 agent 状态和输出摘要
- harness 协议和 decision schema

leader 需要把决策写入 `state/decisions/latest.json`。harness 读取这个文件后执行 action：

- `create_role`：写入 `prompts/roles/<agent>/SYSTEM.md`
- `launch`：启动一个新的 subagent 任务
- `resume`：继续已有 subagent 会话
- `wait`：暂不操作，等待下一次唤醒
- `stop`：停止正在运行的 subagent

任务完成后，leader 会标记 done，并把最终结果写到 `output/`。

## Provider 行为

两个 provider 共享同一套磁盘约定：

```text
agents/<name>/status.json
agents/<name>/output.md
agents/<name>/latest.json
agents/<name>/session_id
agents/<name>/session_id.<provider>
agents/<name>/runs/
```

差异说明：

- Codex 支持 action 级别的 effort：`low`、`medium`、`high`。
- Claude 会忽略 effort。
- Codex 可能写入原始 JSONL 传输输出：`latest.jsonl`。
- Claude 会直接写入统一 JSON 输出。

## 命令

```bash
./run.sh [--provider codex|claude] [--once|--reset|--harness] [--effort low|medium|high]
./stop.sh [--provider codex|claude]
```

常用环境变量：

```bash
MULTI_AGENT_PROVIDER=codex                 # 默认 provider
MULTI_AGENT_CLAUDE_PRIMARY_MODEL=opus      # Claude 主模型标签
MULTI_AGENT_CLAUDE_FALLBACK_MODEL=sonnet   # Claude fallback 模型标签
MULTI_AGENT_CLAUDE_FALLBACK_AFTER=1        # 多少次可重试失败后切换 fallback
CODEX_EXTRA_ARGS="..."                     # 传给 codex 的额外参数
```

旧的 `CLAW_*` 环境变量仍然兼容。

## 项目结构

```text
multi-agent-runner/
  examples/
    mini-escape-room/      # 并行小组工作流 demo
  leader.md                 # leader/coordinator 提示词、初始任务和调度方法
  inbox.md                  # 任务结束后的继续对话输入
  notes.md                  # 每次 leader 唤醒时附带的用户备注
  run.sh                    # 入口脚本
  stop.sh                   # 停止运行中的 harness/agents
  providers/
    claude/provider.sh      # Claude Code provider adapter
    codex/provider.sh       # Codex provider adapter
  scripts/
    harness.sh              # 轮询主循环
    wake_leader.sh          # 构造 leader prompt 并运行 leader
    execute_decisions.sh    # 执行 leader decision
    launch_subagent.sh      # 启动后台 subagent
    lib.sh                  # 共享函数
  prompts/
    templates/              # 可选角色模板
    roles/                  # 运行时生成，默认不进 git
  tests/                    # Python 单元测试
```

`agents/`、`logs/`、`output/`、`state/`、`tmp/` 都属于运行时目录，可能包含会话 id、模型输出、本地路径或任务相关隐私信息，因此默认会被 `.gitignore` 忽略。

## 测试

运行 Python 单元测试：

```bash
python3 -m unittest discover -s tests -p 'test_*.py'
```

检查 shell 语法：

```bash
bash -n run.sh stop.sh scripts/*.sh providers/*/provider.sh
```

## 安全提示

provider adapter 使用了较宽松的 CLI 参数，让 agent 可以在没有交互确认的情况下执行：

- Codex：`--dangerously-bypass-approvals-and-sandbox`
- Claude：`--dangerously-skip-permissions`

请只在你愿意让本地 agent 进程读写文件的工作区里运行本项目。在敏感仓库中使用前，建议先审查 `leader.md` 和运行中生成的 role prompt。

不要提交运行产物、session 文件、日志或 provider 输出。仓库内的 `.gitignore` 已经默认排除了这些内容。

## 贡献

欢迎 issue 和 pull request。新增 provider 时，请把 provider 相关逻辑放在 `providers/<name>/provider.sh`，并保持 README 中描述的共享磁盘约定不变。

## 许可证

MIT
