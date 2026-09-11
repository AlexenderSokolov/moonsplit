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
