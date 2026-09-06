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
