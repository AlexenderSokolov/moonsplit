///|
pub struct RuleSplitPlan {
  priv kind : @spec.V2Kind
  priv rules : Array[@spec.LeakageRule]
  priv assignments : Array[@record.Assignment]
  priv components : @rules.RuleComponents
  priv seed : UInt
  priv balance_labels : Bool
  priv ratio_tolerance_bp : Int
  priv partition_weights : Array[@spec.Partition]
  priv k : Int
  priv initial_objective : String
  priv objective : String
  priv optimization_rounds : Int
  priv warnings : Array[String]
} derive(Debug)

///|
pub fn RuleSplitPlan::kind(self : RuleSplitPlan) -> @spec.V2Kind {
  self.kind
}

///|
pub fn RuleSplitPlan::rules(self : RuleSplitPlan) -> Array[@spec.LeakageRule] {
  self.rules.copy()
}

///|
pub fn RuleSplitPlan::assignments(
  self : RuleSplitPlan,
) -> Array[@record.Assignment] {
  self.assignments.copy()
}

///|
pub fn RuleSplitPlan::components(self : RuleSplitPlan) -> @rules.RuleComponents {
  self.components
}

///|
pub fn RuleSplitPlan::seed(self : RuleSplitPlan) -> UInt {
  self.seed
}

///|
pub fn RuleSplitPlan::balance_labels(self : RuleSplitPlan) -> Bool {
  self.balance_labels
}

///|
pub fn RuleSplitPlan::ratio_tolerance_bp(self : RuleSplitPlan) -> Int {
  self.ratio_tolerance_bp
}

///|
pub fn RuleSplitPlan::partition_weights(
  self : RuleSplitPlan,
) -> Array[@spec.Partition] {
  self.partition_weights.copy()
}

///|
pub fn RuleSplitPlan::k(self : RuleSplitPlan) -> Int {
  self.k
}

///|
pub fn RuleSplitPlan::algorithm(_self : RuleSplitPlan) -> String {
  "group-local-v2"
}

///|
pub fn RuleSplitPlan::initial_objective(self : RuleSplitPlan) -> String {
  self.initial_objective
}

///|
pub fn RuleSplitPlan::objective(self : RuleSplitPlan) -> String {
  self.objective
}

///|
pub fn RuleSplitPlan::optimization_rounds(self : RuleSplitPlan) -> Int {
  self.optimization_rounds
}

///|
pub fn RuleSplitPlan::warnings(self : RuleSplitPlan) -> Array[String] {
  self.warnings.copy()
}

///|
pub fn RuleSplitPlan::partition_counts(
  self : RuleSplitPlan,
) -> Map[String, Int] {
  let counts : Map[String, Int] = Map([])
  for partition in self.partition_weights {
    counts[partition.name()] = 0
  }
  for assignment in self.assignments {
    counts[assignment.partition()] = counts[assignment.partition()] + 1
  }
  copy_rule_plan_int_map(counts)
}

