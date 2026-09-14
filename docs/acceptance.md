# 验收记录

## 0.3.0 发布与验收记录 - 2026-09-14

### 状态与证据边界

- 状态：已发布 `v0.3.0`。发布 tag 与本地验收包对应 `33e2e5de201d882f955df89de0e642a106aa8116`；`main` 另外保留发布后的证据文档提交。官方黑客松验收结论仍由主办方作出。
- 公开记录：[PR #1](https://github.com/AlexenderSokolov/moonsplit/pull/1)、[GitHub Release](https://github.com/AlexenderSokolov/moonsplit/releases/tag/v0.3.0)、[main CI 34863052441](https://github.com/AlexenderSokolov/moonsplit/actions/runs/34863052441) 和 [tag CI 34863265525](https://github.com/AlexenderSokolov/moonsplit/actions/runs/34863265525) 均已成功；tag CI 复跑 Bash 端到端验收并上传证据。
- Mooncakes：[manifest](https://mooncakes.io/api-new/v0/manifest/AlexenderSokolov/moonsplit) 显示 `version = latest_version = 0.3.0`、`has_package = true`、`build_status = success`，包 checksum 为 `536347ca22d2748c17d6c307154b0661c7d9466bd4116f425f3958ce9bbecec2`。
- 工具链：本机完整运行使用 `moon 0.1.20260904 (94521db 2026-09-04)`、`moonc v0.10.12+1634b282e (2026-09-07)`；每次完整版本/环境输出写入新的 `artifacts/acceptance_*`。

### 实测命令与结果

- `moon fmt --check`：通过。
- `moon check --deny-warn`：通过。
- `moon test --deny-warn`：81/81 通过。
- `moon test --target js --deny-warn`：81/81 通过。
- `run_check.ps1` 与 `run_check.sh`：均通过。覆盖 v1 5/6 文件回归、v2 grouped 7/8 文件、time-forward 8 文件、v2/time `validate` 预检、规则/时间负例 audit 的退出码、多窗口与零 gap 边界，以及重复运行、记录逆序、规则换序与 wasm-gc/JS 产品字节一致性。
- `run_acceptance.ps1`：通过，生成 `artifacts/acceptance_20260914_232204_043_61144`；其 37 项包内文件哈希复核为零差异。Git Bash `run_acceptance.sh`：通过，生成 `artifacts/acceptance_20260914_232452_980571500_1808`；其 44 项包内文件哈希复核为零差异。二者均记录空工作树、命令清单、输入哈希、工具链/机器元数据、产品与独立 audit 重检、优化穷举和全包 SHA-256 清单。固定四组件优化从 `76` 到 `52`，独立穷举最优为 `52`、差距 `0`；exact 与 interval 分别运行 100000 条，text 分别运行 1000、5000、10000 条，并记录候选数、实际比较数和耗时。可公开下载的摘要见 [release asset](https://github.com/AlexenderSokolov/moonsplit/releases/download/v0.3.0/v0.3.0-acceptance.md)。

### 本期验收覆盖

- 文本：中文、短文本、完全重复、阈值相等、传递链、缺失/空文本与整数阈值边界；候选过滤结果与独立朴素两两 Jaccard 扫描逐对一致。
- 区间：覆盖链、包含、端点相切、不同来源和非法区间；扫描组件与独立朴素相交图的连通关系逐对一致。
- 时间：验证窗口、组件冲突排除、历史/gap/future/boundary 角色、空训练/验证失败及角色清单独立审计。
- 数值与确定性：v1/v2 目标与比例的 `BigInt` 计算、文本证据计数的显式 `text_count_overflow` 保护、按大小并查集、逆序/换序一致性、100000 条规模与双后端产品字节比较。

### 发布闭环与官方提交状态

- 本期功能提交范围为 `df2ca5e..33e2e5d`，包含规则模型、时间验证、优化/审计、验收脚本和文档的语义提交；`v0.3.0` 为固定在该 SHA 的 annotated tag，`main` 保留其后的发布证据文档提交。
- 发布前已核对 registry 中没有 `0.3.0`；`moon publish` 对打包、解压和独立 `moon check` 都通过后返回 `200 OK`。随后 manifest 变为 `latest_version = 0.3.0` 和 `build_status = success`。
- 干净目录使用 `moon add AlexenderSokolov/moonsplit@0.3.0` 解析到该精确版本与 `moonbitlang/x@0.4.46`，导入 `AlexenderSokolov/moonsplit/src/record` 的公开 API 后，`moon tree`、`moon check --deny-warn`、`moon build --deny-warn` 和 `moon run cmd/main` 均成功。另以 `moon add --bin` 和 `moon install` 验证 wrapper 输出 `MoonSplit 0.3.0`；MoonBit 将 binary dependency 标记为 deprecated，故它只是 CLI 发布验收，不作为新的推荐安装方式。
- 已公开提交的材料包括源码、README、示例、测试、CI、发布说明、Mooncakes manifest 和验收摘要。官方入口/回执尚未在本记录中出现，因此当前官方状态是“发布材料已准备，待主办方确认”，而不是“已通过”。

## 历史记录（仅供追溯，不适用于 v0.3.0 当前能力或验收范围）

以下内容保留旧版本的已发生提交、发布和当时的验证上下文。它们不覆盖本节开头的 v0.3.0 发布结论，尤其不能被解读为 v0.3.0 不支持时间前向验证。

## 0.2.0 实现与验收证据 - 2026-09-12

### 实际提交范围

- 实际提交范围：`a4fb8d4..40bc7a5`，共 16 个提交；其中包含 10 个主线功能/测试增量、1 个 worktree 忽略配置提交、1 个 v0.2.0 release preparation 提交、1 个验收记录提交和 3 个针对最新 MoonBit CI 工具链的格式/接口/警告兼容提交。
- 主线提交依次覆盖 assignment 诊断、canonical spec、组件诊断、分区摘要、标签 summary、比例 warning、audit JSON、K-fold manifest、validate preflight 和完整验收矩阵。
- 此前的 `9a3c13c` 已将本地验收记录作为独立文档提交加入；本次更新只补充公开 push 与 CI 证据，不计作功能凑数。

### 已验证

- `moon fmt --check`：通过。
- `moon info` 后 `git diff --exit-code -- '*.mbti'`：通过，无接口漂移。
- `moon check --deny-warn`：通过。
- `moon build --deny-warn`：通过。
- `moon test --deny-warn`：42/42 通过。
- `moon test --target js --deny-warn`：42/42 通过。
- `run_check.ps1`：通过；覆盖 canonical normalize、holdout 5 文件、K-fold 6 文件、summary/folds 内容、audit JSON 成功/失败、validate 无写入、空 assignment 的 2、audit 语义失败的 3 和输出错误的 4。
- `run_check.sh`：通过 Git for Windows login Bash 执行；同样覆盖 wasm-gc/JS 字节一致性、内容断言和 `moon fmt --check`。
- `run_bench.ps1` 与 `run_bench.sh`：均输出 `bench=ok`、`records=100000`、`components=20000`、`assignments=100000`。
- `git diff --check`：通过；nested repository 的 `main` 工作树清洁。
- GitHub Actions `ci` run `34623390996`（提交 `40bc7a5`）：通过 Format、Public interface、Typecheck、Build、MoonBit 测试、JS 测试和端到端检查。

### 已执行的外部动作

- 按本轮授权已直接 push 到 GitHub `main`：`origin/main = 40bc7a5`。

### 尚未执行的外部动作

- 未执行 tag、GitLink 同步、Mooncakes publish 或干净安装验证；本轮授权范围仅为直接 push `main`。

## 0.1.1 - 2026-09-06

- `moon check` 通过，0 个错误。
- `moon fmt --check` 通过。
- `moon test` 和 `moon test --target js` 均 24/24 通过。
- `./run_check.ps1` 通过，并额外验证 `--version` 和 `version` 都输出 `MoonSplit 0.1.1`。
- `./run_bench.ps1` 成功处理 100000 条记录、20000 个组件、100000 条分配。
- 新增 `CHANGELOG.md` 和 `docs/output.md`；`docs/api.md` 补充 K 折 `fold_members`。

## 0.1.1 公开发布闭环 - 2026-09-06

- GitHub 仓库：`https://github.com/AlexenderSokolov/moonsplit`
- 发布标签：`v0.1.1`
- GitHub 提交：`afceb9f`
- GitHub Actions：
  - `main` run `34013988648`：成功。
  - `v0.1.1` run `34013990933` 成功。
  - 覆盖 `moon info`、`moon check`、`moon build`、`moon test`、`moon test --target js` 和 `bash ./run_check.sh`。
- Mooncakes：
  - 包名：`AlexenderSokolov/moonsplit`
  - `latest_version = 0.1.1`
  - `build_status = success`
  - `has_package = true`
  - Manifest 地址：`https://mooncakes.io/api-new/v0/manifest/AlexenderSokolov/moonsplit`
- 干净安装复现：
  - 临时项目通过 `moon.mod` 引入 `AlexenderSokolov/moonsplit@0.1.1`。
  - `moon build` 成功下载并构建该包。
  - `moon test` 成功运行（0 个测试，因为临时项目没有自己的测试入口）。
- 按用户本轮指示，GitLink 发布不做。

## 2026-09-06

- `moon check` 通过，0 个错误。
- `moon fmt --check` 通过。
- `moon test` 和 `moon test --target js` 均 23/23 通过。
- `./run_check.ps1` 通过，覆盖真实 CLI：
  - wasm-gc 和 JS 目标各生成 4 个输出文件，`plan.json`、`assignments.jsonl`、`components.jsonl`、`report.md` 字节一致。
  - 独立 audit 成功返回 0。
  - 非法分配清单返回 3。
  - 缺失 spec 文件返回 2。
  - 已有输出路径返回 4。
  - 缺失父目录返回 4。
  - `中文 路径` 带空格路径可正常写出。
- `moon run cmd/moonsplit -- demo --out examples/demo_20260906_005928` 成功生成 20 条记录、20 个组件、20 条分配和 4 个文件。
- `moon run cmd/moonsplit -- bench --records 100000 --speakers 20000` 成功完成分组、计划和内置审计，输出 100000 条分配。

## 单元口径

- 20 个等大且单成员的组件按 8:1:1 得到 16/2/2。
- 12 个样本组成大小 9、2、1 的组件时，组件完整保留并输出大组件警告。
- 开启类别平衡后，8:1:1 的训练分区得到正负各 8 条。
- 五折中每个样本恰好验证一次，训练集是补集。
- 逆序输入后分配 ID 和分区完全一致。
- 见证边端点和顺序在输入顺序变化后一致；`components.jsonl` 中的边按 `(key_name, key_value, left_id, right_id)` 排序。
- 审计器检查重复分配、未知样本、遗漏、空分区和跨区隔离。
- JSON/JSONL 输入接受 UTF-8 BOM，JSONL 报告行号，JSON 输出转义控制字符。
- `seed` 拒绝负数和小数。
- `k`、分区权重和 `ratio_tolerance_bp` 拒绝小数。
- 无盘符 rooted 输出路径的父目录缺失时返回 4，不自动创建多级目录。
- 键名或键值包含 NUL 不会造成关联桶碰撞。
- `smoke --data <file>` 可读取真实文件并输出字符数。

## 工具链备注

- 当前本机 `moon` 版本为 `0.1.20260703`。
- `moon.mod` 暂时固定在 `moonbitlang/x@0.4.46`：本次尝试升级到 `x@0.5.1` 时，Mooncakes registry 连接失败且本机索引无该版本；待网络可用后应重试并重跑双目标验收。
- `ratio_tolerance_bp` 在 v0.2 中产生非致命 warning；比例阈值比较使用无舍入交叉乘法，等于阈值不告警。
- 独立 review 提出的整数截断、rooted 路径父目录、NUL 关联键和父目录错误信息问题已修复并回归。
- 本机 `moon 0.1.20260703` 不能解析最新 CI 工具链要求的 `pkgtype` 语法；因此当前提交的最新格式、接口、构建和双目标验收以 GitHub Actions run `34623390996` 为准。

## 0.1.1 历史边界（不适用于 v0.3.0）

- 审计只证明声明的元数据隔离规则，不证明“完全没有泄漏”。
- v0.1.1 当时不包含时间序列划分、媒体相似度检测、自动训练或调度。
