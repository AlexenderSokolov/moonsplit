///|
pub struct AuditReport {
  priv is_valid : Bool
  priv issues : Array[@record.Issue]
  priv partition_counts : Map[String, Int]
} derive(Debug)

///|
pub fn AuditReport::new(
  is_valid : Bool,
  issues : Array[@record.Issue],
  partition_counts : Map[String, Int],
) -> AuditReport {
  { is_valid, issues: issues.copy(), partition_counts, }
}

///|
pub fn AuditReport::is_valid(self : AuditReport) -> Bool {
  self.is_valid
}

///|
pub fn AuditReport::issues(self : AuditReport) -> Array[@record.Issue] {
  self.issues.copy()
}

///|
pub fn AuditReport::partition_counts(self : AuditReport) -> Map[String, Int] {
  let copied : Map[String, Int] = Map([])
  for partition in self.partition_counts.keys() {
    copied[partition] = self.partition_counts[partition]
  }
  copied
}

///|
pub fn audit_split(
  records : Array[@record.Record],
  spec : @spec.SplitSpec,
  assignments : Array[@record.Assignment],
) -> Result[AuditReport, Array[@record.Issue]] {
  let issues : Array[@record.Issue] = []
  let record_ids : Map[String, Bool] = Map([])
  for record in records {
    let id = record.id()
    if record_ids.contains(id) {
      issues.push(
        @record.Issue::error(
          "duplicate_record_id",
          "duplicate record id: \{id}",
        ),
      )
    } else {
      record_ids[id] = true
    }
  }
  for key_name in spec.isolation_keys() {
    for record in records {
      match record.key(key_name) {
        None =>
          issues.push(
            @record.Issue::error(
              "missing_isolation_key",
              "record \{record.id()} is missing isolation key \{key_name}",
            ),
          )
        Some(value) =>
          if value == "" {
            issues.push(
              @record.Issue::error(
                "empty_isolation_key",
                "record \{record.id()} has empty isolation key \{key_name}",
              ),
            )
          }
      }
    }
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
    } else {
      assigned[id] = partition
    }
  }
  let allowed : Map[String, Bool] = Map([])
  for partition in spec.partitions() {
    allowed[partition.name()] = true
  }
  for id in assigned.keys() {
    let partition = assigned[id]
    if !allowed.contains(partition) {
      issues.push(
        @record.Issue::error(
          "invalid_partition",
          "record \{id} uses unknown partition \{partition}",
        ),
      )
    }
  }
  for record in records {
    if !assigned.contains(record.id()) {
      issues.push(
        @record.Issue::error(
          "missing_assignment",
          "record \{record.id()} has no assignment",
        ),
      )
    }
  }
  let report = match @group.build_components(records, spec.isolation_keys()) {
    Err(component_issues) => {
      for issue in component_issues {
        issues.push(issue)
      }
      AuditReport::new(false, issues, Map([]))
    }
    Ok(components) => {
      for component in components.groups() {
        let component_partition : Map[String, Bool] = Map([])
        let mut first_partition = ""
        for record_id in component.member_ids() {
          match assigned.get(record_id) {
            Some(partition) =>
              if component_partition.length() == 0 {
                component_partition[partition] = true
                first_partition = partition
              } else if !component_partition.contains(partition) {
                issues.push(
                  @record.Issue::error(
                    "cross_partition_isolation",
                    "component \{component.id()} spans \{first_partition} and \{partition}",
                  ),
                )
              }
            None => ()
          }
        }
      }
      let partition_counts : Map[String, Int] = Map([])
      for partition in spec.partitions() {
        partition_counts[partition.name()] = 0
      }
      for id in assigned.keys() {
        let partition = assigned[id]
        match partition_counts.get(partition) {
          Some(count) => partition_counts[partition] = count + 1
          None => partition_counts[partition] = 1
        }
      }
      for partition in spec.partitions() {
        match partition_counts.get(partition.name()) {
          Some(0) =>
            issues.push(
              @record.Issue::error(
                "empty_partition",
                "partition \{partition.name()} is empty",
              ),
            )
          _ => ()
        }
      }
      let report = AuditReport::new(
        issues.length() == 0,
        issues,
        partition_counts,
      )
      report
    }
  }
  Ok(report)
}
