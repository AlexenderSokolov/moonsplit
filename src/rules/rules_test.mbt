///|
test "MoonBit lexical comparator keeps canonical ascending ordering" {
  let values = ["tail", "outer", "inside"]
  values.sort_by((left, right) => left.lexical_compare(right))
  @test.assert_eq(values, ["inside", "outer", "tail"])
}

///|
test "rule component builder validates every constructor-built interval" {
  let intervals : Map[String, @record.Interval] = Map([])
  intervals["unused"] = @record.Interval::new(8L, 8L)
  let records = [
    @record.V2Record::new("a", None, Map([]), Some("nonempty"), intervals),
  ]
  let spec = match
    @spec.parse_v2_spec(
      "{\"schema_version\":2,\"kind\":\"holdout\",\"partitions\":[{\"name\":\"train\",\"weight\":1},{\"name\":\"test\",\"weight\":1}],\"rules\":[{\"id\":\"duplicate\",\"type\":\"text_jaccard\"}]}",
    ) {
    Ok(value) => value
    Err(_) => abort("test spec should parse")
  }
  match build_rule_components(records, spec.rules()) {
    Ok(_) => assert_true(false)
    Err(issues) => assert_eq(issues[0].code(), "invalid_interval_bounds")
  }
}

///|
test "v2 rules join exact text and interval evidence into one component" {
  let records = match
    @record.parse_v2_records(
      "[{\"id\":\"a\",\"keys\":{\"speaker\":\"s1\",\"source\":\"doc\"},\"text\":\"Alpha beta gamma\",\"intervals\":{\"segment\":{\"start\":0,\"end\":5}}},{\"id\":\"b\",\"keys\":{\"speaker\":\"s1\",\"source\":\"other\"},\"text\":\"unrelated\",\"intervals\":{\"segment\":{\"start\":0,\"end\":1}}},{\"id\":\"c\",\"keys\":{\"speaker\":\"s2\",\"source\":\"other\"},\"text\":\"ALPHA  beta\\ngamma\",\"intervals\":{\"segment\":{\"start\":3,\"end\":4}}},{\"id\":\"d\",\"keys\":{\"speaker\":\"s3\",\"source\":\"doc\"},\"text\":\"different text\",\"intervals\":{\"segment\":{\"start\":4,\"end\":8}}}]",
      Json,
    ) {
    Ok(value) => value
    Err(_) => abort("test records should parse")
  }
  let spec = match
    @spec.parse_v2_spec(
      "{\"schema_version\":2,\"kind\":\"holdout\",\"partitions\":[{\"name\":\"train\",\"weight\":8},{\"name\":\"test\",\"weight\":2}],\"rules\":[{\"id\":\"window\",\"type\":\"interval_overlap\",\"source_key\":\"source\",\"interval\":\"segment\"},{\"id\":\"duplicate\",\"type\":\"text_jaccard\"},{\"id\":\"speaker\",\"type\":\"exact_key\",\"key\":\"speaker\"}]}",
    ) {
    Ok(value) => value
    Err(_) => abort("test spec should parse")
  }
  match build_rule_components(records, spec.rules()) {
    Err(_) => assert_true(false)
    Ok(components) => {
      assert_eq(components.count(), 1)
      let group = components.groups()[0]
      @test.assert_eq(group.member_ids(), ["a", "b", "c", "d"])
      assert_eq(group.witness_edges().length(), 3)
      assert_eq(components.text_candidate_count(), 1)
      assert_eq(components.text_comparison_count(), 1)
    }
  }
}

