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
