///|
pub struct RelationEdge {
  priv left_id : String
  priv right_id : String
  priv key_name : String
  priv key_value : String
} derive(Debug)

///|
pub struct Component {
  priv id : String
  priv member_ids : Array[String]
  priv witness_edges : Array[RelationEdge]
} derive(Debug)

///|
pub struct Components {
  priv groups : Array[Component]
} derive(Debug)

///|
pub fn RelationEdge::left_id(self : RelationEdge) -> String {
  self.left_id
}

///|
pub fn RelationEdge::right_id(self : RelationEdge) -> String {
  self.right_id
}

///|
pub fn RelationEdge::key_name(self : RelationEdge) -> String {
  self.key_name
}

///|
pub fn RelationEdge::key_value(self : RelationEdge) -> String {
  self.key_value
}

///|
fn normalize_edge(edge : RelationEdge) -> RelationEdge {
  if edge.left_id() <= edge.right_id() {
    edge
  } else {
    RelationEdge::new(
      edge.right_id(),
      edge.left_id(),
      edge.key_name(),
      edge.key_value(),
    )
  }
}

///|
fn compare_edges(left : RelationEdge, right : RelationEdge) -> Int {
  let comparisons = [
    (left.key_name(), right.key_name()),
    (left.key_value(), right.key_value()),
    (left.left_id(), right.left_id()),
    (left.right_id(), right.right_id()),
  ]
  for pair in comparisons {
    let comparison = pair.0.lexical_compare(pair.1)
    if comparison != 0 {
      return comparison
    }
  }
  0
}

///|
pub fn Component::id(self : Component) -> String {
  self.id
}

///|
pub fn Component::member_ids(self : Component) -> Array[String] {
  self.member_ids.copy()
}

///|
/// Number of records contained in this component.
pub fn Component::size(self : Component) -> Int {
  self.member_ids.length()
}

///|
pub fn Component::witness_edges(self : Component) -> Array[RelationEdge] {
  self.witness_edges.copy()
}

///|
pub fn Components::groups(self : Components) -> Array[Component] {
  self.groups.copy()
}

///|
pub fn Components::count(self : Components) -> Int {
  self.groups.length()
}

///|
/// Number of records across all components.
pub fn Components::total_records(self : Components) -> Int {
  let mut total = 0
  for group in self.groups {
    total += group.size()
  }
  total
}

///|
/// Largest component, breaking ties by the lexicographically smallest id.
pub fn Components::largest(self : Components) -> Component? {
  let mut largest : Component? = None
  for group in self.groups {
    match largest {
      None => largest = Some(group)
      Some(current) =>
        if group.size() > current.size() ||
          (
            group.size() == current.size() &&
            group.id().lexical_compare(current.id()) < 0
          ) {
          largest = Some(group)
        }
    }
  }
  largest
}

///|
pub fn RelationEdge::new(
  left_id : String,
  right_id : String,
  key_name : String,
  key_value : String,
) -> RelationEdge {
  { left_id, right_id, key_name, key_value, }
}

///|
pub fn Component::new(
  id : String,
  member_ids : Array[String],
  witness_edges : Array[RelationEdge],
) -> Component {
  { id, member_ids: member_ids.copy(), witness_edges: witness_edges.copy(), }
}

///|
pub fn Component::add_member(self : Component, id : String) -> Unit {
  self.member_ids.push(id)
}

///|
pub fn Components::new(groups : Array[Component]) -> Components {
  { groups: groups.copy(), }
}