///|
test "text jaccard includes equality at the threshold" {
  let records = match
    @record.parse_v2_records(
      "[{\"id\":\"a\",\"keys\":{},\"text\":\"abcde\"},{\"id\":\"b\",\"keys\":{},\"text\":\"abcdf\"}]",
      Json,
    ) {
    Ok(value) => value
    Err(_) => abort("test records should parse")
  }
  let spec = match
    @spec.parse_v2_spec(
      "{\"schema_version\":2,\"kind\":\"holdout\",\"partitions\":[{\"name\":\"train\",\"weight\":1},{\"name\":\"test\",\"weight\":1}],\"rules\":[{\"id\":\"duplicate\",\"type\":\"text_jaccard\",\"q\":3,\"threshold_bp\":5000}]}",
    ) {
    Ok(value) => value
    Err(_) => abort("test spec should parse")
  }
  match build_rule_components(records, spec.rules()) {
    Err(_) => assert_true(false)
    Ok(components) => {
      assert_eq(components.count(), 1)
      assert_eq(components.text_candidate_count(), 1)
      assert_eq(components.text_comparison_count(), 1)
    }
  }
}

///|
test "text jaccard normalizes Chinese short text and keeps transitive chains" {
  let records = match
    @record.parse_v2_records(
      "[{\"id\":\"chain_a\",\"keys\":{},\"text\":\"abcd\"},{\"id\":\"chain_b\",\"keys\":{},\"text\":\"abef\"},{\"id\":\"chain_c\",\"keys\":{},\"text\":\"efgh\"},{\"id\":\"cn_a\",\"keys\":{},\"text\":\"你好世界\"},{\"id\":\"cn_b\",\"keys\":{},\"text\":\"你好世界\"},{\"id\":\"short_a\",\"keys\":{},\"text\":\"Hi\"},{\"id\":\"short_b\",\"keys\":{},\"text\":\" hI \"}]",
      Json,
    ) {
    Ok(value) => value
    Err(_) => abort("test records should parse")
  }
  let spec = match
    @spec.parse_v2_spec(
      "{\"schema_version\":2,\"kind\":\"holdout\",\"partitions\":[{\"name\":\"train\",\"weight\":1},{\"name\":\"test\",\"weight\":1}],\"rules\":[{\"id\":\"duplicate\",\"type\":\"text_jaccard\",\"q\":1,\"threshold_bp\":3333}]}",
    ) {
    Ok(value) => value
    Err(_) => abort("test spec should parse")
  }
  match build_rule_components(records, spec.rules()) {
    Err(_) => assert_true(false)
    Ok(components) => {
      assert_eq(components.count(), 3)
      let groups : Map[String, String] = Map([])
      for group in components.groups() {
        for id in group.member_ids() {
          groups[id] = group.id()
        }
      }
      assert_eq(groups["chain_a"], groups["chain_b"])
      assert_eq(groups["chain_b"], groups["chain_c"])
      assert_eq(groups["cn_a"], groups["cn_b"])
      assert_eq(groups["short_a"], groups["short_b"])
      assert_true(groups["chain_a"] != groups["cn_a"])
    }
  }
}

///|
test "text candidate filtering agrees with an independent naive pair scan" {
  let texts : Array[String] = []
  for
    value in [
      "abcde", "abcdf", "lmnop", "lmnox", "你好世界甲", "你好世界乙", "Hi",
      " hI ",
    ] {
    texts.push(value)
  }
  let input = "["
  let mut json = input
  for index = 0; index < texts.length(); index = index + 1 {
    if index > 0 {
      json = json + ","
    }
    json = json +
      "{\"id\":\"r\{index}\",\"keys\":{},\"text\":\"\{texts[index]}\"}"
  }
  json = json + "]"
  let records = match @record.parse_v2_records(json, Json) {
    Ok(value) => value
    Err(_) => abort("test records should parse")
  }
  let spec = match
    @spec.parse_v2_spec(
      "{\"schema_version\":2,\"kind\":\"holdout\",\"partitions\":[{\"name\":\"train\",\"weight\":1},{\"name\":\"test\",\"weight\":1}],\"rules\":[{\"id\":\"duplicate\",\"type\":\"text_jaccard\",\"q\":3,\"threshold_bp\":5000}]}",
    ) {
    Ok(value) => value
    Err(_) => abort("test spec should parse")
  }
  let components = match build_rule_components(records, spec.rules()) {
    Ok(value) => value
    Err(_) => abort("rule components should build")
  }
  for left = 0; left < texts.length(); left = left + 1 {
    for right = left + 1; right < texts.length(); right = right + 1 {
      let naive = naive_jaccard_match(texts[left], texts[right], 3, 5000)
      let actual = same_rule_component(
        components,
        records[left].id(),
        records[right].id(),
      )
      assert_eq(actual, naive)
    }
  }
}

