# MoonSplit

## 研究背景

MoonSplit 处理机器学习实验中的数据泄漏风险：说话人、来源文档、患者等关联键，近重复文本，或同一来源的重叠片段被随机分到训练与评测分区时，都可能让模型借共享上下文取得虚高分数。

项目提供声明式规则分组、确定性划分和独立审计，不做模型训练或调度。v0.3 的文本规则只判断字符片段重叠，区间规则只判断同来源的时间/位置覆盖；它不把这些能力扩展为语义改写、音视频相似或“完全无泄漏”的承诺。

## 基本假设

- v1 输入是唯一 `id`、可选 `label` 和 `keys`；v2 在此基础上增加可选 `text` 和命名 `intervals`。
- 用户准确声明关联规则和（时间模式下）全局时间坐标。来源内字符位置不能被当作全局时间比较。
- 关联规则取 OR 再做传递闭包：同 key 名/值、文本 Jaccard 命中、或同来源区间重叠都会把记录连成同一组件。
- 组件是泄漏审计的最小单位，不能被拆开。
- 审计结论只覆盖已声明规则，不等于“数据完全没有泄漏”。

## 分析目标

1. 以 `exact_key`、`text_jaccard` 和 `interval_overlap` 建立连通组件，并保留解释用森林见证。
2. 按权重进行确定性分配，在贪心初始化后做至多十轮局部组件移动。
3. 对普通划分从原始记录、规则和 assignment 重建约束；不信任计划统计。
4. 对前向验证为每折每条记录给出唯一角色与排除原因，保证活动训练和验证组件不交叉。
5. 在 wasm-gc 与 JS 目标验证字节一致性。

## 工作流程

1. 读取 JSON/JSONL 与 schema v1/v2 配置，先执行同 CLI 的字段和数值校验。
2. 按规则 ID、记录 ID 规范排序，用按大小合并与迭代路径压缩的并查集建立组件。
3. 文本使用规范化 Unicode q-gram 集合、完整前缀候选和整数交叉乘法；默认 `q=3`、`8000bp`。
4. 区间在同来源内按起点扫描，维护最大终点并输出连接性见证；区间是半开 `[start,end)`，端点相接不重叠。
5. 普通划分使用任意精度整数平方误差；局部移动不拆组件、不清空源分区且只接受严格改善。
6. 时间模式依次判定完整验证窗口、组件冲突、历史训练、gap、future 和 boundary overlap；每折训练和验证均非空。
7. 输出契约：v1 holdout/K-fold 为 5/6 文件，v2 grouped 为 7/8 文件，time-forward 为 8 文件；详见 `docs/output.md`。

## 代码结构

- `src/record`：记录、分配清单和输入错误。
- `src/spec`：v1 与 v2 配置、规则和时间窗口。
- `src/group`：v1 关联分组和并查集。
- `src/rules`：v2 三类泄漏规则、组件与见证森林。
- `src/plan`：v1 分配、v2 局部优化与 K 折清单。
- `src/temporal`：独立的前向验证角色规划和审计。
- `src/audit`、`src/export`：独立审计器及稳定 JSON/JSONL/Markdown 导出。
- `cmd/moonsplit`：真实文件 CLI。

## 运行流程

```powershell
./run_check.ps1
./run_acceptance.ps1
./run_demo.ps1
```

```bash
./run_check.sh
./run_acceptance.sh
./run_demo.sh
./run_bench.sh
```

## 设计决策

- v1 保持 `group-greedy-v1` 与既有 API。v2 使用 `group-local-v2`：先贪心、后至多十轮确定性局部移动，最终目标不差于贪心，但不宣称全局最优。
- 文本规则规范化 CRLF、ASCII 大小写和连续空白；短于 q 的非空文本作为单一片段；缺失或规范化后为空在启用规则时失败。密集数据允许退化为二次比较，不截断。
- 时间模式的 `excluded` 不是活动分区；保留验证样本并排除其关联训练样本是预期行为。
- 输出目录不允许覆盖，父目录必须已存在；CLI 用文件系统错误返回固定退出码，而不是递归创建目录。
- 当前依赖 `moonbitlang/x@0.4.46`。计划中的 `x@0.5.1` 因本机 registry 连接失败暂未采用；升级后必须重跑 wasm-gc 与 JS 双目标检查。
- `ratio_tolerance_bp` 使用无舍入交叉乘法进行比例偏差判断；超过阈值时只追加确定性 warning，不使计划失败，等于阈值不告警。
- `seed`、`k` 和 `ratio_tolerance_bp` 必须是非负整数；分区权重必须是正整数且保持兼容的 `Int` 单项范围。权重总和、评分、比例和摘要从累加起使用 `BigInt`，避免总和先在 `Int` 溢出；关联桶使用 `(key_name, key_value)` 元组，避免字符串分隔符歧义。
- CLI 提供 `--version` / `version`、`normalize-spec`、`validate`、`audit --report json` 与 `bench --mode exact|interval|text`；版本号与 `moon.mod` 保持一致。
- 检查、构建和测试（含 JS 目标）统一使用 `--deny-warn`，任何新增警告都会导致检查失败；`*_test.mbt` 是黑盒测试，`moonbitlang/core/test` 需通过 `import { ... } for "test"` 导入。
- v0.3.0 的 tag、远端 CI、Mooncakes manifest、干净目录安装与最终验收包必须形成同一条可追踪发布证据链；当前证据状态以 `docs/acceptance.md` 为准。官方验收结论只能由赛事方作出。

## 验收标准

- 文本：中英文、短文本、阈值相等与传递链都与固定预期连接关系一致。
- 区间：链、包含、相切和不同来源行为符合半开区间定义；扫描见证保持朴素重叠图的连接性。
- 时间：角色优先级、组件冲突排除、gap/边界/future 与空活动分区失败均有测试。
- 新规则审计：故意跨区的文本/区间泄漏和 temporal 组件冲突均由 CLI audit 返回 3。
- 优化：结果不劣于贪心；固定四组件用例从 76 改善为 52，独立穷举最优为 52。
- 规模：exact/interval 各 100000 条，text 为 1000/5000/10000 条；候选数、比较数与耗时保存在每次新的 `artifacts/acceptance_*`。文本密集候选在资源上仍可能退化为二次；证据计数达到可移植 `Int` 上限前以 `text_count_overflow` 显式失败，绝不静默回绕或截断。
- 相同输入、记录逆序、规则换序以及 wasm-gc/JS 产品输出字节一致；v1 回归仍通过。
- CLI 退出码固定为 0/2/3/4，`--version` 和 `version` 输出 `MoonSplit 0.3.0`。
