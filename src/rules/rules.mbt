///|
pub struct RuleWitness {
  priv left_id : String
  priv right_id : String
  priv rule_id : String
  priv rule_type : String
  priv detail : String
} derive(Debug)

///|
pub struct RuleComponent {
  priv id : String
  priv member_ids : Array[String]
  priv witness_edges : Array[RuleWitness]
} derive(Debug)

///|
pub struct RuleComponents {
  priv groups : Array[RuleComponent]
  priv text_candidate_count : Int
  priv text_comparison_count : Int
} derive(Debug)

///|
priv struct TextTokenSet {
  lexical : Array[String]
  ordered : Array[String]
}

///|
priv struct IntervalEntry {
  id : String
  source : String
  start : Int64
  end : Int64
}

///|
pub fn RuleWitness::new(
  left_id : String,
  right_id : String,
  rule_id : String,
  rule_type : String,
  detail : String,
) -> RuleWitness {
  if left_id <= right_id {
    { left_id, right_id, rule_id, rule_type, detail, }
  } else {
    { left_id: right_id, right_id: left_id, rule_id, rule_type, detail, }
  }
}

///|
pub fn RuleWitness::left_id(self : RuleWitness) -> String {
  self.left_id
}

///|
pub fn RuleWitness::right_id(self : RuleWitness) -> String {
  self.right_id
}

///|
pub fn RuleWitness::rule_id(self : RuleWitness) -> String {
  self.rule_id
}

///|
pub fn RuleWitness::rule_type(self : RuleWitness) -> String {
  self.rule_type
}

///|
pub fn RuleWitness::detail(self : RuleWitness) -> String {
  self.detail
}

///|
pub fn RuleComponent::new(
  id : String,
  member_ids : Array[String],
  witness_edges : Array[RuleWitness],
) -> RuleComponent {
  { id, member_ids: member_ids.copy(), witness_edges: witness_edges.copy(), }
}

///|
pub fn RuleComponent::id(self : RuleComponent) -> String {
  self.id
}

///|
pub fn RuleComponent::member_ids(self : RuleComponent) -> Array[String] {
  self.member_ids.copy()
}

///|
pub fn RuleComponent::size(self : RuleComponent) -> Int {
  self.member_ids.length()
}

///|
pub fn RuleComponent::witness_edges(self : RuleComponent) -> Array[RuleWitness] {
  self.witness_edges.copy()
}

///|
pub fn RuleComponents::new(
  groups : Array[RuleComponent],
  text_candidate_count : Int,
  text_comparison_count : Int,
) -> RuleComponents {
  { groups: groups.copy(), text_candidate_count, text_comparison_count, }
}

///|
pub fn RuleComponents::groups(self : RuleComponents) -> Array[RuleComponent] {
  self.groups.copy()
}

///|
pub fn RuleComponents::count(self : RuleComponents) -> Int {
  self.groups.length()
}

///|
pub fn RuleComponents::total_records(self : RuleComponents) -> Int {
  let mut total = 0
  for group in self.groups {
    total += group.size()
  }
  total
}

///|
pub fn RuleComponents::text_candidate_count(self : RuleComponents) -> Int {
  self.text_candidate_count
}

///|
pub fn RuleComponents::text_comparison_count(self : RuleComponents) -> Int {
  self.text_comparison_count
}

