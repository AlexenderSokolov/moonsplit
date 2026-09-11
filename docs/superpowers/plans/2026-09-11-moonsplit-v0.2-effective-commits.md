# MoonSplit v0.2 有效提交链实施计划

## 目标与边界

以基线 `a4fb8d4` 为参照，在 `codex/moonsplit-v0.2` 分支形成至少 10 个独立、可测试、可审阅的实质增量提交，再完成独立的 v0.2.0 发布准备与验收证据记录。已有提交数量不作为本轮完成依据；不使用空提交、历史重写、时间戳伪造或机械拆分。

保留 JSON/JSONL 输入、数组与并查集分组、wasm-gc/JS 双目标和退出码 `0/2/3/4`。不引入 CSV、数据库、媒体相似度检测、训练器或调度器。旧四个核心输出文件的字段保持不变；新增文件必须被旧消费者忽略。

## 主线提交

每项遵循：先写失败测试，实施最小改动，运行默认与 JS 目标测试，`moon info` 同步 `.mbti`，执行格式和差异检查后独立提交。

1. `fix: tighten assignment input diagnostics`
   - 空 assignment `id` / `partition` 分别报告 `empty_assignment_id` / `empty_assignment_partition`，保留 JSONL 行号；重复 assignment 继续由独立 audit 返回退出码 3。
2. `feat: add canonical split spec serialization`
   - 新增 `SplitSpec::to_json()` 与 `normalize-spec --spec`；固定字段顺序，展开默认值，isolation keys 字典序，holdout 保留分区声明顺序，K-fold 仅输出 `k`。
3. `feat: expose component diagnostics`
   - 新增 `Component::size()`、`Components::total_records()`、`Components::largest()`；并列最大时选择字典序最小 ID。
4. `feat: add deterministic partition summaries`
   - 新增 `PartitionSummary` 和 `SplitPlan::summaries()`；输出 record count、target/actual/deviation bps，半入取整，按 spec 顺序返回；不改变 `SplitPlan::new` 签名。
5. `feat: add label-aware summary artifact`
   - summary 增加标签计数与未标注计数，新增固定 schema 的 `summary.json`；holdout 输出 5 个文件，report 增加比例和标签统计。
6. `feat: enable non-fatal ratio tolerance warnings`
   - 用无舍入交叉乘法和严格 `>` 判断 `ratio_tolerance_bp`，warning 排在组件 warning 后并按 partition 声明顺序输出；不使计划失败。
7. `feat: add stable machine-readable audit reports`
   - 修复 `partition_counts()` 副本隔离；新增稳定 `audit_report_json()` 和 `audit --report text|json`，语义 audit 失败仍为 3，读取/解析失败为 2。
8. `feat: export kfold membership manifest`
   - 新增 `folds_jsonl()`；按 record ID 排序、无尾随换行；K-fold 输出 6 个文件，holdout 不生成 manifest。
9. `feat: add no-write validation preflight`
   - 新增 `validate --data ... --spec ... [--format ...]`，走完整计划路径但不创建输出目录，输出固定校验摘要和 warning。
10. `test: exercise the complete acceptance matrix`
    - 新增多键传递闭包、标签、K-fold 和非法输入 fixtures；双平台脚本检查内容、行为、文件数、字节一致性、退出码、无写入校验和 shell 格式检查；CI 增加显式 `moon fmt --check`。

## 发布闭环

11. `chore: prepare moonsplit 0.2.0 release`
    - 更新 `moon.mod`、CLI 版本、README、API/output 文档、`PROJECT.md` 和 `CHANGELOG.md`；同步 `.mbti`。
12. `docs: record moonsplit 0.2.0 acceptance evidence`
    - 记录实际 commit range、测试、双目标、`run_check`、benchmark、build 和接口无漂移证据。未获得额外明确授权前，不执行 tag、远端 push、GitLink 同步或 `moon publish`。

## 总验收

```bash
moon fmt --check
moon info
git diff --exit-code -- '*.mbti'
moon check --deny-warn
moon build --deny-warn
moon test --deny-warn
moon test --target js --deny-warn
bash run_check.sh
bash run_bench.sh
git diff --check
git rev-list --count a4fb8d4..HEAD
```

还要确认 nested `moonsplit` 干净，parent repository 不误收 `moonsplit/`、`moontrack/`、`_build/`、`.mooncakes/` 或 `artifacts/`。
