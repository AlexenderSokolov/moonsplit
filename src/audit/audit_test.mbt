///|
fn audit_spec() -> @spec.SplitSpec {
  @spec.SplitSpec::new(
    Holdout,
    ["speaker_id"],
    42U,
    false,
    500,
    [@spec.Partition::new("train", 8), @spec.Partition::new("test", 2)],
    0,
  )
}

///|
test "audit detects a component spanning partitions" {
  let keys : Map[String, String] = Map([])
  keys["speaker_id"] = "shared"
  let records = [
    @record.Record::new("a", None, keys),
    @record.Record::new("b", None, keys),
  ]
  let assignments = [
    @record.Assignment::new("a", "train"),
    @record.Assignment::new("b", "test"),
  ]
  let result = audit_split(records, audit_spec(), assignments)
  let report = match result {
    Ok(value) => value
    Err(_) => AuditReport::new(true, [], Map([]))
  }
  assert_false(report.is_valid())
  let mut has_leak = false
  for issue in report.issues() {
    if issue.code() == "cross_partition_isolation" {
      has_leak = true
    }
  }
  assert_true(has_leak)
}

///|
test "audit reports invalid manifests without trusting plan metadata" {
  let shared_keys : Map[String, String] = Map([])
  shared_keys["speaker_id"] = "shared"
  let records = [
    @record.Record::new("a", None, shared_keys),
    @record.Record::new("b", None, shared_keys),
    @record.Record::new("c", None, map_of([("speaker_id", "other")])),
  ]
  let assignments = [
    @record.Assignment::new("a", "train"),
    @record.Assignment::new("a", "train"),
    @record.Assignment::new("b", "test"),
    @record.Assignment::new("unknown", "validation"),
  ]
  let result = audit_split(records, audit_spec(), assignments)
  let report = match result {
    Ok(value) => value
    Err(_) => AuditReport::new(true, [], Map([]))
  }
  assert_false(report.is_valid())
  let codes : Map[String, Bool] = Map([])
  for issue in report.issues() {
    codes[issue.code()] = true
  }
  assert_true(codes.contains("duplicate_assignment"))
  assert_true(codes.contains("unknown_record_assignment"))
  assert_true(codes.contains("missing_assignment"))
  assert_true(codes.contains("cross_partition_isolation"))
}

///|
test "audit detects an empty declared partition" {
  let keys : Map[String, String] = Map([])
  keys["speaker_id"] = "shared"
  let records = [
    @record.Record::new("a", None, keys),
    @record.Record::new("b", None, keys),
    @record.Record::new("c", None, map_of([("speaker_id", "other")])),
  ]
  let assignments = [
    @record.Assignment::new("a", "train"),
    @record.Assignment::new("b", "train"),
    @record.Assignment::new("c", "train"),
  ]
  let result = audit_split(records, audit_spec(), assignments)
  let report = match result {
    Ok(value) => value
    Err(_) => AuditReport::new(true, [], Map([]))
  }
  assert_false(report.is_valid())
  let mut has_empty = false
  for issue in report.issues() {
    if issue.code() == "empty_partition" {
      has_empty = true
    }
  }
  assert_true(has_empty)
}

///|
test "audit partition counts are returned as an isolated copy" {
  let counts : Map[String, Int] = Map([])
  counts["train"] = 2
  let report = AuditReport::new(true, [], counts)
  let returned = report.partition_counts()
  returned["train"] = 99
  match report.partition_counts().get("train") {
    Some(value) => assert_eq(value, 2)
    None => assert_true(false)
  }
}

///|
fn map_of(entries : Array[(String, String)]) -> Map[String, String] {
  let map : Map[String, String] = Map([])
  for entry in entries {
    map[entry.0] = entry.1
  }
  map
}