///|
pub fn build_rule_components(
  records : Array[@record.V2Record],
  rules : Array[@spec.LeakageRule],
) -> Result[RuleComponents, Array[@record.Issue]] {
  let sorted_records = records.copy()
  sorted_records.sort_by(compare_records)
  let sorted_rules = rules.copy()
  sorted_rules.sort_by((left, right) => left.id().lexical_compare(right.id()))
  let issues = validate_rule_component_inputs(sorted_records, sorted_rules)
  if issues.length() > 0 {
    return Err(issues)
  }
  let candidates : Array[RuleWitness] = []
  let mut text_candidate_count = 0
  let mut text_comparison_count = 0
  for rule in sorted_rules {
    match rule.kind() {
      ExactKey =>
        match exact_key_edges(sorted_records, rule) {
          Ok(edges) =>
            for edge in edges {
              candidates.push(edge)
            }
          Err(issues) => return Err(issues)
        }
      TextJaccard =>
        match text_jaccard_edges(sorted_records, rule) {
          Ok((edges, candidate_count, comparison_count)) => {
            for edge in edges {
              candidates.push(edge)
            }
            match
              add_text_evidence_count(
                text_candidate_count, candidate_count, "candidate",
              ) {
              Ok(next_count) => text_candidate_count = next_count
              Err(issues) => return Err(issues)
            }
            match
              add_text_evidence_count(
                text_comparison_count, comparison_count, "comparison",
              ) {
              Ok(next_count) => text_comparison_count = next_count
              Err(issues) => return Err(issues)
            }
          }
          Err(issues) => return Err(issues)
        }
      IntervalOverlap =>
        match interval_overlap_edges(sorted_records, rule) {
          Ok(edges) =>
            for edge in edges {
              candidates.push(edge)
            }
          Err(issues) => return Err(issues)
        }
    }
  }
  candidates.sort_by(compare_witnesses)
  let ids : Map[String, Int] = Map([])
  let parent : Array[Int] = []
  let sizes : Array[Int] = []
  for index = 0; index < sorted_records.length(); index = index + 1 {
    ids[sorted_records[index].id()] = index
    parent.push(index)
    sizes.push(1)
  }
  let forest : Array[RuleWitness] = []
  for edge in candidates {
    if union_by_size(parent, sizes, ids[edge.left_id()], ids[edge.right_id()]) {
      forest.push(edge)
    }
  }
  let members_by_root : Map[Int, Array[String]] = Map([])
  for index = 0; index < sorted_records.length(); index = index + 1 {
    let root = find_root(parent, index)
    match members_by_root.get(root) {
      Some(members) => members.push(sorted_records[index].id())
      None => members_by_root[root] = [sorted_records[index].id()]
    }
  }
  let witnesses_by_root : Map[Int, Array[RuleWitness]] = Map([])
  for edge in forest {
    let root = find_root(parent, ids[edge.left_id()])
    match witnesses_by_root.get(root) {
      Some(edges) => edges.push(edge)
      None => witnesses_by_root[root] = [edge]
    }
  }
  let groups : Array[RuleComponent] = []
  let added_roots : Map[Int, Bool] = Map([])
  for index = 0; index < sorted_records.length(); index = index + 1 {
    let root = find_root(parent, index)
    if added_roots.contains(root) {
      continue
    }
    added_roots[root] = true
    let members = members_by_root[root]
    members.sort_by((left, right) => left.lexical_compare(right))
    let edges = match witnesses_by_root.get(root) {
      Some(value) => value.copy()
      None => []
    }
    edges.sort_by(compare_witnesses)
    groups.push(RuleComponent::new(members[0], members, edges))
  }
  groups.sort_by((left, right) => left.id().lexical_compare(right.id()))
  Ok(RuleComponents::new(groups, text_candidate_count, text_comparison_count))
}

///|
fn add_text_evidence_count(
  current : Int,
  increment : Int,
  field : String,
) -> Result[Int, Array[@record.Issue]] {
  // Public evidence counters use portable MoonBit `Int`. Reject a corpus or
  // rule set that would overflow them instead of letting a dense candidate
  // join wrap its count silently on wasm-gc.
  if current < 0 || increment < 0 || increment > 2147483647 - current {
    return Err([
      @record.Issue::error(
        "text_count_overflow",
        "text \{field} evidence count exceeds 2147483647; split the corpus or reduce text rules",
      ),
    ])
  }
  Ok(current + increment)
}

///|
test "text evidence counters reject overflow rather than wrapping" {
  match add_text_evidence_count(2147483647, 1, "candidate") {
    Ok(_) => assert_true(false)
    Err(issues) => assert_true(issues[0].code() == "text_count_overflow")
  }
  match add_text_evidence_count(2147483646, 1, "comparison") {
    Ok(value) => assert_true(value == 2147483647)
    Err(_) => assert_true(false)
  }
}

