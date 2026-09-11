///|
pub struct SplitPlan {
  priv kind : @spec.SplitKind
  priv isolation_keys : Array[String]
  priv assignments : Array[@record.Assignment]
  priv components : @group.Components
  priv seed : UInt
  priv balance_labels : Bool
  priv ratio_tolerance_bp : Int
  priv partition_weights : Array[@spec.Partition]
  priv k : Int
  priv warnings : Array[String]
} derive(Debug)

///|
/// Deterministic record-count summary for one declared partition.
pub struct PartitionSummary {
  priv name : String
  priv weight : Int
  priv record_count : Int
  priv target_bp : Int
  priv actual_bp : Int
  priv deviation_bp : Int
} derive(Debug)

///|
pub fn PartitionSummary::name(self : PartitionSummary) -> String {
  self.name
}

///|
pub fn PartitionSummary::weight(self : PartitionSummary) -> Int {
  self.weight
}

///|
pub fn PartitionSummary::record_count(self : PartitionSummary) -> Int {
  self.record_count
}

///|
pub fn PartitionSummary::target_bp(self : PartitionSummary) -> Int {
  self.target_bp
}

///|
pub fn PartitionSummary::actual_bp(self : PartitionSummary) -> Int {
  self.actual_bp
}

///|
pub fn PartitionSummary::deviation_bp(self : PartitionSummary) -> Int {
  self.deviation_bp
}

///|
pub fn SplitPlan::kind(self : SplitPlan) -> @spec.SplitKind {
  self.kind
}

///|
pub fn SplitPlan::isolation_keys(self : SplitPlan) -> Array[String] {
  self.isolation_keys.copy()
}

///|
pub fn SplitPlan::assignments(self : SplitPlan) -> Array[@record.Assignment] {
  self.assignments.copy()
}

///|
pub fn SplitPlan::components(self : SplitPlan) -> @group.Components {
  self.components
}

///|
pub fn SplitPlan::seed(self : SplitPlan) -> UInt {
  self.seed
}

///|
pub fn SplitPlan::balance_labels(self : SplitPlan) -> Bool {
  self.balance_labels
}

///|
pub fn SplitPlan::ratio_tolerance_bp(self : SplitPlan) -> Int {
  self.ratio_tolerance_bp
}

///|
pub fn SplitPlan::partition_weights(self : SplitPlan) -> Array[@spec.Partition] {
  self.partition_weights.copy()
}

///|
pub fn SplitPlan::k(self : SplitPlan) -> Int {
  self.k
}

///|
pub fn SplitPlan::warnings(self : SplitPlan) -> Array[String] {
  self.warnings.copy()
}

///|
/// Return partition summaries in declared specification order.
pub fn SplitPlan::summaries(self : SplitPlan) -> Array[PartitionSummary] {
  let partitions = self.partition_weights.copy()
  let counts : Map[String, Int] = Map([])
  for partition in partitions {
    counts[partition.name()] = 0
  }
  for assignment in self.assignments {
    match counts.get(assignment.partition()) {
      Some(count) => counts[assignment.partition()] = count + 1
      None => ()
    }
  }
  let mut weight_sum = 0
  for partition in partitions {
    weight_sum += partition.weight()
  }
  let total = self.assignments.length()
  let summaries : Array[PartitionSummary] = []
  for partition in partitions {
    let record_count = counts[partition.name()]
    let target_bp = basis_points(partition.weight(), weight_sum)
    let actual_bp = if total == 0 {
      0
    } else {
      basis_points(record_count, total)
    }
    let raw_deviation = actual_bp - target_bp
    let deviation_bp = if raw_deviation < 0 {
      -raw_deviation
    } else {
      raw_deviation
    }
    summaries.push({
      name: partition.name(),
      weight: partition.weight(),
      record_count,
      target_bp,
      actual_bp,
      deviation_bp,
    })
  }
  summaries
}

