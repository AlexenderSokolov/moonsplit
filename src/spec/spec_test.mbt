///|
test "parse spec accepts a UTF-8 byte order mark" {
  let input = "\u{feff}{\"schema_version\":1,\"kind\":\"kfold\",\"isolation_keys\":[\"speaker_id\"],\"k\":3}"
  match parse_spec(input) {
    Ok(spec) => {
      assert_true(spec.kind() is KFold)
      assert_eq(spec.k(), 3)
      assert_eq(spec.partitions().length(), 3)
    }
    Err(issues) => {
      assert_true(false)
      ignore(issues)
    }
  }
}

///|
test "parse spec rejects an unsupported schema version" {
  let input = "{\"schema_version\":2,\"kind\":\"kfold\",\"isolation_keys\":[\"speaker_id\"],\"k\":3}"
  match parse_spec(input) {
    Ok(_) => assert_true(false)
    Err(issues) => assert_eq(issues[0].code(), "unsupported_schema_version")
  }
}

///|
test "parse v2 grouped spec canonicalizes leakage rules" {
  let input = "{\"schema_version\":2,\"kind\":\"holdout\",\"seed\":7,\"partitions\":[{\"name\":\"train\",\"weight\":8},{\"name\":\"test\",\"weight\":2}],\"rules\":[{\"id\":\"window\",\"type\":\"interval_overlap\",\"source_key\":\"source_id\",\"interval\":\"segment\"},{\"id\":\"duplicate\",\"type\":\"text_jaccard\"}]}"
  match parse_v2_spec(input) {
    Ok(spec) => {
      let rules = spec.rules()
      assert_eq(rules.length(), 2)
      assert_eq(rules[0].id(), "duplicate")
      assert_true(rules[0].kind() is TextJaccard)
      assert_eq(rules[0].q(), 3)
      assert_eq(rules[0].threshold_bp(), 8000)
      assert_eq(rules[1].id(), "window")
      assert_true(rules[1].kind() is IntervalOverlap)
      assert_eq(rules[1].source_key(), Some("source_id"))
      assert_eq(rules[1].interval(), Some("segment"))
    }
    Err(issues) => {
      assert_true(false)
      ignore(issues)
    }
  }
}

///|
test "parse v2 spec rejects duplicate leakage rule ids" {
  let input = "{\"schema_version\":2,\"kind\":\"holdout\",\"partitions\":[{\"name\":\"train\",\"weight\":1},{\"name\":\"test\",\"weight\":1}],\"rules\":[{\"id\":\"same\",\"type\":\"exact_key\",\"key\":\"speaker\"},{\"id\":\"same\",\"type\":\"text_jaccard\"}]}"
  match parse_v2_spec(input) {
    Ok(_) => assert_true(false)
    Err(issues) => assert_eq(issues[0].code(), "duplicate_rule_id")
  }
}

///|
test "parse v2 time-forward spec preserves an explicit time coordinate" {
  let input = "{\"schema_version\":2,\"kind\":\"time_forward\",\"rules\":[{\"id\":\"duplicate\",\"type\":\"text_jaccard\"}],\"time\":{\"interval\":\"observation\",\"unit\":\"ms\",\"epoch\":\"unix\",\"gap\":1000,\"validation_windows\":[{\"id\":\"fold_0\",\"start\":10000,\"end\":20000},{\"id\":\"fold_1\",\"start\":30000,\"end\":40000}]}}"
  match parse_v2_spec(input) {
    Err(_) => assert_true(false)
    Ok(spec) => {
      assert_eq(spec.kind(), TimeForward)
      match spec.time() {
        None => assert_true(false)
        Some(time) => {
          assert_eq(time.interval(), "observation")
          assert_eq(time.unit(), "ms")
          assert_eq(time.epoch(), "unix")
          assert_eq(time.gap(), 1000L)
          let windows = time.validation_windows()
          assert_eq(windows.length(), 2)
          assert_eq(windows[0].id(), "fold_0")
          assert_eq(windows[1].start(), 30000L)
        }
      }
    }
  }
}

///|
test "parse v2 time-forward spec rejects overlapping validation windows" {
  let input = "{\"schema_version\":2,\"kind\":\"time_forward\",\"rules\":[{\"id\":\"speaker\",\"type\":\"exact_key\",\"key\":\"speaker\"}],\"time\":{\"interval\":\"observation\",\"unit\":\"ms\",\"epoch\":\"unix\",\"gap\":0,\"validation_windows\":[{\"id\":\"fold_0\",\"start\":10000,\"end\":20000},{\"id\":\"fold_1\",\"start\":19000,\"end\":30000}]}}"
  match parse_v2_spec(input) {
    Ok(_) => assert_true(false)
    Err(issues) => {
      assert_eq(issues.length(), 1)
      assert_eq(issues[0].code(), "invalid_validation_windows")
    }
  }
}

