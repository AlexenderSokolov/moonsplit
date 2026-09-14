# MoonSplit v0.3.0 项目说明与验收材料

## 现有基础

MoonSplit 是一个 MoonBit 数据集划分与独立审计工具。既有 v1 能够将同说话人、同来源文档、同患者等同名关联键的记录做传递闭包，作为不可拆分组件进行 holdout/K 折划分，并从原始记录和 assignment 清单重新审计。JSON/JSONL 输入、稳定导出、wasm-gc/JS CLI 和 v1 接口均保留兼容。

## 本期新增

本期实现引入 schema v2 和三类泄漏模型：`exact_key`、Unicode 字符 q-gram Jaccard 文本近重复、以及同来源半开区间重叠；新增显式时间窗口的前向验证，逐折输出 `train`、`validation` 和具名 `excluded` 原因；普通划分加入最多十轮确定性组件局部移动优化。自动化验证已实测 81 个 wasm-gc 测试和 81 个 JS 测试通过，PowerShell 与 Bash 验收入口均已生成证据包并复核包内 SHA-256 清单；固定优化例从目标值 76 降至 52，独立穷举最优值为 52。正式发布时将以同一 SHA 的 tag、CI、Mooncakes manifest、干净目录安装与最终验收包形成公开证据链；官方验收结论仍由主办方作出。

## 技术路线

文本规则将 CRLF、ASCII 大小写和连续空白规范化，默认用 3-gram 集合和 `8000bp` 阈值；前缀倒排产生完整候选，再以整数交叉乘法精确判定，阈值相等计为命中。区间规则在同来源内按起点扫描并维护最大终点，使用 `[start,end)`，端点相接不算重叠。三类规则取 OR 后做并查集传递闭包，输出的是解释用森林而不是所有命中边。

前向验证明确声明时间 interval、单位和 epoch。每折依次保留完整落入窗口的验证样本，排除其余同组件样本，再接纳 `end <= validation_start - gap` 的历史训练样本，其余分别标记 gap、future 或 boundary overlap。排除项不是活动分区；每折训练集和验证集都必须非空，任一组件不能同时出现在活动训练和验证中。

## 交付与验收材料

- v0.3.0 源码、兼容 v1 的库 API、v2 CLI 和 `run_check` / `run_acceptance` 双入口。
- 三类规则的固定示例、故意泄漏 assignment/role 反例、组件/见证/逐折角色与独立审计报告。
- v2 grouped 的 7/8 文件输出和 time-forward 的 8 文件输出说明。
- 优化对照、四组件穷举参考、100000 条 exact/interval 与 1000/5000/10000 条文本规模日志。
- 含工具链、命令、输入 SHA-256、时间和结果的每次新建 `artifacts/acceptance_*` 证据包。

## 验收步骤、发布链路与判定

运行 `run_acceptance.ps1` 或 `run_acceptance.sh`。脚本先运行格式、检查、wasm-gc/JS 测试和真实 CLI 对照，再比对两后端产品文件字节，验证 v1 回归、v2 规则反例 audit 的退出码 3、时间角色语义与输出文件数，最后生成规模和优化证据。正式发布按“干净提交 → 同 SHA CI → annotated tag → Mooncakes manifest → 干净目录安装 → 最终验收包”核验。通过判定以脚本返回 0、产品文件一致、反例 audit 失败且独立穷举差距为 0 为准；官方验收结论仍由主办方独立作出。项目为原创实现，未移植外部代码；PPJoin 仅为候选过滤算法参考，直接依赖为 `moonbitlang/x@0.4.46`，许可证为 Apache-2.0。官方要求见 [Hackathon 2026](https://moonbitlang.github.io/Hackathon2026/)，文本候选过滤参考 [PPJoin 原始论文](https://archives.iw3c2.org/www2008/papers/fp103.html)。

## 能力边界

文本 Jaccard 检测字符重叠，不能证明语义改写或音频、图像、视频相似。密集文本语料的候选比较仍可能退化为二次，受内存限制；候选/比较证据计数达到可移植 `Int` 上限前会以 `text_count_overflow` 显式失败，不会静默回绕或截断。区间只在声明为同一来源的记录间比较，来源内字符位置不充当全局时间。局部优化保证不劣于贪心初始化，不保证全局最优。审计只证明已声明规则和清单满足约束，不证明数据完全没有其他形式的泄漏。
