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
