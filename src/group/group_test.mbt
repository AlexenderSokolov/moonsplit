///|
test "multi-key components use the minimum id and ordered members" {
  let records = [
    @record.Record::new(
      "a",
      Some("b"),
      map_of([("speaker", "1"), ("source", "doc")]),
    ),
    @record.Record::new(
      "b",
      Some("c"),
      map_of([("speaker", "2"), ("source", "doc")]),
    ),
    @record.Record::new(
      "c",
      Some("a"),
      map_of([("speaker", "1"), ("source", "other")]),
    ),
  ]
  let result = build_components(records, ["speaker", "source"])
  assert_true(result is Ok(_))
  let components = match result {
    Ok(value) => value
    Err(_) => Components::new([])
  }
  assert_eq(components.count(), 1)
  let component = components.groups()[0]
  assert_eq(component.id(), "a")
  @test.assert_eq(component.member_ids(), ["a", "b", "c"])
  assert_eq(component.witness_edges().length(), 2)
}

///|
test "different key names do not merge equal values" {
  let records = [
    @record.Record::new("a", None, map_of([("speaker", "1"), ("source", "2")])),
    @record.Record::new("b", None, map_of([("speaker", "2"), ("source", "1")])),
  ]
  let result = build_components(records, ["speaker", "source"])
  let components = match result {
    Ok(value) => value
    Err(_) => Components::new([])
  }
  assert_eq(components.count(), 2)
}

///|
test "multi-key grouping preserves edges when the union root changes" {
  let records = [
    @record.Record::new(
      "r0",
      None,
      map_of([("speaker", "A"), ("source", "da0")]),
    ),
    @record.Record::new(
      "r1",
      None,
      map_of([("speaker", "B"), ("source", "da1")]),
    ),
    @record.Record::new("r2", None, map_of([("speaker", "B"), ("source", "X")])),
    @record.Record::new("r3", None, map_of([("speaker", "A"), ("source", "X")])),
  ]
  let result = build_components(records, ["speaker", "source"])
  let components = match result {
    Ok(value) => value
    Err(_) => Components::new([])
  }
  assert_eq(components.count(), 1)
  let component = components.groups()[0]
  assert_eq(component.id(), "r0")
  @test.assert_eq(component.member_ids(), ["r0", "r1", "r2", "r3"])
  assert_eq(component.witness_edges().length(), 3)
  let mut r1_edge_count = 0
  for edge in component.witness_edges() {
    if edge.left_id() == "r1" || edge.right_id() == "r1" {
      r1_edge_count = r1_edge_count + 1
    }
  }
  assert_eq(r1_edge_count, 1)
}

///|
test "witness edges are canonical for reversed input" {
  let forward = [
    @record.Record::new(
      "z",
      None,
      map_of([("speaker", "A"), ("source", "doc")]),
    ),
    @record.Record::new(
      "b",
      None,
      map_of([("speaker", "A"), ("source", "doc")]),
    ),
    @record.Record::new(
      "a",
      None,
      map_of([("speaker", "B"), ("source", "doc")]),
    ),
  ]
  let reversed : Array[@record.Record] = []
  for i = forward.length() - 1; i >= 0; i = i - 1 {
    reversed.push(forward[i])
  }
  let forward_components = match
    build_components(forward, ["speaker", "source"]) {
    Ok(value) => value
    Err(_) => @group.Components::new([])
  }
  let reversed_components = match
    build_components(reversed, ["speaker", "source"]) {
    Ok(value) => value
    Err(_) => @group.Components::new([])
  }
  assert_eq(reversed_components.count(), 1)
  let left = forward_components.groups()[0]
  let right = reversed_components.groups()[0]
  assert_eq(left.id(), right.id())
  @test.assert_eq(left.member_ids(), right.member_ids())
  assert_eq(left.witness_edges().length(), right.witness_edges().length())
  let left_edges = left.witness_edges()
  let right_edges = right.witness_edges()
  for i = 0; i < left_edges.length(); i = i + 1 {
    assert_eq(left_edges[i].left_id(), right_edges[i].left_id())
    assert_eq(left_edges[i].right_id(), right_edges[i].right_id())
    assert_eq(left_edges[i].key_name(), right_edges[i].key_name())
    assert_eq(left_edges[i].key_value(), right_edges[i].key_value())
  }
}

///|
fn map_of(entries : Array[(String, String)]) -> Map[String, String] {
  let map : Map[String, String] = Map([])
  for entry in entries {
    map[entry.0] = entry.1
  }
  map
}
