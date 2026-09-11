///|
fn balanced_spec() -> @spec.SplitSpec {
  @spec.SplitSpec::new(
    Holdout,
    ["speaker_id"],
    42U,
    false,
    500,
    [
      @spec.Partition::new("train", 8),
      @spec.Partition::new("validation", 1),
      @spec.Partition::new("test", 1),
    ],
    0,
  )
}

///|
fn weighted_spec() -> @spec.SplitSpec {
  @spec.SplitSpec::new(
    Holdout,
    ["speaker_id"],
    42U,
    false,
    500,
    [
      @spec.Partition::new("train", 6),
      @spec.Partition::new("validation", 2),
      @spec.Partition::new("test", 2),
    ],
    0,
  )
}

///|
fn equal_components(count : Int) -> Array[@record.Record] {
  let records : Array[@record.Record] = []
  for index = 0; index < count; index = index + 1 {
    let keys : Map[String, String] = Map([])
    keys["speaker_id"] = "speaker_\{index}"
    records.push(@record.Record::new("record_\{index}", Some("positive"), keys))
  }
  records
}

///|
fn same_component(
  records : Array[@record.Record],
  start : Int,
  count : Int,
  component_id : Int,
) -> Unit {
  let keys : Map[String, String] = Map([])
  keys["speaker_id"] = "speaker_\{component_id}"
  for offset = 0; offset < count; offset = offset + 1 {
    let id = "record_\{start + offset}"
    records.push(@record.Record::new(id, Some("negative"), keys))
  }
}