///|
/// Plan a v2 grouped split with deterministic local component moves after greedy
/// initialization.  The public entry rebuilds rule components and independently
/// audits the returned manifest before it succeeds.
pub fn plan_split_with_rules(
  records : Array[@record.V2Record],
  spec : @spec.V2Spec,
) -> Result[RuleSplitPlan, Array[@record.Issue]] {
  if spec.kind() == TimeForward {
    return Err([
      @record.Issue::error(
        "invalid_spec_kind", "time_forward must be planned with plan_temporal",
      ),
    ])
  }
  let components = match @rules.build_rule_components(records, spec.rules()) {
    Ok(value) => value
    Err(issues) => return Err(issues)
  }
  let partitions = spec.partitions()
  if components.count() < partitions.length() {
    return Err([
      @record.Issue::error(
        "insufficient_components", "components are fewer than partitions",
      ),
    ])
  }
  let labels = match rule_plan_labels(records, spec.balance_labels()) {
    Ok(value) => value
    Err(issues) => return Err(issues)
  }
  let label_totals = rule_label_totals(labels)
  let label_names = sorted_rule_plan_map_keys(label_totals)
  let ordered_components = order_rule_components(components, spec.seed())
  let component_labels : Array[Map[String, Int]] = []
  for component in ordered_components {
    component_labels.push(rule_component_label_counts(component, labels))
  }
  let mut weight_sum = rule_bigint_zero()
  for partition in partitions {
    weight_sum = weight_sum + @bigint.BigInt::from_int(partition.weight())
  }
  let sizes : Array[Int] = []
  let partition_labels : Array[Map[String, Int]] = []
  let component_counts : Array[Int] = []
  for _partition in partitions {
    sizes.push(0)
    partition_labels.push(Map([]))
    component_counts.push(0)
  }
  let component_partitions : Array[Int] = []
  for index = 0; index < ordered_components.length(); index = index + 1 {
    let component = ordered_components[index]
    let chosen = if index < partitions.length() {
      index
    } else {
      choose_greedy_rule_partition(
        component.size(),
        component_labels[index],
        sizes,
        partition_labels,
        records.length(),
        partitions,
        weight_sum,
        label_totals,
        label_names,
        spec.balance_labels(),
      )
    }
    component_partitions.push(chosen)
    rule_apply_component_add(
      sizes,
      partition_labels,
      chosen,
      component.size(),
      component_labels[index],
    )
    component_counts[chosen] += 1
  }
  let initial_objective = rule_allocation_objective(
    sizes,
    partition_labels,
    records.length(),
    partitions,
    weight_sum,
    label_totals,
    label_names,
    spec.balance_labels(),
  )
  let optimization_rounds = optimize_rule_components(
    ordered_components,
    component_labels,
    component_partitions,
    sizes,
    partition_labels,
    component_counts,
    records.length(),
    partitions,
    weight_sum,
    label_totals,
    label_names,
    spec.balance_labels(),
  )
  let objective = rule_allocation_objective(
    sizes,
    partition_labels,
    records.length(),
    partitions,
    weight_sum,
    label_totals,
    label_names,
    spec.balance_labels(),
  )
  let assignments : Array[@record.Assignment] = []
  for index = 0; index < ordered_components.length(); index = index + 1 {
    let partition_name = partitions[component_partitions[index]].name()
    for id in ordered_components[index].member_ids() {
      assignments.push(@record.Assignment::new(id, partition_name))
    }
  }
  assignments.sort_by((left, right) => left.id().lexical_compare(right.id()))
  let plan = RuleSplitPlan::new(
    spec.kind(),
    spec.rules(),
    assignments,
    components,
    spec.seed(),
    spec.balance_labels(),
    spec.ratio_tolerance_bp(),
    partitions,
    spec.k(),
    initial_objective.to_string(),
    objective.to_string(),
    optimization_rounds,
    rule_plan_warnings(
      components,
      assignments,
      partitions,
      spec.ratio_tolerance_bp(),
    ),
  )
  let audit = match
    @audit.audit_split_with_rules(records, spec, plan.assignments()) {
    Ok(value) => value
    Err(issues) => return Err(issues)
  }
  if !audit.is_valid() {
    return Err(audit.issues())
  }
  Ok(plan)
}

///|
fn RuleSplitPlan::new(
  kind : @spec.V2Kind,
  rules : Array[@spec.LeakageRule],
  assignments : Array[@record.Assignment],
  components : @rules.RuleComponents,
  seed : UInt,
  balance_labels : Bool,
  ratio_tolerance_bp : Int,
  partition_weights : Array[@spec.Partition],
  k : Int,
  initial_objective : String,
  objective : String,
  optimization_rounds : Int,
  warnings : Array[String],
) -> RuleSplitPlan {
  let sorted_assignments = assignments.copy()
  sorted_assignments.sort_by((left, right) => {
    left.id().lexical_compare(right.id())
  })
  {
    kind,
    rules: rules.copy(),
    assignments: sorted_assignments,
    components,
    seed,
    balance_labels,
    ratio_tolerance_bp,
    partition_weights: partition_weights.copy(),
    k,
    initial_objective,
    objective,
    optimization_rounds,
    warnings: warnings.copy(),
  }
}

///|
fn rule_plan_labels(
  records : Array[@record.V2Record],
  balance_labels : Bool,
) -> Result[Map[String, String], Array[@record.Issue]] {
  let labels : Map[String, String] = Map([])
  if !balance_labels {
    return Ok(labels)
  }
  for record in records {
    match record.label() {
      Some(label) if label != "" => labels[record.id()] = label
      Some(_) =>
        return Err([
          @record.Issue::error(
            "empty_label",
            "record \{record.id()} has empty label",
          ),
        ])
      None =>
        return Err([
          @record.Issue::error(
            "missing_label",
            "record \{record.id()} has no label but label balancing is enabled",
          ),
        ])
    }
  }
  Ok(labels)
}