///|
test "parse v2 time-forward spec rejects unsafe JSON time values" {
  let unsafe_gap = "{\"schema_version\":2,\"kind\":\"time_forward\",\"rules\":[{\"id\":\"speaker\",\"type\":\"exact_key\",\"key\":\"speaker\"}],\"time\":{\"interval\":\"observation\",\"unit\":\"ms\",\"epoch\":\"unix\",\"gap\":9007199254740992,\"validation_windows\":[{\"id\":\"fold_0\",\"start\":10000,\"end\":20000}]}}"
  match parse_v2_spec(unsafe_gap) {
    Ok(_) => assert_true(false)
    Err(issues) => assert_eq(issues[0].code(), "unsafe_time_gap")
  }
}

///|
test "parse v2 grouped spec rejects an unsafe seed before conversion" {
  let unsafe_seed = "{\"schema_version\":2,\"kind\":\"holdout\",\"seed\":9007199254740992,\"partitions\":[{\"name\":\"train\",\"weight\":1},{\"name\":\"test\",\"weight\":1}],\"rules\":[{\"id\":\"speaker\",\"type\":\"exact_key\",\"key\":\"speaker\"}]}"
  match parse_v2_spec(unsafe_seed) {
    Ok(_) => assert_true(false)
    Err(issues) => assert_eq(issues[0].code(), "invalid_seed")
  }
}