///|
pub fn plan_split(
  records : Array[@record.Record],
  spec : @spec.SplitSpec,
) -> Result[SplitPlan, Array[@record.Issue]] {
  let components = match
    @group.build_components(records, spec.isolation_keys()) {
    Err(issues) => return Err(issues)
    Ok(value) => value
  }
  let partition_count = spec.partitions().length()
  if components.count() < partition_count {
    return Err([
      @record.Issue::error(
        "insufficient_components", "components are fewer than partitions",
      ),
    ])
  }
  let mut weight_sum = 0
  for partition in spec.partitions() {
    weight_sum = weight_sum + partition.weight()
  }
  let labels : Map[String, String] = Map([])
  let label_totals : Map[String, Int] = Map([])
  let mut record_count = 0
  for record in records {
    if spec.balance_labels() {
      match record.label() {
        None =>
          return Err([
            @record.Issue::error(
              "missing_label",
              "record \{record.id()} has no label but label balancing is enabled",
            ),
          ])
        Some(label) => {
          if label == "" {
            return Err([
              @record.Issue::error(
                "empty_label",
                "record \{record.id()} has empty label",
              ),
            ])
          }
          labels[record.id()] = label
        }
      }
    }
    match label_totals.get(record.label().unwrap_or("")) {
      Some(count) => label_totals[record.label().unwrap_or("")] = count + 1
      None => label_totals[record.label().unwrap_or("")] = 1
    }
    record_count = record_count + 1
  }
  let sizes : Array[Int] = []
  let label_counts : Array[Map[String, Int]] = []
  for _i = 0; _i < partition_count; _i = _i + 1 {
    sizes.push(0)
    label_counts.push(Map([]))
  }
  let ordered = order_components(components, spec.seed())
  let assignments : Array[@record.Assignment] = []
  for component_index = 0
      component_index < ordered.length()
      component_index = component_index + 1 {
    let component = ordered[component_index]
    let size = component.member_ids().length()
    let component_labels = component_label_counts(component, labels)
    let mut chosen = -1
    let mut best_delta = 0
    if component_index < partition_count {
      chosen = component_index
    } else {
      for partition_index = 0
          partition_index < partition_count
          partition_index = partition_index + 1 {
        let partition = spec.partitions()[partition_index]
        let current_size = sizes[partition_index]
        let current_label_count = label_counts[partition_index]
        let mut delta = 0
        let size_before = record_count * partition.weight() -
          weight_sum * current_size
        let size_after = record_count * partition.weight() -
          weight_sum * (current_size + size)
        delta = delta + size_after * size_after - size_before * size_before
        if spec.balance_labels() {
          for label in component_labels.keys() {
            let count = component_labels[label]
            let label_total = match label_totals.get(label) {
              Some(value) => value
              None => 0
            }
            let current = match current_label_count.get(label) {
              Some(value) => value
              None => 0
            }
            let before = label_total * partition.weight() - weight_sum * current
            let after = label_total * partition.weight() -
              weight_sum * (current + count)
            delta = delta + after * after - before * before
          }
        }
        if chosen == -1 || delta < best_delta {
          chosen = partition_index
          best_delta = delta
        }
      }
    }
    if chosen == -1 {
      return Err([
        @record.Issue::error("assignment_failed", "no partition selected"),
      ])
    }
    for record_id in component.member_ids() {
      assignments.push(
        @record.Assignment::new(record_id, spec.partitions()[chosen].name()),
      )
    }
    sizes[chosen] = sizes[chosen] + size
    for label in component_labels.keys() {
      let count = component_labels[label]
      match label_counts[chosen].get(label) {
        Some(value) => label_counts[chosen][label] = value + count
        None => label_counts[chosen][label] = count
      }
    }
  }
  assignments.sort_by((left, right) => compare_strings(left.id(), right.id()))
  let warnings = plan_warnings(records, spec, components)
  let plan = SplitPlan::new(
    spec.kind(),
    spec.isolation_keys(),
    assignments,
    components,
    spec.seed(),
    spec.balance_labels(),
    spec.ratio_tolerance_bp(),
    spec.partitions(),
    spec.k(),
    warnings,
  )
  let audit_result = @audit.audit_split(records, spec, plan.assignments())
  match audit_result {
    Err(issues) => return Err(issues)
    Ok(report) => if !report.is_valid() { return Err(report.issues()) }
  }
  Ok(plan)
}