///|
fn rule_label_totals(labels : Map[String, String]) -> Map[String, Int] {
  let totals : Map[String, Int] = Map([])
  for id in labels.keys() {
    let label = labels[id]
    totals[label] = totals.get(label).unwrap_or(0) + 1
  }
  totals
}

///|
fn order_rule_components(
  components : @rules.RuleComponents,
  seed : UInt,
) -> Array[@rules.RuleComponent] {
  let ordered = components.groups()
  ordered.sort_by((left, right) => {
    if left.size() > right.size() {
      -1
    } else if left.size() < right.size() {
      1
    } else {
      let left_order = component_order_key(left.id(), seed)
      let right_order = component_order_key(right.id(), seed)
      if left_order < right_order {
        -1
      } else if left_order > right_order {
        1
      } else {
        left.id().lexical_compare(right.id())
      }
    }
  })
  ordered
}

///|
fn rule_component_label_counts(
  component : @rules.RuleComponent,
  labels : Map[String, String],
) -> Map[String, Int] {
  let counts : Map[String, Int] = Map([])
  for id in component.member_ids() {
    match labels.get(id) {
      Some(label) => counts[label] = counts.get(label).unwrap_or(0) + 1
      None => ()
    }
  }
  counts
}

///|
fn choose_greedy_rule_partition(
  component_size : Int,
  component_labels : Map[String, Int],
  sizes : Array[Int],
  partition_labels : Array[Map[String, Int]],
  total_records : Int,
  partitions : Array[@spec.Partition],
  weight_sum : @bigint.BigInt,
  label_totals : Map[String, Int],
  label_names : Array[String],
  balance_labels : Bool,
) -> Int {
  let mut chosen = 0
  let mut best_delta : @bigint.BigInt? = None
  for partition = 0; partition < partitions.length(); partition = partition + 1 {
    let delta = rule_add_delta(
      component_size, component_labels, partition, sizes, partition_labels, total_records,
      partitions, weight_sum, label_totals, label_names, balance_labels,
    )
    match best_delta {
      None => {
        chosen = partition
        best_delta = Some(delta)
      }
      Some(best) =>
        if delta < best {
          chosen = partition
          best_delta = Some(delta)
        }
    }
  }
  chosen
}

///|
fn optimize_rule_components(
  components : Array[@rules.RuleComponent],
  component_labels : Array[Map[String, Int]],
  component_partitions : Array[Int],
  sizes : Array[Int],
  partition_labels : Array[Map[String, Int]],
  component_counts : Array[Int],
  total_records : Int,
  partitions : Array[@spec.Partition],
  weight_sum : @bigint.BigInt,
  label_totals : Map[String, Int],
  label_names : Array[String],
  balance_labels : Bool,
) -> Int {
  let mut rounds = 0
  let mut keep_optimizing = true
  while keep_optimizing && rounds < 10 {
    let mut improved = false
    for index = 0; index < components.length(); index = index + 1 {
      let source = component_partitions[index]
      if component_counts[source] <= 1 {
        continue
      }
      let mut destination = -1
      let mut best_delta : @bigint.BigInt? = None
      for target = 0; target < partitions.length(); target = target + 1 {
        if target == source {
          continue
        }
        let delta = rule_move_delta(
          components[index].size(),
          component_labels[index],
          source,
          target,
          sizes,
          partition_labels,
          total_records,
          partitions,
          weight_sum,
          label_totals,
          label_names,
          balance_labels,
        )
        if delta < rule_bigint_zero() {
          match best_delta {
            None => {
              destination = target
              best_delta = Some(delta)
            }
            Some(best) =>
              if delta < best {
                destination = target
                best_delta = Some(delta)
              }
          }
        }
      }
      if destination >= 0 {
        rule_apply_component_remove(
          sizes,
          partition_labels,
          source,
          components[index].size(),
          component_labels[index],
        )
        rule_apply_component_add(
          sizes,
          partition_labels,
          destination,
          components[index].size(),
          component_labels[index],
        )
        component_partitions[index] = destination
        component_counts[source] -= 1
        component_counts[destination] += 1
        improved = true
      }
    }
    if !improved {
      keep_optimizing = false
    } else {
      rounds += 1
    }
  }
  rounds
}