///|
test "interval overlap treats touching endpoints and distinct sources as isolated" {
  let records = match
    @record.parse_v2_records(
      "[{\"id\":\"a\",\"keys\":{\"source\":\"one\"},\"intervals\":{\"segment\":{\"start\":0,\"end\":10}}},{\"id\":\"b\",\"keys\":{\"source\":\"one\"},\"intervals\":{\"segment\":{\"start\":10,\"end\":20}}},{\"id\":\"c\",\"keys\":{\"source\":\"two\"},\"intervals\":{\"segment\":{\"start\":5,\"end\":15}}}]",
      Json,
    ) {
    Ok(value) => value
    Err(_) => abort("test records should parse")
  }
  let spec = match
    @spec.parse_v2_spec(
      "{\"schema_version\":2,\"kind\":\"holdout\",\"partitions\":[{\"name\":\"train\",\"weight\":1},{\"name\":\"test\",\"weight\":1}],\"rules\":[{\"id\":\"window\",\"type\":\"interval_overlap\",\"source_key\":\"source\",\"interval\":\"segment\"}]}",
    ) {
    Ok(value) => value
    Err(_) => abort("test spec should parse")
  }
  match build_rule_components(records, spec.rules()) {
    Err(_) => assert_true(false)
    Ok(components) => assert_eq(components.count(), 3)
  }
}

///|
test "interval scan preserves naive overlap connectivity for chains and containment" {
  let records = match
    @record.parse_v2_records(
      "[{\"id\":\"outer\",\"keys\":{\"source\":\"one\"},\"intervals\":{\"segment\":{\"start\":0,\"end\":100}}},{\"id\":\"inside\",\"keys\":{\"source\":\"one\"},\"intervals\":{\"segment\":{\"start\":10,\"end\":20}}},{\"id\":\"tail\",\"keys\":{\"source\":\"one\"},\"intervals\":{\"segment\":{\"start\":99,\"end\":120}}},{\"id\":\"other\",\"keys\":{\"source\":\"two\"},\"intervals\":{\"segment\":{\"start\":10,\"end\":110}}}]",
      Json,
    ) {
    Ok(value) => value
    Err(_) => abort("test records should parse")
  }
  let spec = match
    @spec.parse_v2_spec(
      "{\"schema_version\":2,\"kind\":\"holdout\",\"partitions\":[{\"name\":\"train\",\"weight\":1},{\"name\":\"test\",\"weight\":1}],\"rules\":[{\"id\":\"window\",\"type\":\"interval_overlap\",\"source_key\":\"source\",\"interval\":\"segment\"}]}",
    ) {
    Ok(value) => value
    Err(_) => abort("test spec should parse")
  }
  match build_rule_components(records, spec.rules()) {
    Err(_) => assert_true(false)
    Ok(components) => {
      assert_eq(components.count(), 2)
      let first = components.groups()[0]
      @test.assert_eq(first.member_ids(), ["inside", "outer", "tail"])
      // A component of three intervals has two explanatory scan witnesses,
      // although its naive pairwise-overlap graph has all three edges.
      assert_eq(first.witness_edges().length(), 2)
    }
  }
}

