# MoonSplit

## 研究背景

MoonSplit 处理机器学习实验中最常见的一类数据泄漏风险：多个记录通过同一说话人、同一来源文档、同一患者或其他关联键连接在一起。若这些记录被随机分散到训练集和测试集，模型就可能通过共享上下文“背答案”，让评测分数虚高。

这个工具只做一件事：根据用户声明的元数据关联键，把样本划分为不跨组的数据集分区，并独立审计这种隔离规则。它不判断原始音频、文本或图像是否相似，也不做训练和调度。

## 基本假设

- 输入是结构化记录，每条记录有唯一 `id`、可选 `label` 和一个 `keys` 对象。
- 用户准确声明哪些 key 代表不可跨分区的关联关系。
- 关联关系是“同 key 名 + 同 key 值”的 OR 关系；多个键之间做传递闭包。
- 组件是泄漏审计的最小单位，不能被拆开。
- 审计结论只覆盖声明的元数据隔离规则，不等于“数据完全没有泄漏”。

## 分析目标

1. 把多关联键样本合并成连通组件，并保留可解释的见证边。
2. 按权重确定性地分配组件，避免组件拆散。
3. 独立重新审计分配结果，不信任计划文件里的统计。
4. 支持等权 K 折划分，并保证每个样本恰好验证一次。
5. 在 wasm-gc 和 JS 目标上保持一致的确定性行为。

## 工作流程

1. 读取 JSON/JSONL 记录和 SplitSpec 配置。
2. 检查重复 ID、缺失 key、非法类型和空数据。
3. 用并查集合并组件，组件 ID 取成员 ID 最小值。
4. 用 `group-greedy-v1` 分配组件；见证边先规范化端点顺序，再按 `(key_name, key_value, left_id, right_id)` 排序。
5. 独立审计跨区隔离、重复分配、遗漏、空分区和非法分区。
6. 输出 `plan.json`、`assignments.jsonl`、`components.jsonl`、`report.md`、`summary.json`；K-fold 额外输出 `folds.jsonl`。

## 代码结构

- `src/record`：记录、分配清单和输入错误。
- `src/spec`：holdout/kfold 配置。
- `src/group`：关联分组和并查集。
- `src/plan`：确定性分配与 K 折取集。
- `src/audit`：独立审计器。
- `src/export`：稳定 JSON/JSONL/Markdown 导出。
- `cmd/moonsplit`：真实文件 CLI。

## 运行流程

```powershell
./run_check.ps1
./run_demo.ps1
```

```bash
./run_check.sh
./run_demo.sh
./run_bench.sh
```

## 设计决策

- 分配算法固定为 `group-greedy-v1`：先保证每个分区非空，再按加权整数目标减少尺寸和可选标签的平方误差；组件不可拆分。
- 输出目录不允许覆盖，父目录必须已存在；CLI 用文件系统错误返回固定退出码，而不是递归创建目录。
- 当前依赖 `moonbitlang/x@0.4.46`。计划中的 `x@0.5.1` 因本机 registry 连接失败暂未采用；升级后必须重跑 wasm-gc 与 JS 双目标检查。
- `ratio_tolerance_bp` 使用无舍入交叉乘法进行比例偏差判断；超过阈值时只追加确定性 warning，不使计划失败，等于阈值不告警。
- `seed`、`k`、分区权重和 `ratio_tolerance_bp` 都必须是非负整数；关联桶使用 `(key_name, key_value)` 元组，避免字符串分隔符歧义。
- CLI 提供 `--version` / `version`，版本号与 `moon.mod` 保持一致；v0.2.0 还提供 `normalize-spec`、`validate` 和 `audit --report json`。
- 检查、构建和测试（含 JS 目标）统一使用 `--deny-warn`，任何新增警告都会导致检查失败；`*_test.mbt` 是黑盒测试，`moonbitlang/core/test` 需通过 `import { ... } for "test"` 导入。
- 发布顺序固定为：更新版本号并提交，打 tag 并推送到 GitHub，确认 CI 通过后再执行 `moon publish`，保证 Mooncakes manifest 的发布时间晚于对应提交。

## 验收标准

- 20 个等大组件按 8:1:1 得到 16/2/2。
- 12 个样本组成大小 9、2、1 的组件时，9/2/1 完整保留并输出大组件警告。
- 五折中每个样本恰好验证一次。
- 100000 条同键记录能完成分组，不生成全样本两两列表。
- 重复运行、逆序输入、键顺序变化后的输出字节一致。
- `seed` 只接受非负整数；见证边端点和顺序在输入顺序变化时保持一致。
- `k`、分区权重和 `ratio_tolerance_bp` 拒绝小数；无盘符 rooted 输出路径也必须验证父目录存在。
- wasm-gc 与 JS 目标的分配清单一致。
- CLI 退出码固定为 0/2/3/4。
- `--version` 和 `version` 输出 `MoonSplit 0.2.0`。