///|
fn rule_apply_component_add(
  sizes : Array[Int],
  partition_labels : Array[Map[String, Int]],
  partition : Int,
  component_size : Int,
  component_labels : Map[String, Int],
) -> Unit {
  sizes[partition] += component_size
  for label in component_labels.keys() {
    partition_labels[partition][label] = partition_labels[partition]
      .get(label)
      .unwrap_or(0) +
      component_labels[label]
  }
}

///|
fn rule_apply_component_remove(
  sizes : Array[Int],
  partition_labels : Array[Map[String, Int]],
  partition : Int,
  component_size : Int,
  component_labels : Map[String, Int],
) -> Unit {
  sizes[partition] -= component_size
  for label in component_labels.keys() {
    partition_labels[partition][label] = partition_labels[partition]
      .get(label)
      .unwrap_or(0) -
      component_labels[label]
  }
}

///|
fn rule_add_delta(
  component_size : Int,
  component_labels : Map[String, Int],
  partition : Int,
  sizes : Array[Int],
  partition_labels : Array[Map[String, Int]],
  total_records : Int,
  partitions : Array[@spec.Partition],
  weight_sum : @bigint.BigInt,
  label_totals : Map[String, Int],
  label_names : Array[String],
  balance_labels : Bool,
) -> @bigint.BigInt {
  let mut delta = rule_size_error(
      total_records,
      weight_sum,
      partitions[partition].weight(),
      sizes[partition] + component_size,
    ) -
    rule_size_error(
      total_records,
      weight_sum,
      partitions[partition].weight(),
      sizes[partition],
    )
  if balance_labels {
    for label in label_names {
      let amount = component_labels.get(label).unwrap_or(0)
      if amount > 0 {
        let total = label_totals[label]
        let current = partition_labels[partition].get(label).unwrap_or(0)
        delta = delta +
          rule_size_error(
            total,
            weight_sum,
            partitions[partition].weight(),
            current + amount,
          ) -
          rule_size_error(
            total,
            weight_sum,
            partitions[partition].weight(),
            current,
          )
      }
    }
  }
  delta
}

///|
fn rule_move_delta(
  component_size : Int,
  component_labels : Map[String, Int],
  source : Int,
  target : Int,
  sizes : Array[Int],
  partition_labels : Array[Map[String, Int]],
  total_records : Int,
  partitions : Array[@spec.Partition],
  weight_sum : @bigint.BigInt,
  label_totals : Map[String, Int],
  label_names : Array[String],
  balance_labels : Bool,
) -> @bigint.BigInt {
  let mut delta = rule_size_error(
      total_records,
      weight_sum,
      partitions[source].weight(),
      sizes[source] - component_size,
    ) +
    rule_size_error(
      total_records,
      weight_sum,
      partitions[target].weight(),
      sizes[target] + component_size,
    ) -
    rule_size_error(
      total_records,
      weight_sum,
      partitions[source].weight(),
      sizes[source],
    ) -
    rule_size_error(
      total_records,
      weight_sum,
      partitions[target].weight(),
      sizes[target],
    )
  if balance_labels {
    for label in label_names {
      let amount = component_labels.get(label).unwrap_or(0)
      if amount > 0 {
        let total = label_totals[label]
        let source_current = partition_labels[source].get(label).unwrap_or(0)
        let target_current = partition_labels[target].get(label).unwrap_or(0)
        delta = delta +
          rule_size_error(
            total,
            weight_sum,
            partitions[source].weight(),
            source_current - amount,
          ) +
          rule_size_error(
            total,
            weight_sum,
            partitions[target].weight(),
            target_current + amount,
          ) -
          rule_size_error(
            total,
            weight_sum,
            partitions[source].weight(),
            source_current,
          ) -
          rule_size_error(
            total,
            weight_sum,
            partitions[target].weight(),
            target_current,
          )
      }
    }
  }
  delta
}

