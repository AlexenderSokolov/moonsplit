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
test "parse v2 records preserves text and named intervals" {
  let input = "[{\"id\":\"a\",\"label\":\"speech\",\"keys\":{\"source_id\":\"doc-1\"},\"text\":\"Hello 世界\",\"intervals\":{\"segment\":{\"start\":0,\"end\":12},\"observation\":{\"start\":10000,\"end\":20000}}}]"
  match parse_v2_records(input, Json) {
    Err(_) => assert_true(false)
    Ok(records) => {
      assert_eq(records.length(), 1)
      assert_eq(records[0].id(), "a")
      @test.assert_eq(records[0].text(), Some("Hello 世界"))
      match records[0].interval("segment") {
        None => assert_true(false)
        Some(interval) => {
          assert_eq(interval.start(), 0L)
          assert_eq(interval.end(), 12L)
        }
      }
      let snapshot = records[0].snapshot()
      @test.assert_eq(snapshot.text(), Some("Hello 世界"))
      match snapshot.interval("observation") {
        None => assert_true(false)
        Some(interval) => {
          assert_eq(interval.start(), 10000L)
          assert_eq(interval.end(), 20000L)
        }
      }
    }
  }
}

///|
test "parse v2 records rejects an empty interval" {
  let input = "[{\"id\":\"a\",\"keys\":{},\"intervals\":{\"segment\":{\"start\":8,\"end\":8}}}]"
  match parse_v2_records(input, Json) {
    Ok(_) => assert_true(false)
    Err(issues) => {
      assert_eq(issues.length(), 1)
      assert_eq(issues[0].code(), "invalid_interval_bounds")
    }
  }
}

///|
test "parse v2 records rejects interval values outside JSON safe integers" {
  let input = "[{\"id\":\"a\",\"keys\":{},\"intervals\":{\"segment\":{\"start\":9007199254740992,\"end\":9007199254740993}}}]"
  match parse_v2_records(input, Json) {
    Ok(_) => assert_true(false)
    Err(issues) => assert_eq(issues[0].code(), "unsafe_interval_start")
  }
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
