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
/// Stable machine-readable summary including component and label diagnostics.
pub fn summary_json(plan : @plan.SplitPlan) -> String {
  let out = StringBuilder()
  out <+ "{\n"
  out <+ "  \"schema_version\": 1,\n"
  out <+ "  \"algorithm\": \"group-greedy-v1\",\n"
  out <+ "  \"records\": \{plan.components().total_records()},\n"
  out <+ "  \"components\": \{plan.components().count()},\n"
  match plan.components().largest() {
    Some(component) =>
      out <+
        "  \"largest_component\": {\"id\": \"\{escape_json(component.id())}\", \"size\": \{component.size()}},\n"
    None => out <+ "  \"largest_component\": null,\n"
  }
  out <+ "  \"partitions\": [\n"
  let summaries = plan.summaries()
  for index = 0; index < summaries.length(); index = index + 1 {
    let summary = summaries[index]
    out <+
      "    {\"name\": \"\{escape_json(summary.name())}\", \"weight\": \{summary.weight()}, \"record_count\": \{summary.record_count()}, \"target_bp\": \{summary.target_bp()}, \"actual_bp\": \{summary.actual_bp()}, \"deviation_bp\": \{summary.deviation_bp()}, \"label_counts\": \{json_int_map(summary.label_counts())}, \"unlabeled_count\": \{summary.unlabeled_count()}}"
    if index + 1 < summaries.length() {
      out <+ ","
    }
    out <+ "\n"
  }
  out <+ "  ]\n"
  out <+ "}"
  out.to_string()
}

///|
/// Stable machine-readable representation of an independent audit result.
pub fn audit_report_json(
  report : @audit.AuditReport,
  spec : @spec.SplitSpec,
  record_count : Int,
  assignment_count : Int,
) -> String {
  let out = StringBuilder()
  out <+ "{\n"
  out <+ "  \"schema_version\": 1,\n"
  out <+ "  \"valid\": \{report.is_valid()},\n"
  out <+ "  \"records\": \{record_count},\n"
  out <+ "  \"assignments\": \{assignment_count},\n"
  out <+ "  \"partition_counts\": {\n"
  let counts = report.partition_counts()
  let names = spec.partition_names()
  let declared : Map[String, Bool] = Map([])
  for name in names {
    declared[name] = true
  }
  let unknown : Array[String] = []
  for name in counts.keys() {
    if !declared.contains(name) {
      unknown.push(name)
    }
  }
  unknown.sort_by(compare_strings)
  let all_names = names.copy()
  for name in unknown {
    all_names.push(name)
  }
  for index = 0; index < all_names.length(); index = index + 1 {
    let name = all_names[index]
    let count = match counts.get(name) {
      Some(value) => value
      None => 0
    }
    out <+ "    \"\{escape_json(name)}\": \{count}"
    if index + 1 < all_names.length() {
      out <+ ","
    }
    out <+ "\n"
  }
  out <+ "  },\n"
  out <+ "  \"issues\": ["
  let issues = report.issues()
  if issues.length() > 0 {
    out <+ "\n"
    for index = 0; index < issues.length(); index = index + 1 {
      let issue = issues[index]
      let severity = match issue.severity() {
        Error => "error"
        Warning => "warning"
      }
      let line = match issue.line() {
        Some(value) => value.to_string()
        None => "null"
      }
      out <+
        "    {\"severity\": \"\{severity}\", \"code\": \"\{escape_json(issue.code())}\", \"message\": \"\{escape_json(issue.message())}\", \"line\": \{line}}"
      if index + 1 < issues.length() {
        out <+ ","
      }
      out <+ "\n"
    }
    out <+ "  ]\n"
  } else {
    out <+ "]\n"
  }
  out <+ "}"
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
  out <+
    "| Partition | Weight | Target (bp) | Actual (bp) | Deviation (bp) | Records |\n"
  out <+ "|---|---:|---:|---:|---:|---:|\n"
  for summary in plan.summaries() {
    out <+
      "| `\{summary.name()}` | \{summary.weight()} | \{summary.target_bp()} | \{summary.actual_bp()} | \{summary.deviation_bp()} | \{summary.record_count()} |\n"
  }
  out <+ "\n## Labels\n\n"
  out <+ "| Partition | Label counts | Unlabeled |\n"
  out <+ "|---|---|---:|\n"
  for summary in plan.summaries() {
    out <+
      "| `\{summary.name()}` | \{markdown_label_counts(summary.label_counts())} | \{summary.unlabeled_count()} |\n"
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
/// Serialize a string-to-integer map with sorted keys.
fn json_int_map(values : Map[String, Int]) -> String {
  let keys : Array[String] = []
  for key in values.keys() {
    keys.push(key)
  }
  keys.sort_by(compare_strings)
  let out = StringBuilder()
  out <+ "{"
  for index = 0; index < keys.length(); index = index + 1 {
    if index > 0 {
      out <+ ", "
    }
    let key = keys[index]
    out <+ "\"{escape_json(key)}\": \{values[key]}"
  }
  out <+ "}"
  out.to_string()
}

///|
/// Render label counts in stable key order for the Markdown report.
fn markdown_label_counts(values : Map[String, Int]) -> String {
  let keys : Array[String] = []
  for key in values.keys() {
    keys.push(key)
  }
  keys.sort_by(compare_strings)
  if keys.length() == 0 {
    "None"
  } else {
    let out = StringBuilder()
    for index = 0; index < keys.length(); index = index + 1 {
      if index > 0 {
        out <+ ", "
      }
      let key = keys[index]
      out <+ "`\{key}`=\{values[key]}"
    }
    out.to_string()
  }
}

///|
/// Lexicographic comparator shared by stable export orderings.
fn compare_strings(left : String, right : String) -> Int {
  left.lexical_compare(right)
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