///|
fn rule_allocation_objective(
  sizes : Array[Int],
  partition_labels : Array[Map[String, Int]],
  total_records : Int,
  partitions : Array[@spec.Partition],
  weight_sum : @bigint.BigInt,
  label_totals : Map[String, Int],
  label_names : Array[String],
  balance_labels : Bool,
) -> @bigint.BigInt {
  let mut objective = rule_bigint_zero()
  for partition = 0; partition < partitions.length(); partition = partition + 1 {
    objective = objective +
      rule_size_error(
        total_records,
        weight_sum,
        partitions[partition].weight(),
        sizes[partition],
      )
    if balance_labels {
      for label in label_names {
        objective = objective +
          rule_size_error(
            label_totals[label],
            weight_sum,
            partitions[partition].weight(),
            partition_labels[partition].get(label).unwrap_or(0),
          )
      }
    }
  }
  objective
}

///|
/// Squared term (W*n - w*N)^2 evaluated only after converting every operand.
fn rule_size_error(
  total : Int,
  weight_sum : @bigint.BigInt,
  weight : Int,
  count : Int,
) -> @bigint.BigInt {
  let difference = weight_sum * @bigint.BigInt::from_int(count) -
    @bigint.BigInt::from_int(weight) * @bigint.BigInt::from_int(total)
  difference * difference
}

///|
fn rule_bigint_zero() -> @bigint.BigInt {
  @bigint.BigInt::from_int(0)
}

///|
fn rule_plan_warnings(
  components : @rules.RuleComponents,
  assignments : Array[@record.Assignment],
  partitions : Array[@spec.Partition],
  tolerance_bp : Int,
) -> Array[String] {
  let warnings : Array[String] = []
  let counts : Map[String, Int] = Map([])
  let mut total = 0
  let mut weight_sum = rule_bigint_zero()
  for partition in partitions {
    counts[partition.name()] = 0
    weight_sum = weight_sum + @bigint.BigInt::from_int(partition.weight())
  }
  for assignment in assignments {
    counts[assignment.partition()] = counts[assignment.partition()] + 1
    total += 1
  }
  if total > 0 && weight_sum > rule_bigint_zero() {
    for partition in partitions {
      if rule_ratio_exceeds_tolerance(
          counts[partition.name()],
          total,
          partition.weight(),
          weight_sum,
          tolerance_bp,
        ) {
        warnings.push(
          "partition \{partition.name()} exceeds ratio tolerance \{tolerance_bp}bp",
        )
      }
    }
  }
  let mut max_weight = 0
  for partition in partitions {
    if partition.weight() > max_weight {
      max_weight = partition.weight()
    }
  }
  if total > 0 && weight_sum > rule_bigint_zero() {
    let target_numerator = @bigint.BigInt::from_int(total) *
      @bigint.BigInt::from_int(max_weight) +
      (weight_sum - @bigint.BigInt::from_int(1))
    let ideal = target_numerator / weight_sum
    for component in components.groups() {
      if @bigint.BigInt::from_int(component.size()) > ideal {
        warnings.push(
          "component \{component.id()} exceeds the largest weighted target",
        )
      }
    }
  }
  warnings
}

///|
fn rule_ratio_exceeds_tolerance(
  count : Int,
  total : Int,
  weight : Int,
  weight_sum : @bigint.BigInt,
  tolerance_bp : Int,
) -> Bool {
  let difference = @bigint.BigInt::from_int(count) * weight_sum -
    @bigint.BigInt::from_int(total) * @bigint.BigInt::from_int(weight)
  let absolute_difference = if difference < rule_bigint_zero() {
    -difference
  } else {
    difference
  }
  absolute_difference * @bigint.BigInt::from_int(10000) >
  @bigint.BigInt::from_int(tolerance_bp) *
  @bigint.BigInt::from_int(total) *
  weight_sum
}

///|
fn sorted_rule_plan_map_keys(source : Map[String, Int]) -> Array[String] {
  let keys : Array[String] = []
  for key in source.keys() {
    keys.push(key)
  }
  keys.sort_by((left, right) => left.lexical_compare(right))
  keys
}

///|
fn copy_rule_plan_int_map(source : Map[String, Int]) -> Map[String, Int] {
  let copied : Map[String, Int] = Map([])
  for key in source.keys() {
    copied[key] = source[key]
  }
  copied
}