///|
fn validate_rule_component_inputs(
  records : Array[@record.V2Record],
  rules : Array[@spec.LeakageRule],
) -> Array[@record.Issue] {
  let issues : Array[@record.Issue] = []
  if records.length() == 0 {
    issues.push(@record.Issue::error("empty_records", "record list is empty"))
  }
  if rules.length() == 0 {
    issues.push(
      @record.Issue::error("missing_rules", "rules must be a non-empty array"),
    )
  }
  let ids : Map[String, Bool] = Map([])
  for record in records {
    let id = record.id()
    if id == "" {
      issues.push(
        @record.Issue::error("empty_record_id", "record id cannot be empty"),
      )
    } else if ids.contains(id) {
      issues.push(
        @record.Issue::error(
          "duplicate_record_id",
          "duplicate record id: \{id}",
        ),
      )
    } else {
      ids[id] = true
    }
    // Parsed JSON rejects these already, but public constructors intentionally
    // remain backwards-compatible.  Validate every named interval here so no
    // public planning or audit entry can bypass CLI-level record checks by
    // supplying a constructor-built record with an unrelated bad interval.
    let intervals = record.intervals()
    let interval_names : Array[String] = []
    for name in intervals.keys() {
      interval_names.push(name)
    }
    interval_names.sort_by((left, right) => left.lexical_compare(right))
    for name in interval_names {
      if name == "" {
        issues.push(
          @record.Issue::error(
            "empty_interval_name",
            "record \{id} has an empty interval name",
          ),
        )
      } else {
        let interval = intervals[name]
        if interval.start() >= interval.end() {
          issues.push(
            @record.Issue::error(
              "invalid_interval_bounds",
              "record \{id} interval \{name} must satisfy start < end",
            ),
          )
        }
      }
    }
  }
  let rule_ids : Map[String, Bool] = Map([])
  for rule in rules {
    let id = rule.id()
    if id == "" {
      issues.push(
        @record.Issue::error("invalid_rule_id", "rule id cannot be empty"),
      )
    } else if rule_ids.contains(id) {
      issues.push(
        @record.Issue::error("duplicate_rule_id", "duplicate rule id: \{id}"),
      )
    } else {
      rule_ids[id] = true
    }
  }
  issues
}

///|
fn exact_key_edges(
  records : Array[@record.V2Record],
  rule : @spec.LeakageRule,
) -> Result[Array[RuleWitness], Array[@record.Issue]] {
  let key = match rule.key() {
    Some(value) if value != "" => value
    _ =>
      return Err([
        @record.Issue::error(
          "invalid_rule_key", "exact_key rule requires a key",
        ),
      ])
  }
  let buckets : Map[String, Int] = Map([])
  let edges : Array[RuleWitness] = []
  for index = 0; index < records.length(); index = index + 1 {
    let record = records[index]
    let value = match record.key(key) {
      Some(value) if value != "" => value
      Some(_) =>
        return Err([
          @record.Issue::error(
            "empty_rule_key",
            "record \{record.id()} has empty key \{key}",
          ),
        ])
      None =>
        return Err([
          @record.Issue::error(
            "missing_rule_key",
            "record \{record.id()} is missing key \{key}",
          ),
        ])
    }
    match buckets.get(value) {
      None => buckets[value] = index
      Some(first) =>
        edges.push(
          RuleWitness::new(
            records[first].id(),
            record.id(),
            rule.id(),
            "exact_key",
            "key=\{key};value=\{value}",
          ),
        )
    }
  }
  Ok(edges)
}