///|
pub fn SplitPlan::new(
  kind : @spec.SplitKind,
  isolation_keys : Array[String],
  assignments : Array[@record.Assignment],
  components : @group.Components,
  seed : UInt,
  balance_labels : Bool,
  ratio_tolerance_bp : Int,
  partition_weights : Array[@spec.Partition],
  k : Int,
  warnings : Array[String],
) -> SplitPlan {
  let sorted_assignments = assignments.copy()
  sorted_assignments.sort_by((left, right) => {
    compare_strings(left.id(), right.id())
  })
  {
    kind,
    isolation_keys: isolation_keys.copy(),
    assignments: sorted_assignments,
    components,
    seed,
    balance_labels,
    ratio_tolerance_bp,
    partition_weights: partition_weights.copy(),
    k,
    warnings: warnings.copy(),
  }
}

///|
fn order_components(
  components : @group.Components,
  seed : UInt,
) -> Array[@group.Component] {
  let ordered : Array[@group.Component] = components.groups()
  ordered.sort_by((left, right) => {
    let left_size = left.member_ids().length()
    let right_size = right.member_ids().length()
    if left_size > right_size {
      -1
    } else if left_size < right_size {
      1
    } else {
      let left_order = component_order_key(left.id(), seed)
      let right_order = component_order_key(right.id(), seed)
      if left_order < right_order {
        -1
      } else if left_order > right_order {
        1
      } else {
        compare_strings(left.id(), right.id())
      }
    }
  })
  ordered
}

///|
fn component_order_key(id : String, seed : UInt) -> UInt {
  let mut hash = 2166136261U
  for ch in id {
    hash = (hash ^ ch.to_int().reinterpret_as_uint()) * 16777619U
  }
  hash ^ seed
}

///|
fn component_label_counts(
  component : @group.Component,
  labels : Map[String, String],
) -> Map[String, Int] {
  let counts : Map[String, Int] = Map([])
  for record_id in component.member_ids() {
    match labels.get(record_id) {
      Some(label) =>
        match counts.get(label) {
          Some(value) => counts[label] = value + 1
          None => counts[label] = 1
        }
      None => ()
    }
  }
  counts
}

///|
fn plan_warnings(
  records : Array[@record.Record],
  spec : @spec.SplitSpec,
  components : @group.Components,
) -> Array[String] {
  let warnings : Array[String] = []
  let mut total = 0
  let mut weight_sum = 0
  let mut max_weight = 0
  for _record in records {
    total = total + 1
  }
  for partition in spec.partitions() {
    weight_sum = weight_sum + partition.weight()
    if partition.weight() > max_weight {
      max_weight = partition.weight()
    }
  }
  if total > 0 && weight_sum > 0 {
    let ideal = (total * max_weight + weight_sum - 1) / weight_sum
    for component in components.groups() {
      let size = component.member_ids().length()
      if size > ideal {
        warnings.push(
          "component \{component.id()} has \{size} records, exceeding the largest weighted target \{ideal}",
        )
      }
    }
  }
  warnings
}

///|
fn compare_strings(left : String, right : String) -> Int {
  if left < right {
    -1
  } else if left > right {
    1
  } else {
    0
  }
}

///|
/// Convert a non-negative ratio to basis points using half-up rounding.
fn basis_points(numerator : Int, denominator : Int) -> Int {
  if denominator <= 0 {
    0
  } else {
    (numerator * 10000 + denominator / 2) / denominator
  }
}