///|
pub fn build_components(
  records : Array[@record.Record],
  isolation_keys : Array[String],
) -> Result[Components, Array[@record.Issue]] {
  let issues : Array[@record.Issue] = []
  let ids : Map[String, Int] = Map([])
  for index = 0; index < records.length(); index = index + 1 {
    let id = records[index].id()
    match ids.get(id) {
      Some(_) =>
        issues.push(
          @record.Issue::error(
            "duplicate_record_id",
            "duplicate record id: \{id}",
          ),
        )
      None => ids[id] = index
    }
    for key in isolation_keys {
      match records[index].key(key) {
        None =>
          issues.push(
            @record.Issue::error(
              "missing_isolation_key",
              "record \{id} is missing isolation key \{key}",
            ),
          )
        Some(value) =>
          if value == "" {
            issues.push(
              @record.Issue::error(
                "empty_isolation_key",
                "record \{id} has empty isolation key \{key}",
              ),
            )
          }
      }
    }
  }
  if issues.length() > 0 {
    return Err(issues)
  }
  let parent : Array[Int] = []
  let sizes : Array[Int] = []
  for i = 0; i < records.length(); i = i + 1 {
    parent.push(i)
    sizes.push(1)
  }
  let witness_edges : Array[RelationEdge] = []
  let buckets : Map[(String, String), Int] = Map([])
  for record in sorted_records(records) {
    for key_name in isolation_keys {
      let key_value = record.key(key_name).unwrap_or("")
      let bucket_key = (key_name, key_value)
      match buckets.get(bucket_key) {
        Some(other) => {
          let right_index = other
          let right_record = records[right_index]
          if union(parent, sizes, ids[record.id()], ids[right_record.id()]) {
            let edge = RelationEdge::new(
              record.id(),
              right_record.id(),
              key_name,
              key_value,
            )
            witness_edges.push(edge)
          }
        }
        None => buckets[bucket_key] = ids[record.id()]
      }
    }
  }
  let edges_by_root : Map[Int, Array[RelationEdge]] = Map([])
  for edge in witness_edges {
    let root = find(parent, ids[edge.left_id()])
    match edges_by_root.get(root) {
      Some(edges) => edges.push(edge)
      None => edges_by_root[root] = [edge]
    }
  }
  let roots : Map[Int, Component] = Map([])
  for record in sorted_records(records) {
    let root = find(parent, ids[record.id()])
    match roots.get(root) {
      Some(group) => group.add_member(record.id())
      None => {
        let members : Array[String] = [record.id()]
        let edges = match edges_by_root.get(root) {
          Some(value) => value
          None => []
        }
        let component = Component::new(record.id(), members, edges)
        roots[root] = component
      }
    }
  }
  let groups : Array[Component] = []
  for group in roots.values() {
    let member_ids = group.member_ids()
    member_ids.sort_by((left, right) => left.lexical_compare(right))
    groups.push(
      Component::new(member_ids[0], member_ids, group.witness_edges()),
    )
  }
  groups.sort_by((a, b) => a.id().lexical_compare(b.id()))
  for index = 0; index < groups.length(); index = index + 1 {
    let group = groups[index]
    let edges = group.witness_edges()
    for i = 0; i < edges.length(); i = i + 1 {
      edges[i] = normalize_edge(edges[i])
    }
    edges.sort_by(compare_edges)
    groups[index] = Component::new(group.id(), group.member_ids(), edges)
  }
  Ok(Components::new(groups))
}

///|
fn sorted_records(records : Array[@record.Record]) -> Array[@record.Record] {
  let sorted = records.copy()
  sorted.sort_by((left, right) => left.id().lexical_compare(right.id()))
  sorted
}

///|
fn find(parent : Array[Int], x : Int) -> Int {
  let mut root = x
  while parent[root] != root {
    root = parent[root]
  }
  let mut node = x
  while parent[node] != node {
    let next = parent[node]
    parent[node] = root
    node = next
  }
  root
}

///|
fn union(parent : Array[Int], sizes : Array[Int], a : Int, b : Int) -> Bool {
  let ra = find(parent, a)
  let rb = find(parent, b)
  if ra == rb {
    return false
  }
  if sizes[ra] > sizes[rb] || (sizes[ra] == sizes[rb] && ra < rb) {
    parent[rb] = ra
    sizes[ra] = sizes[ra] + sizes[rb]
  } else {
    parent[ra] = rb
    sizes[rb] = sizes[rb] + sizes[ra]
  }
  true
}
