///|
test "assignment JSONL is stable and sorted by record id" {
  let components = @group.Components::new([
    @group.Component::new("b", ["b"], []),
    @group.Component::new("a", ["a"], []),
  ])
  let plan = @plan.SplitPlan::new(
    Holdout,
    ["speaker_id"],
    [
      @record.Assignment::new("b", "train"),
      @record.Assignment::new("a", "test"),
    ],
    components,
    42U,
    false,
    500,
    [@spec.Partition::new("train", 8), @spec.Partition::new("test", 2)],
    0,
    [],
  )
  assert_eq(
    assignments_jsonl(plan),
    "{\"id\": \"a\", \"partition\": \"test\"}\n{\"id\": \"b\", \"partition\": \"train\"}",
  )
}

///|
test "JSON export escapes control characters" {
  let components = @group.Components::new([
    @group.Component::new("a", ["a"], []),
  ])
  let plan = @plan.SplitPlan::new(
    Holdout,
    ["speaker_id"],
    [@record.Assignment::new("\u{0001}", "train")],
    components,
    42U,
    false,
    500,
    [@spec.Partition::new("train", 1)],
    0,
    [],
  )
  assert_eq(
    assignments_jsonl(plan),
    "{\"id\": \"\\u0001\", \"partition\": \"train\"}",
  )
}

///|
test "summary JSON has a stable schema and component diagnostics" {
  let components = @group.Components::new([
    @group.Component::new("a", ["a"], []),
    @group.Component::new("b", ["b"], []),
  ])
  let plan = @plan.SplitPlan::new(
    Holdout,
    ["speaker_id"],
    [
      @record.Assignment::new("a", "train"),
      @record.Assignment::new("b", "test"),
    ],
    components,
    42U,
    false,
    500,
    [@spec.Partition::new("train", 1), @spec.Partition::new("test", 1)],
    0,
    [],
  )
  assert_eq(
    summary_json(plan),
    "{\n  \"schema_version\": 1,\n  \"algorithm\": \"group-greedy-v1\",\n  \"records\": 2,\n  \"components\": 2,\n  \"largest_component\": {\"id\": \"a\", \"size\": 1},\n  \"partitions\": [\n    {\"name\": \"train\", \"weight\": 1, \"record_count\": 1, \"target_bp\": 5000, \"actual_bp\": 5000, \"deviation_bp\": 0, \"label_counts\": {}, \"unlabeled_count\": 0},\n    {\"name\": \"test\", \"weight\": 1, \"record_count\": 1, \"target_bp\": 5000, \"actual_bp\": 5000, \"deviation_bp\": 0, \"label_counts\": {}, \"unlabeled_count\": 0}\n  ]\n}",
  )
}

///|
test "audit JSON orders declared and unknown partitions and preserves issues" {
  let counts : Map[String, Int] = Map([])
  counts["z"] = 5
  counts["validation"] = 1
  counts["test"] = 1
  counts["train"] = 2
  let report = @audit.AuditReport::new(
    false,
    [
      @record.Issue::error_at_line("cross_partition_isolation", "leak", 7),
      @record.Issue::error("missing_assignment", "missing"),
    ],
    counts,
  )
  let spec = @spec.SplitSpec::new(
    Holdout,
    ["speaker_id"],
    42U,
    false,
    500,
    [@spec.Partition::new("train", 1), @spec.Partition::new("test", 1)],
    0,
  )
  assert_eq(
    audit_report_json(report, spec, 3, 4),
    "{\n  \"schema_version\": 1,\n  \"valid\": false,\n  \"records\": 3,\n  \"assignments\": 4,\n  \"partition_counts\": {\n    \"train\": 2,\n    \"test\": 1,\n    \"validation\": 1,\n    \"z\": 5\n  },\n  \"issues\": [\n    {\"severity\": \"error\", \"code\": \"cross_partition_isolation\", \"message\": \"leak\", \"line\": 7},\n    {\"severity\": \"error\", \"code\": \"missing_assignment\", \"message\": \"missing\", \"line\": null}\n  ]\n}",
  )
}

///|
test "kfold manifest is sorted, escaped, and rejects holdout plans" {
  let components = @group.Components::new([
    @group.Component::new("a", ["a"], []),
    @group.Component::new("b\"", ["b\""], []),
  ])
  let kfold = @plan.SplitPlan::new(
    KFold,
    ["speaker_id"],
    [
      @record.Assignment::new("b\"", "fold_1"),
      @record.Assignment::new("a", "fold_0"),
    ],
    components,
    42U,
    false,
    500,
    [@spec.Partition::new("fold_0", 1), @spec.Partition::new("fold_1", 1)],
    2,
    [],
  )
  let manifest = match folds_jsonl(kfold) {
    Ok(value) => value
    Err(issues) => {
      assert_true(false)
      ignore(issues)
      ""
    }
  }
  assert_eq(
    manifest, "{\"id\": \"a\", \"validation_fold\": \"fold_0\"}\n{\"id\": \"b\\\"\", \"validation_fold\": \"fold_1\"}",
  )
  let holdout = @plan.SplitPlan::new(
    Holdout,
    ["speaker_id"],
    [],
    @group.Components::new([]),
    42U,
    false,
    500,
    [@spec.Partition::new("train", 1), @spec.Partition::new("test", 1)],
    0,
    [],
  )
  match folds_jsonl(holdout) {
    Ok(_) => assert_true(false)
    Err(issues) => assert_eq(issues[0].code(), "not_kfold_plan")
  }
}

