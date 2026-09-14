///|
test "rule-aware plan keeps leakage components whole and passes independent audit" {
  let records = match
    @record.parse_v2_records(
      "[{\"id\":\"a\",\"label\":\"x\",\"keys\":{\"speaker\":\"s1\"},\"text\":\"first\"},{\"id\":\"b\",\"label\":\"x\",\"keys\":{\"speaker\":\"s1\"},\"text\":\"second\"},{\"id\":\"c\",\"label\":\"y\",\"keys\":{\"speaker\":\"s2\"},\"text\":\"third\"},{\"id\":\"d\",\"label\":\"y\",\"keys\":{\"speaker\":\"s3\"},\"text\":\"fourth\"}]",
      Json,
    ) {
    Ok(value) => value
    Err(_) => abort("test records should parse")
  }
  let spec = match
    @spec.parse_v2_spec(
      "{\"schema_version\":2,\"kind\":\"holdout\",\"seed\":42,\"balance_labels\":true,\"partitions\":[{\"name\":\"train\",\"weight\":1},{\"name\":\"test\",\"weight\":1}],\"rules\":[{\"id\":\"speaker\",\"type\":\"exact_key\",\"key\":\"speaker\"}]}",
    ) {
    Ok(value) => value
    Err(_) => abort("test spec should parse")
  }
  let plan = match plan_split_with_rules(records, spec) {
    Ok(value) => value
    Err(_) => abort("plan should succeed")
  }
  let partitions : Map[String, String] = Map([])
  for assignment in plan.assignments() {
    partitions[assignment.id()] = assignment.partition()
  }
  assert_eq(partitions["a"], partitions["b"])
  let audit = match
    @audit.audit_split_with_rules(records, spec, plan.assignments()) {
    Ok(value) => value
    Err(_) => abort("audit should receive valid inputs")
  }
  assert_true(audit.is_valid())
}

///|
test "rule-aware optimizer never returns an objective worse than greedy initialization" {
  let records = match
    @record.parse_v2_records(
      "[{\"id\":\"a0\",\"keys\":{\"group\":\"a\"}},{\"id\":\"a1\",\"keys\":{\"group\":\"a\"}},{\"id\":\"a2\",\"keys\":{\"group\":\"a\"}},{\"id\":\"a3\",\"keys\":{\"group\":\"a\"}},{\"id\":\"b0\",\"keys\":{\"group\":\"b\"}},{\"id\":\"b1\",\"keys\":{\"group\":\"b\"}},{\"id\":\"b2\",\"keys\":{\"group\":\"b\"}},{\"id\":\"c0\",\"keys\":{\"group\":\"c\"}},{\"id\":\"c1\",\"keys\":{\"group\":\"c\"}},{\"id\":\"d0\",\"keys\":{\"group\":\"d\"}},{\"id\":\"e0\",\"keys\":{\"group\":\"e\"}}]",
      Json,
    ) {
    Ok(value) => value
    Err(_) => abort("test records should parse")
  }
  let spec = match
    @spec.parse_v2_spec(
      "{\"schema_version\":2,\"kind\":\"holdout\",\"seed\":7,\"partitions\":[{\"name\":\"train\",\"weight\":8},{\"name\":\"test\",\"weight\":2}],\"rules\":[{\"id\":\"group\",\"type\":\"exact_key\",\"key\":\"group\"}]}",
    ) {
    Ok(value) => value
    Err(_) => abort("test spec should parse")
  }
  let plan = match plan_split_with_rules(records, spec) {
    Ok(value) => value
    Err(_) => abort("plan should succeed")
  }
  assert_true(
    compare_decimal_objectives(plan.objective(), plan.initial_objective()) <= 0,
  )
}

///|
test "rule-aware optimizer strictly improves the fixed four-component case" {
  let records = match
    @record.parse_v2_records(
      "[{\"id\":\"c0_a\",\"label\":\"A\",\"keys\":{\"group\":\"c0\"}},{\"id\":\"c0_b0\",\"label\":\"B\",\"keys\":{\"group\":\"c0\"}},{\"id\":\"c0_b1\",\"label\":\"B\",\"keys\":{\"group\":\"c0\"}},{\"id\":\"c0_b2\",\"label\":\"B\",\"keys\":{\"group\":\"c0\"}},{\"id\":\"c0_b3\",\"label\":\"B\",\"keys\":{\"group\":\"c0\"}},{\"id\":\"c1_a0\",\"label\":\"A\",\"keys\":{\"group\":\"c1\"}},{\"id\":\"c1_a1\",\"label\":\"A\",\"keys\":{\"group\":\"c1\"}},{\"id\":\"c1_a2\",\"label\":\"A\",\"keys\":{\"group\":\"c1\"}},{\"id\":\"c1_a3\",\"label\":\"A\",\"keys\":{\"group\":\"c1\"}},{\"id\":\"c2_a0\",\"label\":\"A\",\"keys\":{\"group\":\"c2\"}},{\"id\":\"c2_a1\",\"label\":\"A\",\"keys\":{\"group\":\"c2\"}},{\"id\":\"c2_b\",\"label\":\"B\",\"keys\":{\"group\":\"c2\"}},{\"id\":\"c3_b\",\"label\":\"B\",\"keys\":{\"group\":\"c3\"}}]",
      Json,
    ) {
    Ok(value) => value
    Err(_) => abort("test records should parse")
  }
  let spec = match
    @spec.parse_v2_spec(
      "{\"schema_version\":2,\"kind\":\"holdout\",\"seed\":0,\"balance_labels\":true,\"ratio_tolerance_bp\":10000,\"partitions\":[{\"name\":\"left\",\"weight\":1},{\"name\":\"right\",\"weight\":1}],\"rules\":[{\"id\":\"group\",\"type\":\"exact_key\",\"key\":\"group\"}]}",
    ) {
    Ok(value) => value
    Err(_) => abort("test spec should parse")
  }
  let plan = match plan_split_with_rules(records, spec) {
    Ok(value) => value
    Err(_) => abort("plan should succeed")
  }
  assert_eq(plan.initial_objective(), "76")
  assert_eq(plan.objective(), "52")
  assert_true(plan.optimization_rounds() >= 1)
}

///|
test "public v2 planner rejects an unrelated invalid constructor interval" {
  let invalid_intervals : Map[String, @record.Interval] = Map([])
  invalid_intervals["unused"] = @record.Interval::new(4L, 4L)
  let records = [
    @record.V2Record::new("a", None, Map([]), Some("alpha"), invalid_intervals),
    @record.V2Record::new("b", None, Map([]), Some("bravo"), Map([])),
  ]
  let spec = match
    @spec.parse_v2_spec(
      "{\"schema_version\":2,\"kind\":\"holdout\",\"partitions\":[{\"name\":\"train\",\"weight\":1},{\"name\":\"test\",\"weight\":1}],\"rules\":[{\"id\":\"duplicate\",\"type\":\"text_jaccard\"}]}",
    ) {
    Ok(value) => value
    Err(_) => abort("test spec should parse")
  }
  match plan_split_with_rules(records, spec) {
    Ok(_) => assert_true(false)
    Err(issues) => assert_eq(issues[0].code(), "invalid_interval_bounds")
  }
}

///|
fn compare_decimal_objectives(left : String, right : String) -> Int {
  if left.length() < right.length() {
    -1
  } else if left.length() > right.length() {
    1
  } else if left < right {
    -1
  } else if left > right {
    1
  } else {
    0
  }
}
