///|
test "time-forward plan assigns the documented role priority for every record" {
  let records = match
    @record.parse_v2_records(
      "[{\"id\":\"history\",\"keys\":{\"speaker\":\"h\"},\"intervals\":{\"observation\":{\"start\":0,\"end\":1000}}},{\"id\":\"conflict_history\",\"keys\":{\"speaker\":\"shared\"},\"intervals\":{\"observation\":{\"start\":0,\"end\":1000}}},{\"id\":\"gap\",\"keys\":{\"speaker\":\"g\"},\"intervals\":{\"observation\":{\"start\":9001,\"end\":9500}}},{\"id\":\"boundary\",\"keys\":{\"speaker\":\"b\"},\"intervals\":{\"observation\":{\"start\":9500,\"end\":10500}}},{\"id\":\"validation\",\"keys\":{\"speaker\":\"shared\"},\"intervals\":{\"observation\":{\"start\":12000,\"end\":13000}}},{\"id\":\"future\",\"keys\":{\"speaker\":\"f\"},\"intervals\":{\"observation\":{\"start\":21000,\"end\":22000}}}]",
      Json,
    ) {
    Ok(value) => value
    Err(_) => abort("test records should parse")
  }
  let spec = match
    @spec.parse_v2_spec(
      "{\"schema_version\":2,\"kind\":\"time_forward\",\"rules\":[{\"id\":\"speaker\",\"type\":\"exact_key\",\"key\":\"speaker\"}],\"time\":{\"interval\":\"observation\",\"unit\":\"ms\",\"epoch\":\"unix\",\"gap\":1000,\"validation_windows\":[{\"id\":\"fold_0\",\"start\":10000,\"end\":20000}]}}",
    ) {
    Ok(value) => value
    Err(_) => abort("test spec should parse")
  }
  let plan = match plan_temporal(records, spec) {
    Ok(value) => value
    Err(_) => abort("time plan should succeed")
  }
  let roles : Map[String, TemporalRole] = Map([])
  for role in plan.roles() {
    roles[role.id()] = role
  }
  assert_eq(roles["validation"].role(), Validation)
  assert_eq(roles["validation"].reason(), ValidationWindow)
  assert_eq(roles["conflict_history"].role(), Excluded)
  assert_eq(roles["conflict_history"].reason(), ComponentConflict)
  assert_eq(roles["history"].role(), Train)
  assert_eq(roles["history"].reason(), Historical)
  assert_eq(roles["gap"].role(), Excluded)
  assert_eq(roles["gap"].reason(), Gap)
  assert_eq(roles["future"].reason(), Future)
  assert_eq(roles["boundary"].reason(), BoundaryOverlap)
}

///|
test "time-forward audit rejects a manifest that turns a component conflict into train" {
  let records = match
    @record.parse_v2_records(
      "[{\"id\":\"history\",\"keys\":{\"speaker\":\"shared\"},\"intervals\":{\"observation\":{\"start\":0,\"end\":1000}}},{\"id\":\"validation\",\"keys\":{\"speaker\":\"shared\"},\"intervals\":{\"observation\":{\"start\":12000,\"end\":13000}}},{\"id\":\"independent\",\"keys\":{\"speaker\":\"i\"},\"intervals\":{\"observation\":{\"start\":0,\"end\":1000}}}]",
      Json,
    ) {
    Ok(value) => value
    Err(_) => abort("test records should parse")
  }
  let spec = match
    @spec.parse_v2_spec(
      "{\"schema_version\":2,\"kind\":\"time_forward\",\"rules\":[{\"id\":\"speaker\",\"type\":\"exact_key\",\"key\":\"speaker\"}],\"time\":{\"interval\":\"observation\",\"unit\":\"ms\",\"epoch\":\"unix\",\"gap\":0,\"validation_windows\":[{\"id\":\"fold_0\",\"start\":10000,\"end\":20000}]}}",
    ) {
    Ok(value) => value
    Err(_) => abort("test spec should parse")
  }
  let roles = [
    TemporalRole::new("fold_0", "history", Train, Historical),
    TemporalRole::new("fold_0", "validation", Validation, ValidationWindow),
    TemporalRole::new("fold_0", "independent", Train, Historical),
  ]
  let audit = match audit_temporal(records, spec, roles) {
    Ok(value) => value
    Err(_) => abort("audit inputs should parse")
  }
  assert_false(audit.is_valid())
  let codes : Map[String, Bool] = Map([])
  for issue in audit.issues() {
    codes[issue.code()] = true
  }
  assert_true(codes.contains("invalid_temporal_role"))
  assert_true(codes.contains("temporal_component_leak"))
}

///|
test "time-forward refuses folds without both active train and validation records" {
  let validation_only = match
    @record.parse_v2_records(
      "[{\"id\":\"validation\",\"keys\":{},\"text\":\"only validation\",\"intervals\":{\"observation\":{\"start\":12000,\"end\":13000}}}]",
      Json,
    ) {
    Ok(value) => value
    Err(_) => abort("validation-only records should parse")
  }
  let history_only = match
    @record.parse_v2_records(
      "[{\"id\":\"history\",\"keys\":{},\"text\":\"only history\",\"intervals\":{\"observation\":{\"start\":0,\"end\":1000}}}]",
      Json,
    ) {
    Ok(value) => value
    Err(_) => abort("history-only records should parse")
  }
  let spec = match
    @spec.parse_v2_spec(
      "{\"schema_version\":2,\"kind\":\"time_forward\",\"rules\":[{\"id\":\"duplicate\",\"type\":\"text_jaccard\"}],\"time\":{\"interval\":\"observation\",\"unit\":\"ms\",\"epoch\":\"unix\",\"gap\":0,\"validation_windows\":[{\"id\":\"fold_0\",\"start\":10000,\"end\":20000}]}}",
    ) {
    Ok(value) => value
    Err(_) => abort("test spec should parse")
  }
  match plan_temporal(validation_only, spec) {
    Ok(_) => assert_true(false)
    Err(issues) => assert_eq(issues[0].code(), "empty_temporal_train")
  }
  match plan_temporal(history_only, spec) {
    Ok(_) => assert_true(false)
    Err(issues) => assert_eq(issues[0].code(), "empty_temporal_validation")
  }
}