///|
test "parse v2 grouped spec accepts safe large partition weights" {
  let input = "{\"schema_version\":2,\"kind\":\"holdout\",\"partitions\":[{\"name\":\"train\",\"weight\":1500000000},{\"name\":\"test\",\"weight\":1400000000}],\"rules\":[{\"id\":\"speaker\",\"type\":\"exact_key\",\"key\":\"speaker\"}]}"
  match parse_v2_spec(input) {
    Ok(spec) => {
      let partitions = spec.partitions()
      assert_eq(partitions[0].weight(), 1500000000)
      assert_eq(partitions[1].weight(), 1400000000)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "parse spec rejects fractional and negative seeds" {
  let fractional = "{\"schema_version\":1,\"kind\":\"kfold\",\"isolation_keys\":[\"speaker_id\"],\"k\":2,\"seed\":1.5}"
  let negative = "{\"schema_version\":1,\"kind\":\"kfold\",\"isolation_keys\":[\"speaker_id\"],\"k\":2,\"seed\":-1}"
  match parse_spec(fractional) {
    Ok(_) => assert_true(false)
    Err(issues) => assert_eq(issues[0].code(), "invalid_seed")
  }
  match parse_spec(negative) {
    Ok(_) => assert_true(false)
    Err(issues) => assert_eq(issues[0].code(), "invalid_seed")
  }
}

///|
test "parse spec rejects fractional k weight and ratio tolerance" {
  let fractional_k = "{\"schema_version\":1,\"kind\":\"kfold\",\"isolation_keys\":[\"speaker_id\"],\"k\":3.9}"
  let fractional_weight = "{\"schema_version\":1,\"kind\":\"holdout\",\"isolation_keys\":[\"speaker_id\"],\"partitions\":[{\"name\":\"a\",\"weight\":8.5},{\"name\":\"b\",\"weight\":1.5}]}"
  let fractional_tolerance = "{\"schema_version\":1,\"kind\":\"kfold\",\"isolation_keys\":[\"speaker_id\"],\"k\":2,\"ratio_tolerance_bp\":500.5}"
  match parse_spec(fractional_k) {
    Ok(_) => assert_true(false)
    Err(issues) => assert_eq(issues[0].code(), "invalid_k")
  }
  match parse_spec(fractional_weight) {
    Ok(_) => assert_true(false)
    Err(issues) => assert_eq(issues[0].code(), "invalid_partition_weight")
  }
  match parse_spec(fractional_tolerance) {
    Ok(_) => assert_true(false)
    Err(issues) => assert_eq(issues[0].code(), "invalid_ratio_tolerance_bp")
  }
}

///|
test "spec JSON expands holdout defaults and sorts isolation keys" {
  let input = "{\"schema_version\":1,\"kind\":\"holdout\",\"isolation_keys\":[\"speaker_id\",\"source\"]}"
  let spec = match parse_spec(input) {
    Ok(value) => value
    Err(issues) => {
      assert_true(false)
      ignore(issues)
      SplitSpec::new(Holdout, [], 0U, false, 0, [], 0)
    }
  }
  let expected = "{\n  \"schema_version\": 1,\n  \"kind\": \"holdout\",\n  \"isolation_keys\": [\"source\", \"speaker_id\"],\n  \"seed\": 42,\n  \"balance_labels\": false,\n  \"ratio_tolerance_bp\": 500,\n  \"partitions\": [\n    {\"name\": \"train\", \"weight\": 8},\n    {\"name\": \"validation\", \"weight\": 1},\n    {\"name\": \"test\", \"weight\": 1}\n  ]\n}"
  assert_eq(spec.to_json(), expected)
  match parse_spec(spec.to_json()) {
    Ok(round_trip) => {
      assert_true(round_trip.kind() is Holdout)
      let keys = round_trip.isolation_keys()
      assert_eq(keys.length(), 2)
      assert_eq(keys[0], "source")
      assert_eq(keys[1], "speaker_id")
      assert_eq(round_trip.partitions().length(), 3)
    }
    Err(issues) => {
      assert_true(false)
      ignore(issues)
    }
  }
}

///|
test "spec JSON omits generated kfold partitions" {
  let input = "{\"schema_version\":1,\"kind\":\"kfold\",\"isolation_keys\":[\"z\",\"a\"],\"k\":3,\"seed\":7}"
  let spec = match parse_spec(input) {
    Ok(value) => value
    Err(issues) => {
      assert_true(false)
      ignore(issues)
      SplitSpec::new(KFold, [], 0U, false, 0, [], 0)
    }
  }
  let expected = "{\n  \"schema_version\": 1,\n  \"kind\": \"kfold\",\n  \"isolation_keys\": [\"a\", \"z\"],\n  \"seed\": 7,\n  \"balance_labels\": false,\n  \"ratio_tolerance_bp\": 500,\n  \"k\": 3\n}"
  assert_eq(spec.to_json(), expected)
  assert_false(spec.to_json().contains("\"partitions\""))
}

///|
test "spec JSON escapes control characters" {
  let spec = SplitSpec::new(
    Holdout,
    ["line\nbreak", "quote\"key"],
    42U,
    false,
    500,
    [Partition::new("train", 1), Partition::new("test", 1)],
    0,
  )
  let json = spec.to_json()
  assert_true(json.contains("line\\nbreak"))
  assert_true(json.contains("quote\\\"key"))
}

///|
test "spec JSON uses dictionary order instead of shortlex order" {
  let input = "{\"schema_version\":1,\"kind\":\"kfold\",\"isolation_keys\":[\"z\",\"validation\"],\"k\":2}"
  let spec = match parse_spec(input) {
    Ok(value) => value
    Err(issues) => {
      assert_true(false)
      ignore(issues)
      SplitSpec::new(KFold, [], 0U, false, 0, [], 2)
    }
  }
  assert_true(spec.to_json().contains("[\"validation\", \"z\"]"))
}

///|
test "v1 accepts safe large partition weights and rejects unsafe JSON weights" {
  let large_without_total_overflow = "{\"schema_version\":1,\"kind\":\"holdout\",\"isolation_keys\":[\"speaker_id\"],\"partitions\":[{\"name\":\"train\",\"weight\":1500000000},{\"name\":\"test\",\"weight\":1}]}"
  match parse_spec(large_without_total_overflow) {
    Ok(spec) => assert_true(spec.to_json().contains("\"weight\": 1500000000"))
    Err(_) => assert_true(false)
  }
  let large_total = "{\"schema_version\":1,\"kind\":\"holdout\",\"isolation_keys\":[\"speaker_id\"],\"partitions\":[{\"name\":\"train\",\"weight\":1500000000},{\"name\":\"test\",\"weight\":1400000000}]}"
  match parse_spec(large_total) {
    Ok(spec) => assert_true(spec.to_json().contains("\"weight\": 1400000000"))
    Err(_) => assert_true(false)
  }
  let above_int_max = "{\"schema_version\":1,\"kind\":\"holdout\",\"isolation_keys\":[\"speaker_id\"],\"partitions\":[{\"name\":\"train\",\"weight\":2147483648},{\"name\":\"test\",\"weight\":1}]}"
  match parse_spec(above_int_max) {
    Ok(_) => assert_true(false)
    Err(issues) => assert_eq(issues[0].code(), "invalid_partition_weight")
  }
  let unsafe_json_weight = "{\"schema_version\":1,\"kind\":\"holdout\",\"isolation_keys\":[\"speaker_id\"],\"partitions\":[{\"name\":\"train\",\"weight\":9007199254740992},{\"name\":\"test\",\"weight\":1}]}"
  match parse_spec(unsafe_json_weight) {
    Ok(_) => assert_true(false)
    Err(issues) => assert_eq(issues[0].code(), "invalid_partition_weight")
  }
}
