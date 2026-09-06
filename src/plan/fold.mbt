///|
pub(all) enum FoldSide {
  Validation
  Train
} derive(Eq, Debug)

///|
pub fn fold_members(
  plan : SplitPlan,
  fold_name : String,
  side : FoldSide,
) -> Result[Array[String], Array[@record.Issue]] {
  if plan.kind() != KFold {
    return Err([
      @record.Issue::error(
        "not_kfold_plan", "fold_members only accepts kfold plans",
      ),
    ])
  }
  let known : Map[String, Bool] = Map([])
  for partition in plan.partition_weights() {
    known[partition.name()] = true
  }
  if !known.contains(fold_name) {
    return Err([
      @record.Issue::error("unknown_fold", "unknown fold: \{fold_name}"),
    ])
  }
  let ids : Array[String] = []
  for assignment in plan.assignments() {
    let keep = match side {
      Validation => assignment.partition() == fold_name
      Train => assignment.partition() != fold_name
    }
    if keep {
      ids.push(assignment.id())
    }
  }
  ids.sort()
  Ok(ids)
}