///|
test "time-forward builds a complete manifest for every ordered validation window" {
  let records = match
    @record.parse_v2_records(
      "[{\"id\":\"cutoff\",\"keys\":{\"speaker\":\"cutoff\"},\"intervals\":{\"observation\":{\"start\":0,\"end\":5}}},{\"id\":\"touch_0\",\"keys\":{\"speaker\":\"touch_0\"},\"intervals\":{\"observation\":{\"start\":8,\"end\":10}}},{\"id\":\"validation_0\",\"keys\":{\"speaker\":\"validation_0\"},\"intervals\":{\"observation\":{\"start\":12,\"end\":18}}},{\"id\":\"between\",\"keys\":{\"speaker\":\"between\"},\"intervals\":{\"observation\":{\"start\":21,\"end\":24}}},{\"id\":\"gap_1\",\"keys\":{\"speaker\":\"gap_1\"},\"intervals\":{\"observation\":{\"start\":26,\"end\":30}}},{\"id\":\"validation_1\",\"keys\":{\"speaker\":\"validation_1\"},\"intervals\":{\"observation\":{\"start\":32,\"end\":38}}},{\"id\":\"future\",\"keys\":{\"speaker\":\"future\"},\"intervals\":{\"observation\":{\"start\":41,\"end\":42}}}]",
      Json,
    ) {
    Ok(value) => value
    Err(_) => abort("multi-window records should parse")
  }
  let spec = match
    @spec.parse_v2_spec(
      "{\"schema_version\":2,\"kind\":\"time_forward\",\"rules\":[{\"id\":\"speaker\",\"type\":\"exact_key\",\"key\":\"speaker\"}],\"time\":{\"interval\":\"observation\",\"unit\":\"ms\",\"epoch\":\"unix\",\"gap\":5,\"validation_windows\":[{\"id\":\"fold_0\",\"start\":10,\"end\":20},{\"id\":\"fold_1\",\"start\":30,\"end\":40}]}}",
    ) {
    Ok(value) => value
    Err(_) => abort("multi-window spec should parse")
  }
  let plan = match plan_temporal(records, spec) {
    Ok(value) => value
    Err(_) => abort("multi-window time plan should succeed")
  }
  assert_eq(plan.roles().length(), 14)
  let roles : Map[(String, String), TemporalRole] = Map([])
  for role in plan.roles() {
    roles[(role.fold_id(), role.id())] = role
  }
  let cutoff = roles[("fold_0", "cutoff")]
  assert_eq(cutoff.role(), Train)
  assert_eq(cutoff.reason(), Historical)
  let touch_0 = roles[("fold_0", "touch_0")]
  assert_eq(touch_0.role(), Excluded)
  assert_eq(touch_0.reason(), Gap)
  let gap_1 = roles[("fold_1", "gap_1")]
  assert_eq(gap_1.role(), Excluded)
  assert_eq(gap_1.reason(), Gap)
  let validation_1 = roles[("fold_1", "validation_1")]
  assert_eq(validation_1.role(), Validation)
  assert_eq(validation_1.reason(), ValidationWindow)
  let audit = match audit_temporal(records, spec, plan.roles()) {
    Ok(value) => value
    Err(_) => abort("multi-window audit should run")
  }
  assert_true(audit.is_valid())
}

///|
test "time-forward with zero gap trains a record ending at validation start" {
  let records = match
    @record.parse_v2_records(
      "[{\"id\":\"touch\",\"keys\":{\"speaker\":\"touch\"},\"intervals\":{\"observation\":{\"start\":0,\"end\":10}}},{\"id\":\"validation\",\"keys\":{\"speaker\":\"validation\"},\"intervals\":{\"observation\":{\"start\":12,\"end\":18}}}]",
      Json,
    ) {
    Ok(value) => value
    Err(_) => abort("zero-gap records should parse")
  }
  let spec = match
    @spec.parse_v2_spec(
      "{\"schema_version\":2,\"kind\":\"time_forward\",\"rules\":[{\"id\":\"speaker\",\"type\":\"exact_key\",\"key\":\"speaker\"}],\"time\":{\"interval\":\"observation\",\"unit\":\"ms\",\"epoch\":\"unix\",\"gap\":0,\"validation_windows\":[{\"id\":\"fold_0\",\"start\":10,\"end\":20}]}}",
    ) {
    Ok(value) => value
    Err(_) => abort("zero-gap spec should parse")
  }
  let plan = match plan_temporal(records, spec) {
    Ok(value) => value
    Err(_) => abort("zero-gap time plan should succeed")
  }
  let roles : Map[String, TemporalRole] = Map([])
  for role in plan.roles() {
    roles[role.id()] = role
  }
  assert_eq(roles["touch"].role(), Train)
  assert_eq(roles["touch"].reason(), Historical)
}
