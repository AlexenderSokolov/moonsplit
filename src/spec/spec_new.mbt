///|
pub fn SplitSpec::new(
  kind : SplitKind,
  isolation_keys : Array[String],
  seed : UInt,
  balance_labels : Bool,
  ratio_tolerance_bp : Int,
  partitions : Array[Partition],
  k : Int,
) -> SplitSpec {
  let resolved_partitions = if kind == KFold && partitions.length() == 0 {
    let generated : Array[Partition] = []
    for index = 0; index < k; index = index + 1 {
      generated.push(Partition::new("fold_\{index}", 1))
    }
    generated
  } else {
    partitions.copy()
  }
  {
    kind,
    isolation_keys: isolation_keys.copy(),
    seed,
    balance_labels,
    ratio_tolerance_bp,
    partitions: resolved_partitions,
    k,
  }
}