///|
fn text_jaccard_edges(
  records : Array[@record.V2Record],
  rule : @spec.LeakageRule,
) -> Result[(Array[RuleWitness], Int, Int), Array[@record.Issue]] {
  let q = rule.q()
  let threshold_bp = rule.threshold_bp()
  if q <= 0 {
    return Err([
      @record.Issue::error(
        "invalid_text_q", "text q must be a positive integer",
      ),
    ])
  }
  if threshold_bp < 1 || threshold_bp > 10000 {
    return Err([
      @record.Issue::error(
        "invalid_text_threshold_bp", "text threshold_bp must be between 1 and 10000",
      ),
    ])
  }
  let lexical_tokens : Array[Array[String]] = []
  for record in records {
    let text = match record.text() {
      Some(value) => value
      None =>
        return Err([
          @record.Issue::error(
            "missing_text",
            "record \{record.id()} is missing text for rule \{rule.id()}",
          ),
        ])
    }
    let tokens = qgrams(text, q)
    if tokens.length() == 0 {
      return Err([
        @record.Issue::error(
          "empty_text",
          "record \{record.id()} has empty normalized text for rule \{rule.id()}",
        ),
      ])
    }
    lexical_tokens.push(tokens)
  }
  let token_frequency : Map[String, Int] = Map([])
  for tokens in lexical_tokens {
    for token in tokens {
      token_frequency[token] = token_frequency.get(token).unwrap_or(0) + 1
    }
  }
  let all_tokens : Array[String] = []
  let added_tokens : Map[String, Bool] = Map([])
  for tokens in lexical_tokens {
    for token in tokens {
      if !added_tokens.contains(token) {
        added_tokens[token] = true
        all_tokens.push(token)
      }
    }
  }
  all_tokens.sort_by((left, right) => {
    let left_frequency = token_frequency[left]
    let right_frequency = token_frequency[right]
    if left_frequency < right_frequency {
      -1
    } else if left_frequency > right_frequency {
      1
    } else {
      left.lexical_compare(right)
    }
  })
  let token_rank : Map[String, Int] = Map([])
  for index = 0; index < all_tokens.length(); index = index + 1 {
    token_rank[all_tokens[index]] = index
  }
  let token_sets : Array[TextTokenSet] = []
  for lexical in lexical_tokens {
    let ordered = lexical.copy()
    ordered.sort_by((left, right) => {
      let left_rank = token_rank[left]
      let right_rank = token_rank[right]
      if left_rank < right_rank {
        -1
      } else if left_rank > right_rank {
        1
      } else {
        left.lexical_compare(right)
      }
    })
    token_sets.push({ lexical, ordered, })
  }
  let inverted : Map[String, Array[Int]] = Map([])
  let candidate_set : Map[(Int, Int), Bool] = Map([])
  let mut candidate_count = 0
  for current = 0; current < token_sets.length(); current = current + 1 {
    let current_set = token_sets[current]
    let prefix_length = jaccard_prefix_length(
      current_set.ordered.length(),
      threshold_bp,
    )
    for position = 0; position < prefix_length; position = position + 1 {
      let token = current_set.ordered[position]
      match inverted.get(token) {
        Some(previous_indices) =>
          for previous in previous_indices {
            if jaccard_length_compatible(
                token_sets[previous].lexical.length(),
                current_set.lexical.length(),
                threshold_bp,
              ) {
              let pair = (previous, current)
              if !candidate_set.contains(pair) {
                match add_text_evidence_count(candidate_count, 1, "candidate") {
                  Ok(next_count) => {
                    candidate_set[pair] = true
                    candidate_count = next_count
                  }
                  Err(issues) => return Err(issues)
                }
              }
            }
          }
        None => ()
      }
      match inverted.get(token) {
        Some(indices) => indices.push(current)
        None => inverted[token] = [current]
      }
    }
  }
  let candidate_pairs : Array[(Int, Int)] = []
  for pair in candidate_set.keys() {
    candidate_pairs.push(pair)
  }
  candidate_pairs.sort_by((left, right) => {
    if left.0 < right.0 {
      -1
    } else if left.0 > right.0 {
      1
    } else if left.1 < right.1 {
      -1
    } else if left.1 > right.1 {
      1
    } else {
      0
    }
  })
  let edges : Array[RuleWitness] = []
  for pair in candidate_pairs {
    let left = token_sets[pair.0].lexical
    let right = token_sets[pair.1].lexical
    let intersection = token_intersection_count(left, right)
    let union = left.length() + right.length() - intersection
    if jaccard_matches(intersection, union, threshold_bp) {
      edges.push(
        RuleWitness::new(
          records[pair.0].id(),
          records[pair.1].id(),
          rule.id(),
          "text_jaccard",
          "q=\{q};threshold_bp=\{threshold_bp};intersection=\{intersection};union=\{union}",
        ),
      )
    }
  }
  Ok((edges, candidate_count, candidate_count))
}

