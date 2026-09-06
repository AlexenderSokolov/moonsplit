///|
pub fn plan_json(plan : @plan.SplitPlan) -> String {
  let out = StringBuilder()
  out <+ "{\n"
  out <+ "  \"schema_version\": 1,\n"
  out <+ "  \"algorithm\": \"group-greedy-v1\",\n"
  out <+ "  \"kind\": \"\{kind_name(plan.kind())}\",\n"
  out <+ "  \"seed\": \{plan.seed()},\n"
  out <+ "  \"isolation_keys\": \{json_string_array(plan.isolation_keys())},\n"
  out <+ "  \"balance_labels\": \{plan.balance_labels()},\n"
  out <+ "  \"ratio_tolerance_bp\": \{plan.ratio_tolerance_bp()},\n"
  out <+ "  \"partitions\": ["
  let partitions = plan.partition_weights()
  if partitions.length() == 0 {
    out <+ "],\n"
  } else {
    out <+ "\n"
    for index = 0; index < partitions.length(); index = index + 1 {
      out <+
        "    {\"name\": \"\{escape_json(partitions[index].name())}\", \"weight\": \{partitions[index].weight()}}"
      if index + 1 < partitions.length() {
        out <+ ","
      }
      out <+ "\n"
    }
    out <+ "  ],\n"
  }
  out <+ "  \"k\": \{plan.k()},\n"
  out <+ "  \"component_count\": \{plan.components().count()},\n"
  out <+ "  \"assignment_count\": \{plan.assignments().length()},\n"
  out <+ "  \"warnings\": \{json_string_array(plan.warnings())}\n"
  out <+ "}"
  out.to_string()
}

///|
pub fn assignments_jsonl(plan : @plan.SplitPlan) -> String {
  let assignments = plan.assignments()
  let out = StringBuilder()
  for index = 0; index < assignments.length(); index = index + 1 {
    if index > 0 {
      out <+ "\n"
    }
    out <+
      "{\"id\": \"\{escape_json(assignments[index].id())}\", \"partition\": \"\{escape_json(assignments[index].partition())}\"}"
  }
  out.to_string()
}

///|
pub fn components_jsonl(plan : @plan.SplitPlan) -> String {
  let components = plan.components().groups()
  let out = StringBuilder()
  for index = 0; index < components.length(); index = index + 1 {
    if index > 0 {
      out <+ "\n"
    }
    let component = components[index]
    out <+
      "{\"id\": \"\{escape_json(component.id())}\", \"member_ids\": \{json_string_array(component.member_ids())}, \"witness_edges\": ["
    let edges = component.witness_edges()
    for edge_index = 0; edge_index < edges.length(); edge_index = edge_index + 1 {
      if edge_index > 0 {
        out <+ ", "
      }
      let edge = edges[edge_index]
      out <+
        "{\"left_id\": \"\{escape_json(edge.left_id())}\", \"right_id\": \"\{escape_json(edge.right_id())}\", \"key_name\": \"\{escape_json(edge.key_name())}\", \"key_value\": \"\{escape_json(edge.key_value())}\"}"
    }
    out <+ "]}"
  }
  out.to_string()
}

///|
pub fn report_markdown(plan : @plan.SplitPlan) -> String {
  let out = StringBuilder()
  out <+ "# MoonSplit Audit Report\n\n"
  out <+ "- Algorithm: `group-greedy-v1`\n"
  out <+ "- Kind: `\{kind_name(plan.kind())}`\n"
  out <+ "- Seed: `\{plan.seed()}`\n"
  out <+ "- Isolation keys: \{markdown_code_list(plan.isolation_keys())}\n"
  out <+ "- Components: \{plan.components().count()}\n"
  out <+ "- Assignments: \{plan.assignments().length()}\n\n"
  out <+ "## Partitions\n\n"
  out <+ "| Partition | Weight | Records |\n"
  out <+ "|---|---:|---:|\n"
  let counts = partition_counts(plan)
  for partition in plan.partition_weights() {
    let count = match counts.get(partition.name()) {
      Some(value) => value
      None => 0
    }
    out <+ "| `\{partition.name()}` | \{partition.weight()} | \{count} |\n"
  }
  out <+ "\n## Warnings\n\n"
  let warnings = plan.warnings()
  if warnings.length() == 0 {
    out <+ "None.\n"
  } else {
    for warning in warnings {
      out <+ "- \{warning}\n"
    }
  }
  out.to_string()
}

///|
fn partition_counts(plan : @plan.SplitPlan) -> Map[String, Int] {
  let counts : Map[String, Int] = Map([])
  for partition in plan.partition_weights() {
    counts[partition.name()] = 0
  }
  for assignment in plan.assignments() {
    match counts.get(assignment.partition()) {
      Some(count) => counts[assignment.partition()] = count + 1
      None => counts[assignment.partition()] = 1
    }
  }
  counts
}

///|
fn kind_name(kind : @spec.SplitKind) -> String {
  match kind {
    Holdout => "holdout"
    KFold => "kfold"
  }
}

///|
fn json_string_array(values : Array[String]) -> String {
  let out = StringBuilder()
  out <+ "["
  for index = 0; index < values.length(); index = index + 1 {
    if index > 0 {
      out <+ ", "
    }
    out <+ "\"\{escape_json(values[index])}\""
  }
  out <+ "]"
  out.to_string()
}

///|
fn markdown_code_list(values : Array[String]) -> String {
  let out = StringBuilder()
  for index = 0; index < values.length(); index = index + 1 {
    if index > 0 {
      out <+ ", "
    }
    out <+ "`\{values[index]}`"
  }
  out.to_string()
}

///|
fn escape_json(value : String) -> String {
  let out = StringBuilder()
  for ch in value {
    match ch {
      '"' => out <+ "\\\""
      '\\' => out <+ "\\\\"
      '\n' => out <+ "\\n"
      '\r' => out <+ "\\r"
      '\t' => out <+ "\\t"
      _ => {
        let code = ch.to_int()
        if code < 32 {
          let hex = code.to_string(radix=16).pad_start(4, '0')
          out <+ "\\u\{hex}"
        } else {
          out <+ "\{ch}"
        }
      }
    }
  }
  out.to_string()
}
