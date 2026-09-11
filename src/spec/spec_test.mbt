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