///|
fn interval_overlap_edges(
  records : Array[@record.V2Record],
  rule : @spec.LeakageRule,
) -> Result[Array[RuleWitness], Array[@record.Issue]] {
  let source_key = match rule.source_key() {
    Some(value) if value != "" => value
    _ =>
      return Err([
        @record.Issue::error(
          "invalid_rule_source_key", "interval_overlap rule requires source_key",
        ),
      ])
  }
  let interval_name = match rule.interval() {
    Some(value) if value != "" => value
    _ =>
      return Err([
        @record.Issue::error(
          "invalid_rule_interval", "interval_overlap rule requires interval",
        ),
      ])
  }
  let entries : Array[IntervalEntry] = []
  for index = 0; index < records.length(); index = index + 1 {
    let record = records[index]
    let source = match record.key(source_key) {
      Some(value) if value != "" => value
      Some(_) =>
        return Err([
          @record.Issue::error(
            "empty_rule_source_key",
            "record \{record.id()} has empty source key \{source_key}",
          ),
        ])
      None =>
        return Err([
          @record.Issue::error(
            "missing_rule_source_key",
            "record \{record.id()} is missing source key \{source_key}",
          ),
        ])
    }
    let interval = match record.interval(interval_name) {
      Some(value) => value
      None =>
        return Err([
          @record.Issue::error(
            "missing_rule_interval",
            "record \{record.id()} is missing interval \{interval_name}",
          ),
        ])
    }
    if interval.start() >= interval.end() {
      return Err([
        @record.Issue::error(
          "invalid_interval_bounds",
          "record \{record.id()} interval \{interval_name} must satisfy start < end",
        ),
      ])
    }
    entries.push({
      id: record.id(),
      source,
      start: interval.start(),
      end: interval.end(),
    })
  }
  entries.sort_by(compare_interval_entries)
  let edges : Array[RuleWitness] = []
  let mut active_source = ""
  let mut has_active_source = false
  let mut representative : IntervalEntry? = None
  for entry in entries {
    if !has_active_source || entry.source != active_source {
      active_source = entry.source
      has_active_source = true
      representative = None
    }
    match representative {
      None => representative = Some(entry)
      Some(previous) =>
        // `previous` is the scanned interval with the greatest end in this
        // source component.  A single overlapping edge preserves connectivity;
        // the exported witness remains an explanation forest rather than all
        // pairwise intersections.
        if previous.end > entry.start {
          edges.push(
            RuleWitness::new(
              previous.id,
              entry.id,
              rule.id(),
              "interval_overlap",
              "source_key=\{source_key};source=\{entry.source};interval=\{interval_name}",
            ),
          )
          if entry.end > previous.end {
            representative = Some(entry)
          }
        } else {
          representative = Some(entry)
        }
    }
  }
  Ok(edges)
}