///|
test "interval scan agrees with an independent naive intersection graph" {
  let sources : Array[String] = []
  for value in ["one", "one", "one", "one", "one", "two"] {
    sources.push(value)
  }
  let starts : Array[Int64] = []
  for value in [0L, 9L, 20L, 29L, 5L, 0L] {
    starts.push(value)
  }
  let ends : Array[Int64] = []
  for value in [10L, 20L, 30L, 40L, 7L, 100L] {
    ends.push(value)
  }
  let mut json = "["
  for index = 0; index < sources.length(); index = index + 1 {
    if index > 0 {
      json = json + ","
    }
    json = json +
      "{\"id\":\"i\{index}\",\"keys\":{\"source\":\"\{sources[index]}\"},\"intervals\":{\"segment\":{\"start\":\{starts[index]},\"end\":\{ends[index]}}}}"
  }
  json = json + "]"
  let records = match @record.parse_v2_records(json, Json) {
    Ok(value) => value
    Err(_) => abort("test records should parse")
  }
  let spec = match
    @spec.parse_v2_spec(
      "{\"schema_version\":2,\"kind\":\"holdout\",\"partitions\":[{\"name\":\"train\",\"weight\":1},{\"name\":\"test\",\"weight\":1}],\"rules\":[{\"id\":\"window\",\"type\":\"interval_overlap\",\"source_key\":\"source\",\"interval\":\"segment\"}]}",
    ) {
    Ok(value) => value
    Err(_) => abort("test spec should parse")
  }
  let components = match build_rule_components(records, spec.rules()) {
    Ok(value) => value
    Err(_) => abort("rule components should build")
  }
  for left = 0; left < records.length(); left = left + 1 {
    for right = left + 1; right < records.length(); right = right + 1 {
      let naive = naive_interval_reachable(left, right, sources, starts, ends)
      let actual = same_rule_component(
        components,
        records[left].id(),
        records[right].id(),
      )
      assert_eq(actual, naive)
    }
  }
}

///|
test "v2 components and witnesses are stable under record and rule reordering" {
  let records = match
    @record.parse_v2_records(
      "[{\"id\":\"a\",\"keys\":{\"speaker\":\"s1\",\"source\":\"doc\"},\"text\":\"alpha beta gamma\",\"intervals\":{\"segment\":{\"start\":0,\"end\":10}}},{\"id\":\"b\",\"keys\":{\"speaker\":\"s1\",\"source\":\"other\"},\"text\":\"bravo\",\"intervals\":{\"segment\":{\"start\":0,\"end\":1}}},{\"id\":\"c\",\"keys\":{\"speaker\":\"s2\",\"source\":\"other\"},\"text\":\"ALPHA  beta\\ngamma\",\"intervals\":{\"segment\":{\"start\":3,\"end\":4}}},{\"id\":\"d\",\"keys\":{\"speaker\":\"s3\",\"source\":\"doc\"},\"text\":\"delta\",\"intervals\":{\"segment\":{\"start\":5,\"end\":12}}}]",
      Json,
    ) {
    Ok(value) => value
    Err(_) => abort("test records should parse")
  }
  let reversed = [records[3], records[2], records[1], records[0]]
  let first_spec = match
    @spec.parse_v2_spec(
      "{\"schema_version\":2,\"kind\":\"holdout\",\"partitions\":[{\"name\":\"train\",\"weight\":1},{\"name\":\"test\",\"weight\":1}],\"rules\":[{\"id\":\"speaker\",\"type\":\"exact_key\",\"key\":\"speaker\"},{\"id\":\"duplicate\",\"type\":\"text_jaccard\"},{\"id\":\"window\",\"type\":\"interval_overlap\",\"source_key\":\"source\",\"interval\":\"segment\"}]}",
    ) {
    Ok(value) => value
    Err(_) => abort("first spec should parse")
  }
  let second_spec = match
    @spec.parse_v2_spec(
      "{\"schema_version\":2,\"kind\":\"holdout\",\"partitions\":[{\"name\":\"train\",\"weight\":1},{\"name\":\"test\",\"weight\":1}],\"rules\":[{\"id\":\"window\",\"type\":\"interval_overlap\",\"source_key\":\"source\",\"interval\":\"segment\"},{\"id\":\"duplicate\",\"type\":\"text_jaccard\"},{\"id\":\"speaker\",\"type\":\"exact_key\",\"key\":\"speaker\"}]}",
    ) {
    Ok(value) => value
    Err(_) => abort("second spec should parse")
  }
  let first = match build_rule_components(records, first_spec.rules()) {
    Ok(value) => value
    Err(_) => abort("first components should build")
  }
  let second = match build_rule_components(reversed, second_spec.rules()) {
    Ok(value) => value
    Err(_) => abort("second components should build")
  }
  assert_eq(first.count(), second.count())
  for index = 0; index < first.count(); index = index + 1 {
    let left = first.groups()[index]
    let right = second.groups()[index]
    assert_eq(left.id(), right.id())
    @test.assert_eq(left.member_ids(), right.member_ids())
    assert_eq(left.witness_edges().length(), right.witness_edges().length())
    for edge_index = 0
        edge_index < left.witness_edges().length()
        edge_index = edge_index + 1 {
      let left_edge = left.witness_edges()[edge_index]
      let right_edge = right.witness_edges()[edge_index]
      assert_eq(left_edge.rule_id(), right_edge.rule_id())
      assert_eq(left_edge.left_id(), right_edge.left_id())
      assert_eq(left_edge.right_id(), right_edge.right_id())
    }
  }
}

