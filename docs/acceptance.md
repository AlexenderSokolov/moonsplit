# 验收记录

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
- `ratio_tolerance_bp` 是 v0.1.0 的元数据，不参与计划或审计的硬校验。
- 独立 review 提出的整数截断、rooted 路径父目录、NUL 关联键和父目录错误信息问题已修复并回归。

## 边界

- 审计只证明声明的元数据隔离规则，不证明“完全没有泄漏”。
- 不包含时间序列划分、媒体相似度检测、自动训练或调度。
