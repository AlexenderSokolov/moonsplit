# MoonSplit v0.2 已确认设计

## 兼容性

- 保留 JSON/JSONL 输入、数组 + 并查集、wasm-gc/JS 双目标和退出码 `0/2/3/4`。
- `plan.json`、`assignments.jsonl`、`components.jsonl`、`report.md` 的既有字段不删除；输出目录新增 `summary.json`，K-fold 额外新增 `folds.jsonl`。
- 因 report 内容和输出文件数量变化，不承诺旧 Markdown 或整个输出目录字节完全兼容；旧消费者必须忽略未知文件。

## 确定性规则

- canonical spec 固定字段顺序，默认值显式展开；isolation keys 用 UTF-16 code-unit 的真正 lexical order，holdout partitions 保持声明顺序，K-fold 不输出派生 partitions。
- 组件 API 的 `largest()` 按 size 最大优先，并列时按 dictionary/lexical order 取最小组件 ID。
- 分区摘要字段为 `name`、`weight`、`record_count`、`target_bp`、`actual_bp`、`deviation_bp`；bps 使用正整数半入计算，偏差为绝对值，返回数组按 spec 顺序且与内部状态隔离。
- `Some(label)` 始终计入 label map，包括空字符串；`None` 只计入 `unlabeled_count`。label map JSON key 按 lexical order。
- 比例 warning 使用：

  `abs(count * weight_sum - total * weight) * 10000 > tolerance * total * weight_sum`

  等于阈值不告警；warning 在组件 warning 后、按 partition spec 顺序出现。

## 机器可读输出

`summary.json` 固定顶层字段为 `schema_version`、`algorithm`、`records`、`components`、`largest_component`、`partitions`。每个 partition summary 扩展 `label_counts` 与 `unlabeled_count`。

`audit_report_json()` 固定顶层字段为 `schema_version`、`valid`、`records`、`assignments`、`partition_counts`、`issues`；声明分区按 spec 顺序，未知分区按 lexical order 追加，issue 保持 audit 生成顺序，缺少行号输出 `null`。

`folds.jsonl` 每行固定为：

```json
{"id": "<escaped>", "validation_fold": "<fold>"}
```

按 record ID lexical order 输出，不带尾随换行；holdout 调用返回 `not_kfold_plan`。

## 验收设计

- 多键 fixture 必须证明传递闭包，而不是只证明单键分组。
- 标签 fixture 必须覆盖普通 label、空字符串 label 和无 label。
- K-fold fixture 的组件数不少于 `k`，并检查每个样本恰好出现一次。
- `normalize-spec`、summary、fold manifest 和 audit JSON 检查实际内容；wasm-gc 与 JS 对所有输出和 validate 文本做字节比较。
- `validate` 成功不能创建任何输出目录；非法输入保留退出码 2，语义 audit 失败保留退出码 3，输出写入失败保留退出码 4。