///|
fn same_rule_component(
  components : RuleComponents,
  left_id : String,
  right_id : String,
) -> Bool {
  for component in components.groups() {
    let mut has_left = false
    let mut has_right = false
    for id in component.member_ids() {
      if id == left_id {
        has_left = true
      }
      if id == right_id {
        has_right = true
      }
    }
    if has_left && has_right {
      return true
    }
  }
  false
}

///|
fn naive_jaccard_match(
  left_text : String,
  right_text : String,
  q : Int,
  threshold_bp : Int,
) -> Bool {
  let left = naive_qgrams(left_text, q)
  let right = naive_qgrams(right_text, q)
  let mut intersection = 0
  for token in left {
    for other in right {
      if token == other {
        intersection += 1
      }
    }
  }
  let union = left.length() + right.length() - intersection
  intersection * 10000 >= threshold_bp * union
}

///|
fn naive_qgrams(text : String, q : Int) -> Array[String] {
  let normalized : Array[Char] = []
  let mut pending_space = false
  let mut pending_carriage_return = false
  for ch in text {
    if pending_carriage_return {
      if ch == '\n' {
        pending_space = true
        pending_carriage_return = false
        continue
      }
      pending_space = true
      pending_carriage_return = false
    }
    if ch == '\r' {
      pending_carriage_return = true
    } else if ch.is_whitespace() {
      pending_space = true
    } else {
      if pending_space && normalized.length() > 0 {
        normalized.push(' ')
      }
      normalized.push(ch.to_ascii_lowercase())
      pending_space = false
    }
  }
  let tokens : Array[String] = []
  if normalized.length() < q {
    tokens.push(naive_chars_to_string(normalized, 0, normalized.length()))
  } else {
    for start = 0; start <= normalized.length() - q; start = start + 1 {
      tokens.push(naive_chars_to_string(normalized, start, start + q))
    }
  }
  let unique : Map[String, Bool] = Map([])
  for token in tokens {
    unique[token] = true
  }
  let result : Array[String] = []
  for token in unique.keys() {
    result.push(token)
  }
  result
}

///|
fn naive_chars_to_string(chars : Array[Char], start : Int, end : Int) -> String {
  let builder = StringBuilder()
  for index = start; index < end; index = index + 1 {
    builder.write_char(chars[index])
  }
  builder.to_string()
}

///|
fn naive_interval_reachable(
  left : Int,
  right : Int,
  sources : Array[String],
  starts : Array[Int64],
  ends : Array[Int64],
) -> Bool {
  let reachable : Array[Bool] = []
  for index = 0; index < sources.length(); index = index + 1 {
    reachable.push(index == left)
  }
  let mut changed = true
  while changed {
    changed = false
    for from = 0; from < sources.length(); from = from + 1 {
      if !reachable[from] {
        continue
      }
      for to = 0; to < sources.length(); to = to + 1 {
        if sources[from] == sources[to] &&
          starts[from] < ends[to] &&
          starts[to] < ends[from] &&
          !reachable[to] {
          reachable[to] = true
          changed = true
        }
      }
    }
  }
  reachable[right]
}