///|
fn qgrams(text : String, q : Int) -> Array[String] {
  let chars : Array[Char] = []
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
      if pending_space && chars.length() > 0 {
        chars.push(' ')
      }
      chars.push(ch.to_ascii_lowercase())
      pending_space = false
    }
  }
  let tokens : Array[String] = []
  if chars.length() == 0 {
    return tokens
  }
  if chars.length() < q {
    tokens.push(chars_to_string(chars, 0, chars.length()))
  } else {
    for start = 0; start <= chars.length() - q; start = start + 1 {
      tokens.push(chars_to_string(chars, start, start + q))
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
  result.sort_by((left, right) => left.lexical_compare(right))
  result
}

///|
fn chars_to_string(chars : Array[Char], start : Int, end : Int) -> String {
  let builder = StringBuilder()
  for index = start; index < end; index = index + 1 {
    builder.write_char(chars[index])
  }
  builder.to_string()
}

///|
fn jaccard_prefix_length(size : Int, threshold_bp : Int) -> Int {
  // `ceil(threshold_bp * size / 10000)` is the PPJoin prefix bound.
  // Split the product before multiplication: both `threshold_bp * remainder`
  // and `threshold_bp * quotient` stay in Int range even when `size` is the
  // largest representable record-local token count.
  let quotient = size / 10000
  let remainder = size % 10000
  let whole = threshold_bp * quotient
  let fractional = (threshold_bp * remainder + 9999) / 10000
  size - (whole + fractional) + 1
}

///|
fn jaccard_length_compatible(
  left_size : Int,
  right_size : Int,
  threshold_bp : Int,
) -> Bool {
  let smaller = if left_size < right_size { left_size } else { right_size }
  let larger = if left_size > right_size { left_size } else { right_size }
  @bigint.BigInt::from_int(smaller) * @bigint.BigInt::from_int(10000) >=
  @bigint.BigInt::from_int(threshold_bp) * @bigint.BigInt::from_int(larger)
}

///|
fn token_intersection_count(left : Array[String], right : Array[String]) -> Int {
  let mut left_index = 0
  let mut right_index = 0
  let mut count = 0
  while left_index < left.length() && right_index < right.length() {
    let comparison = compare_strings(left[left_index], right[right_index])
    if comparison == 0 {
      count += 1
      left_index += 1
      right_index += 1
    } else if comparison < 0 {
      left_index += 1
    } else {
      right_index += 1
    }
  }
  count
}

///|
fn jaccard_matches(intersection : Int, union : Int, threshold_bp : Int) -> Bool {
  @bigint.BigInt::from_int(intersection) * @bigint.BigInt::from_int(10000) >=
  @bigint.BigInt::from_int(threshold_bp) * @bigint.BigInt::from_int(union)
}

///|
fn compare_records(left : @record.V2Record, right : @record.V2Record) -> Int {
  left.id().lexical_compare(right.id())
}

///|
fn compare_interval_entries(left : IntervalEntry, right : IntervalEntry) -> Int {
  let source_comparison = compare_strings(left.source, right.source)
  if source_comparison != 0 {
    return left.source.lexical_compare(right.source)
  }
  if left.start < right.start {
    return -1
  }
  if left.start > right.start {
    return 1
  }
  if left.end < right.end {
    return -1
  }
  if left.end > right.end {
    return 1
  }
  left.id.lexical_compare(right.id)
}

///|
fn compare_witnesses(left : RuleWitness, right : RuleWitness) -> Int {
  let pairs = [
    (left.rule_id(), right.rule_id()),
    (left.rule_type(), right.rule_type()),
    (left.detail(), right.detail()),
    (left.left_id(), right.left_id()),
    (left.right_id(), right.right_id()),
  ]
  for pair in pairs {
    let comparison = pair.0.lexical_compare(pair.1)
    if comparison != 0 {
      return comparison
    }
  }
  0
}

///|
fn compare_strings(left : String, right : String) -> Int {
  if left < right {
    -1
  } else if left > right {
    1
  } else {
    0
  }
}

///|
fn find_root(parent : Array[Int], index : Int) -> Int {
  let mut root = index
  while parent[root] != root {
    root = parent[root]
  }
  let mut current = index
  while parent[current] != current {
    let next = parent[current]
    parent[current] = root
    current = next
  }
  root
}

///|
fn union_by_size(
  parent : Array[Int],
  sizes : Array[Int],
  left : Int,
  right : Int,
) -> Bool {
  let left_root = find_root(parent, left)
  let right_root = find_root(parent, right)
  if left_root == right_root {
    return false
  }
  if sizes[left_root] > sizes[right_root] ||
    (sizes[left_root] == sizes[right_root] && left_root < right_root) {
    parent[right_root] = left_root
    sizes[left_root] += sizes[right_root]
  } else {
    parent[left_root] = right_root
    sizes[right_root] += sizes[left_root]
  }
  true
}
