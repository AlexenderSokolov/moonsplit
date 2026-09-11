///|
test "parse JSONL reports line numbers" {
  let input = "\u{feff}{\"id\":\"a\",\"keys\":{\"speaker\":\"1\"}}\r\n{\"id\":\"b\",\"keys\":[]}\r\n"
  match parse_records(input, Jsonl) {
    Ok(_) => assert_true(false)
    Err(issues) => {
      assert_eq(issues.length(), 1)
      assert_eq(issues[0].code(), "missing_keys")
      @test.assert_eq(issues[0].line(), Some(2))
    }
  }
}

///|
test "parse records rejects duplicate ids" {
  let input = "[{\"id\":\"a\",\"keys\":{\"speaker\":\"1\"}},{\"id\":\"a\",\"keys\":{\"speaker\":\"2\"}}]"
  let result = parse_records(input, Json)
  assert_true(result is Err(_))
}

///|
test "parse JSON accepts a UTF-8 byte order mark" {
  let input = "\u{feff}[{\"id\":\"a\",\"keys\":{\"speaker\":\"1\"}}]"
  match parse_records(input, Json) {
    Ok(records) => assert_eq(records.length(), 1)
    Err(issues) => {
      assert_true(false)
      ignore(issues)
    }
  }
}

///|
test "parse assignments rejects an empty id with its line number" {
  let input = "{\"id\":\"\",\"partition\":\"train\"}\n"
  match parse_assignments(input) {
    Ok(_) => assert_true(false)
    Err(issues) => {
      assert_eq(issues.length(), 1)
      assert_eq(issues[0].code(), "empty_assignment_id")
      @test.assert_eq(issues[0].line(), Some(1))
    }
  }
}

///|
test "parse assignments rejects an empty partition with its line number" {
  let input = "{\"id\":\"a\",\"partition\":\"train\"}\n{\"id\":\"b\",\"partition\":\"\"}\n"
  match parse_assignments(input) {
    Ok(_) => assert_true(false)
    Err(issues) => {
      assert_eq(issues.length(), 1)
      assert_eq(issues[0].code(), "empty_assignment_partition")
      @test.assert_eq(issues[0].line(), Some(2))
    }
  }
}