///|
test "summary JSON sorts labels within a partition" {
  let shared_keys : Map[String, String] = Map([])
  shared_keys["speaker_id"] = "shared"
  let other_keys : Map[String, String] = Map([])
  other_keys["speaker_id"] = "other"
  let records = [
    @record.Record::new("z_record", Some("z"), shared_keys),
    @record.Record::new("a_record", Some("a"), shared_keys),
    @record.Record::new("unlabeled_record", None, other_keys),
  ]
  let spec = @spec.SplitSpec::new(
    Holdout,
    ["speaker_id"],
    42U,
    false,
    10000,
    [@spec.Partition::new("train", 1), @spec.Partition::new("test", 1)],
    0,
  )
  let plan = match @plan.plan_split(records, spec) {
    Ok(value) => value
    Err(issues) => {
      assert_true(false)
      ignore(issues)
      @plan.SplitPlan::new(
        Holdout,
        [],
        [],
        @group.Components::new([]),
        0U,
        false,
        0,
        [],
        0,
        [],
      )
    }
  }
  assert_true(
    summary_json(plan).contains("\"label_counts\": {\"a\": 1, \"z\": 1}"),
  )
}

///|
test "v2 summary preserves targets when partition weights exceed Int totals" {
  let records = match
    @record.parse_v2_records(
      "[{\"id\":\"a\",\"keys\":{\"speaker\":\"a\"}},{\"id\":\"b\",\"keys\":{\"speaker\":\"b\"}}]",
      Json,
    ) {
    Ok(value) => value
    Err(_) => abort("test records should parse")
  }
  let spec = match
    @spec.parse_v2_spec(
      "{\"schema_version\":2,\"kind\":\"holdout\",\"ratio_tolerance_bp\":0,\"partitions\":[{\"name\":\"train\",\"weight\":1500000000},{\"name\":\"test\",\"weight\":1400000000}],\"rules\":[{\"id\":\"speaker\",\"type\":\"exact_key\",\"key\":\"speaker\"}]}",
    ) {
    Ok(value) => value
    Err(_) => abort("test spec should parse")
  }
  let plan = match @plan.plan_split_with_rules(records, spec) {
    Ok(value) => value
    Err(_) => abort("large-weight plan should succeed")
  }
  let summary = rule_summary_json(plan)
  assert_true(summary.contains("\"target_bp\": 5172"))
  assert_true(summary.contains("\"target_bp\": 4828"))
}

///|
test "v2 canonical specs round trip grouped kind-specific split fields" {
  let kfold = match
    @spec.parse_v2_spec(
      "{\"schema_version\":2,\"kind\":\"kfold\",\"seed\":7,\"k\":3,\"rules\":[{\"id\":\"speaker\",\"type\":\"exact_key\",\"key\":\"speaker\"}]}",
    ) {
    Ok(value) => value
    Err(_) => abort("kfold spec should parse")
  }
  let kfold_json = v2_spec_json(kfold)
  assert_true(kfold_json.contains("\"kind\": \"kfold\""))
  assert_true(kfold_json.contains("\"k\": 3"))
  assert_false(kfold_json.contains("\"partitions\""))
  match @spec.parse_v2_spec(kfold_json) {
    Ok(round_trip) => {
      assert_true(round_trip.kind() is GroupedKFold)
      assert_eq(round_trip.k(), 3)
    }
    Err(_) => assert_true(false)
  }

  let holdout = match
    @spec.parse_v2_spec(
      "{\"schema_version\":2,\"kind\":\"holdout\",\"partitions\":[{\"name\":\"train\",\"weight\":8},{\"name\":\"test\",\"weight\":2}],\"rules\":[{\"id\":\"speaker\",\"type\":\"exact_key\",\"key\":\"speaker\"}]}",
    ) {
    Ok(value) => value
    Err(_) => abort("holdout spec should parse")
  }
  let holdout_json = v2_spec_json(holdout)
  assert_true(holdout_json.contains("\"partitions\""))
  assert_false(holdout_json.contains("\"k\""))
  match @spec.parse_v2_spec(holdout_json) {
    Ok(round_trip) => {
      assert_true(round_trip.kind() is GroupedHoldout)
      assert_eq(round_trip.partitions()[0].name(), "train")
      assert_eq(round_trip.partitions()[0].weight(), 8)
      assert_eq(round_trip.partitions()[1].name(), "test")
      assert_eq(round_trip.partitions()[1].weight(), 2)
    }
    Err(_) => assert_true(false)
  }
}
