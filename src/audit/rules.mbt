///|
pub struct RuleAuditReport {
  priv is_valid : Bool
  priv issues : Array[@record.Issue]
  priv partition_counts : Map[String, Int]
  priv components : @rules.RuleComponents
} derive(Debug)

///|
fn RuleAuditReport::new(
  is_valid : Bool,
  issues : Array[@record.Issue],
  partition_counts : Map[String, Int],
  components : @rules.RuleComponents,
) -> RuleAuditReport {
  {
    is_valid,
    issues: issues.copy(),
    partition_counts: copy_rule_partition_counts(partition_counts),
    components,
  }
}

///|
pub fn RuleAuditReport::is_valid(self : RuleAuditReport) -> Bool {
  self.is_valid
}

///|
pub fn RuleAuditReport::issues(self : RuleAuditReport) -> Array[@record.Issue] {
  self.issues.copy()
}

///|
pub fn RuleAuditReport::partition_counts(
  self : RuleAuditReport,
) -> Map[String, Int] {
  copy_rule_partition_counts(self.partition_counts)
}

///|
pub fn RuleAuditReport::components(
  self : RuleAuditReport,
) -> @rules.RuleComponents {
  self.components
}

///|
/// Rebuild v2 rule components from records and rules before validating a manifest.
pub fn audit_split_with_rules(
  records : Array[@record.V2Record],
  spec : @spec.V2Spec,
  assignments : Array[@record.Assignment],
) -> Result[RuleAuditReport, Array[@record.Issue]] {
  if spec.kind() == TimeForward {
    return Err([
      @record.Issue::error(
        "invalid_spec_kind", "time_forward must be audited with audit_temporal",
      ),
    ])
  }
  let components = match @rules.build_rule_components(records, spec.rules()) {
    Ok(value) => value
    Err(issues) => return Err(issues)
  }
  let issues : Array[@record.Issue] = []
  let record_ids : Map[String, Bool] = Map([])
  for record in records {
    record_ids[record.id()] = true
  }
  let allowed_partitions : Map[String, Bool] = Map([])
  let partition_counts : Map[String, Int] = Map([])
  for partition in spec.partitions() {
    allowed_partitions[partition.name()] = true
    partition_counts[partition.name()] = 0
  }
  let assigned : Map[String, String] = Map([])
  for assignment in assignments {
    let id = assignment.id()
    let partition = assignment.partition()
    if !record_ids.contains(id) {
      issues.push(
        @record.Issue::error(
          "unknown_record_assignment",
          "assignment refers to unknown record id: \{id}",
        ),
      )
    } else if assigned.contains(id) {
      issues.push(
        @record.Issue::error(
          "duplicate_assignment",
          "record \{id} is assigned more than once",
        ),
      )
    } else if !allowed_partitions.contains(partition) {
      issues.push(
        @record.Issue::error(
          "invalid_partition_assignment",
          "record \{id} is assigned to undeclared partition \{partition}",
        ),
      )
    } else {
      assigned[id] = partition
      partition_counts[partition] = partition_counts[partition] + 1
    }
  }
  for record in records {
    if !assigned.contains(record.id()) {
      issues.push(
        @record.Issue::error(
          "missing_assignment",
          "record \{record.id()} is not assigned",
        ),
      )
    }
  }
  for partition in spec.partitions() {
    if partition_counts[partition.name()] == 0 {
      issues.push(
        @record.Issue::error(
          "empty_partition",
          "declared partition \{partition.name()} has no records",
        ),
      )
    }
  }
  for component in components.groups() {
    let mut expected : String? = None
    for id in component.member_ids() {
      match assigned.get(id) {
        Some(partition) =>
          match expected {
            None => expected = Some(partition)
            Some(first) =>
              if first != partition {
                issues.push(
                  @record.Issue::error(
                    "cross_partition_rule",
                    "rule component \{component.id()} spans partitions \{first} and \{partition}",
                  ),
                )
                break
              }
          }
        None => ()
      }
    }
  }
  Ok(
    RuleAuditReport::new(
      issues.length() == 0,
      issues,
      partition_counts,
      components,
    ),
  )
}

///|
fn copy_rule_partition_counts(source : Map[String, Int]) -> Map[String, Int] {
  let copied : Map[String, Int] = Map([])
  for partition in source.keys() {
    copied[partition] = source[partition]
  }
  copied
}
