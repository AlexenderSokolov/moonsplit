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
test "audit_split rejects a constructor-built v1 spec before assignments" {
  let invalid = @spec.SplitSpec::new(
    Holdout,
    ["speaker_id"],
    42U,
    false,
    500,
    [@spec.Partition::new("train", 1), @spec.Partition::new("train", 1)],
    0,
  )
  match audit_split([], invalid, []) {
    Ok(_) => assert_true(false)
    Err(issues) => assert_eq(issues[0].code(), "invalid_partition_name")
  }
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
test "rule-aware audit catches text-only and interval-only leakage" {
  let records = match
    @record.parse_v2_records(
      "[{\"id\":\"text_a\",\"keys\":{\"source\":\"one\"},\"text\":\"A unique duplicated sentence\",\"intervals\":{\"segment\":{\"start\":0,\"end\":1}}},{\"id\":\"text_b\",\"keys\":{\"source\":\"two\"},\"text\":\"a UNIQUE duplicated sentence\",\"intervals\":{\"segment\":{\"start\":0,\"end\":1}}},{\"id\":\"window_a\",\"keys\":{\"source\":\"shared\"},\"text\":\"first independent\",\"intervals\":{\"segment\":{\"start\":0,\"end\":10}}},{\"id\":\"window_b\",\"keys\":{\"source\":\"shared\"},\"text\":\"second independent\",\"intervals\":{\"segment\":{\"start\":5,\"end\":12}}}]",
      Json,
    ) {
    Ok(value) => value
    Err(_) => abort("test records should parse")
  }
  let spec = match
    @spec.parse_v2_spec(
      "{\"schema_version\":2,\"kind\":\"holdout\",\"partitions\":[{\"name\":\"train\",\"weight\":1},{\"name\":\"test\",\"weight\":1}],\"rules\":[{\"id\":\"duplicate\",\"type\":\"text_jaccard\"},{\"id\":\"window\",\"type\":\"interval_overlap\",\"source_key\":\"source\",\"interval\":\"segment\"}]}",
    ) {
    Ok(value) => value
    Err(_) => abort("test spec should parse")
  }
  let assignments = [
    @record.Assignment::new("text_a", "train"),
    @record.Assignment::new("text_b", "test"),
    @record.Assignment::new("window_a", "train"),
    @record.Assignment::new("window_b", "test"),
  ]
  let report = match audit_split_with_rules(records, spec, assignments) {
    Ok(value) => value
    Err(_) => abort("audit input should be valid")
  }
  assert_false(report.is_valid())
  let mut rule_leaks = 0
  for issue in report.issues() {
    if issue.code() == "cross_partition_rule" {
      rule_leaks += 1
    }
  }
  assert_eq(rule_leaks, 2)
}

///|
test "rule-aware audit rejects a time-forward spec before inspecting assignments" {
  let spec = match
    @spec.parse_v2_spec(
      "{\"schema_version\":2,\"kind\":\"time_forward\",\"rules\":[{\"id\":\"speaker\",\"type\":\"exact_key\",\"key\":\"speaker\"}],\"time\":{\"interval\":\"observation\",\"unit\":\"ms\",\"epoch\":\"unix\",\"gap\":0,\"validation_windows\":[{\"id\":\"fold_0\",\"start\":10,\"end\":20}]}}",
    ) {
    Ok(value) => value
    Err(_) => abort("time spec should parse")
  }
  match audit_split_with_rules([], spec, []) {
    Ok(_) => assert_true(false)
    Err(issues) => assert_eq(issues[0].code(), "invalid_spec_kind")
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