///|
test "twenty equal components split 16/2/2" {
  let result = plan_split(equal_components(20), balanced_spec())
  let plan = match result {
    Ok(value) => value
    Err(issues) => {
      assert_true(false)
      ignore(issues)
      SplitPlan::new(
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
  let counts : Map[String, Int] = Map([])
  for assignment in plan.assignments() {
    match counts.get(assignment.partition()) {
      Some(count) => counts[assignment.partition()] = count + 1
      None => counts[assignment.partition()] = 1
    }
  }
  @test.assert_eq(counts.get("train"), Some(16))
  @test.assert_eq(counts.get("validation"), Some(2))
  @test.assert_eq(counts.get("test"), Some(2))
}

///|
test "partition summaries report deterministic 8 to 1 to 1 basis points" {
  let result = plan_split(equal_components(20), balanced_spec())
  let plan = match result {
    Ok(value) => value
    Err(issues) => {
      assert_true(false)
      ignore(issues)
      SplitPlan::new(
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
  let summaries = plan.summaries()
  assert_eq(summaries.length(), 3)
  assert_eq(summaries[0].name(), "train")
  assert_eq(summaries[0].weight(), 8)
  assert_eq(summaries[0].record_count(), 16)
  assert_eq(summaries[0].target_bp(), 8000)
  assert_eq(summaries[0].actual_bp(), 8000)
  assert_eq(summaries[0].deviation_bp(), 0)
  assert_eq(summaries[1].name(), "validation")
  assert_eq(summaries[1].record_count(), 2)
  assert_eq(summaries[1].target_bp(), 1000)
  assert_eq(summaries[1].actual_bp(), 1000)
  assert_eq(summaries[1].deviation_bp(), 0)
  assert_eq(summaries[2].name(), "test")
}

///|
test "partition summaries use half-up basis points and return an isolated array" {
  let plan = SplitPlan::new(
    Holdout,
    ["speaker_id"],
    [
      @record.Assignment::new("a", "train"),
      @record.Assignment::new("b", "validation"),
      @record.Assignment::new("c", "validation"),
    ],
    @group.Components::new([]),
    42U,
    false,
    500,
    [@spec.Partition::new("train", 2), @spec.Partition::new("validation", 1)],
    0,
    [],
  )
  let summaries = plan.summaries()
  assert_eq(summaries[0].target_bp(), 6667)
  assert_eq(summaries[0].actual_bp(), 3333)
  assert_eq(summaries[0].deviation_bp(), 3334)
  assert_eq(summaries[1].target_bp(), 3333)
  assert_eq(summaries[1].actual_bp(), 6667)
  assert_eq(summaries[1].deviation_bp(), 3334)
  let mut returned = summaries
  let replacement = returned[1]
  returned[0] = replacement
  assert_eq(returned[0].name(), "validation")
  let fresh = plan.summaries()
  assert_eq(fresh[0].name(), "train")
}

///|
test "a large component is kept and warned" {
  let records : Array[@record.Record] = []
  same_component(records, 0, 1, 0)
  same_component(records, 1, 9, 1)
  same_component(records, 10, 2, 2)
  let result = plan_split(records, weighted_spec())
  let plan = match result {
    Ok(value) => value
    Err(issues) => {
      assert_true(false)
      ignore(issues)
      SplitPlan::new(
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
  assert_true(plan.warnings().length() > 0)
  let counts : Map[String, Int] = Map([])
  for assignment in plan.assignments() {
    match counts.get(assignment.partition()) {
      Some(count) => counts[assignment.partition()] = count + 1
      None => counts[assignment.partition()] = 1
    }
  }
  @test.assert_eq(counts.get("train"), Some(9))
}

///|
test "kfold validates each sample exactly once" {
  let records : Array[@record.Record] = []
  for index = 0; index < 10; index = index + 1 {
    let keys : Map[String, String] = Map([])
    keys["speaker_id"] = "speaker_\{index}"
    records.push(@record.Record::new("record_\{index}", Some("a"), keys))
  }
  let spec = @spec.SplitSpec::new(KFold, ["speaker_id"], 42U, false, 500, [], 5)
  let result = plan_split(records, spec)
  let plan = match result {
    Ok(value) => value
    Err(issues) => {
      assert_true(false)
      ignore(issues)
      SplitPlan::new(
        KFold,
        [],
        [],
        @group.Components::new([]),
        0U,
        false,
        0,
        [],
        5,
        [],
      )
    }
  }
  let validation_seen : Map[String, Int] = Map([])
  for fold_index = 0; fold_index < 5; fold_index = fold_index + 1 {
    let fold_name = "fold_\{fold_index}"
    let fold = match fold_members(plan, fold_name, Validation) {
      Ok(value) => value
      Err(_) => []
    }
    assert_eq(fold.length(), 2)
    for record_id in fold {
      match validation_seen.get(record_id) {
        Some(count) => validation_seen[record_id] = count + 1
        None => validation_seen[record_id] = 1
      }
    }
    let train = match fold_members(plan, fold_name, Train) {
      Ok(value) => value
      Err(_) => []
    }
    assert_eq(train.length(), 8)
  }
  for record in records {
    @test.assert_eq(validation_seen.get(record.id()), Some(1))
  }
}

///|
test "label balancing uses integer component targets" {
  let records : Array[@record.Record] = []
  for index = 0; index < 20; index = index + 1 {
    let keys : Map[String, String] = Map([])
    keys["speaker_id"] = "speaker_\{index}"
    let label = if index % 2 == 0 { Some("positive") } else { Some("negative") }
    records.push(@record.Record::new("record_\{index}", label, keys))
  }
  let spec = @spec.SplitSpec::new(
    Holdout,
    ["speaker_id"],
    42U,
    true,
    500,
    [
      @spec.Partition::new("train", 8),
      @spec.Partition::new("validation", 1),
      @spec.Partition::new("test", 1),
    ],
    0,
  )
  let result = plan_split(records, spec)
  let plan = match result {
    Ok(value) => value
    Err(issues) => {
      assert_true(false)
      ignore(issues)
      SplitPlan::new(
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
  let train_labels : Map[String, Int] = Map([])
  for assignment in plan.assignments() {
    if assignment.partition() == "train" {
      let label = records[index_of_id(records, assignment.id())]
        .label()
        .unwrap_or("")
      match train_labels.get(label) {
        Some(count) => train_labels[label] = count + 1
        None => train_labels[label] = 1
      }
    }
  }
  @test.assert_eq(train_labels.get("positive"), Some(8))
  @test.assert_eq(train_labels.get("negative"), Some(8))
}

///|
fn index_of_id(records : Array[@record.Record], id : String) -> Int {
  for index = 0; index < records.length(); index = index + 1 {
    if records[index].id() == id {
      return index
    }
  }
  -1
}

///|
test "planning is stable when input records are reversed" {
  let records = equal_components(20)
  let reversed_records : Array[@record.Record] = []
  for index = records.length() - 1; index >= 0; index = index - 1 {
    reversed_records.push(records[index])
  }
  let first = plan_split(records, balanced_spec())
  let second = plan_split(reversed_records, balanced_spec())
  let first_plan = match first {
    Ok(value) => value
    Err(issues) => {
      assert_true(false)
      ignore(issues)
      SplitPlan::new(
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
  let second_plan = match second {
    Ok(value) => value
    Err(issues) => {
      assert_true(false)
      ignore(issues)
      SplitPlan::new(
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
  assert_eq(
    first_plan.assignments().length(),
    second_plan.assignments().length(),
  )
  for index = 0; index < first_plan.assignments().length(); index = index + 1 {
    assert_eq(
      first_plan.assignments()[index].id(),
      second_plan.assignments()[index].id(),
    )
    assert_eq(
      first_plan.assignments()[index].partition(),
      second_plan.assignments()[index].partition(),
    )
  }
}
