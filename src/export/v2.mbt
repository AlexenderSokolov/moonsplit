///|
pub fn rule_plan_json(plan : @plan.RuleSplitPlan) -> String {
  let out = StringBuilder()
  out <+ "{\n"
  out <+ "  \"schema_version\": 2,\n"
  out <+ "  \"algorithm\": \"\{plan.algorithm()}\",\n"
  out <+ "  \"kind\": \"\{v2_kind_name(plan.kind())}\",\n"
  out <+ "  \"seed\": \{plan.seed()},\n"
  out <+ "  \"balance_labels\": \{plan.balance_labels()},\n"
  out <+ "  \"ratio_tolerance_bp\": \{plan.ratio_tolerance_bp()},\n"
  out <+ "  \"rules\": \{rule_specs_json(plan.rules())},\n"
  out <+
    "  \"partitions\": \{rule_partitions_json(plan.partition_weights())},\n"
  out <+ "  \"k\": \{plan.k()},\n"
  out <+ "  \"component_count\": \{plan.components().count()},\n"
  out <+ "  \"assignment_count\": \{plan.assignments().length()},\n"
  out <+ "  \"initial_objective\": \"\{plan.initial_objective()}\",\n"
  out <+ "  \"objective\": \"\{plan.objective()}\",\n"
  out <+ "  \"optimization_rounds\": \{plan.optimization_rounds()},\n"
  out <+ "  \"warnings\": \{json_string_array(plan.warnings())}\n"
  out <+ "}"
  out.to_string()
}

///|
/// Canonical v2 spec serialization used by the CLI normalize-spec entrypoint.
pub fn v2_spec_json(spec : @spec.V2Spec) -> String {
  let out = StringBuilder()
  out <+ "{\n"
  out <+ "  \"schema_version\": 2,\n"
  out <+ "  \"kind\": \"\{v2_kind_name(spec.kind())}\",\n"
  out <+ "  \"rules\": \{rule_specs_json(spec.rules())}"
  match spec.time() {
    Some(time) => {
      out <+ ",\n"
      out <+
        "  \"time\": {\"interval\": \"\{escape_json(time.interval())}\", \"unit\": \"\{escape_json(time.unit())}\", \"epoch\": \"\{escape_json(time.epoch())}\", \"gap\": \{time.gap()}, \"validation_windows\": \{validation_windows_json(time.validation_windows())}}\n"
    }
    None => {
      out <+ ",\n"
      out <+ "  \"seed\": \{spec.seed()},\n"
      out <+ "  \"balance_labels\": \{spec.balance_labels()},\n"
      out <+ "  \"ratio_tolerance_bp\": \{spec.ratio_tolerance_bp()},\n"
      out <+ "  \"algorithm\": \"\{spec.algorithm()}\",\n"
      match spec.kind() {
        GroupedHoldout =>
          out <+
            "  \"partitions\": \{rule_partitions_json(spec.partitions())}\n"
        GroupedKFold => out <+ "  \"k\": \{spec.k()}\n"
        TimeForward => abort("time_forward spec is missing time configuration")
      }
    }
  }
  out <+ "}"
  out.to_string()
}

///|
pub fn rule_assignments_jsonl(plan : @plan.RuleSplitPlan) -> String {
  assignments_to_jsonl(plan.assignments())
}

///|
pub fn rule_folds_jsonl(
  plan : @plan.RuleSplitPlan,
) -> Result[String, Array[@record.Issue]] {
  if plan.kind() != GroupedKFold {
    return Err([
      @record.Issue::error(
        "not_kfold_plan", "rule_folds_jsonl only accepts v2 kfold plans",
      ),
    ])
  }
  let assignments = plan.assignments()
  let out = StringBuilder()
  for index = 0; index < assignments.length(); index = index + 1 {
    if index > 0 {
      out <+ "\n"
    }
    out <+
      "{\"id\": \"\{escape_json(assignments[index].id())}\", \"validation_fold\": \"\{escape_json(assignments[index].partition())}\"}"
  }
  Ok(out.to_string())
}

///|
pub fn rule_components_jsonl(plan : @plan.RuleSplitPlan) -> String {
  let groups = plan.components().groups()
  let out = StringBuilder()
  for index = 0; index < groups.length(); index = index + 1 {
    if index > 0 {
      out <+ "\n"
    }
    let group = groups[index]
    out <+
      "{\"id\": \"\{escape_json(group.id())}\", \"member_ids\": \{json_string_array(group.member_ids())}, \"witness_edge_count\": \{group.witness_edges().length()}}"
  }
  out.to_string()
}

///|
/// Explanatory forest only.  It does not claim to list all rule matches.
pub fn rule_evidence_jsonl(plan : @plan.RuleSplitPlan) -> String {
  rule_evidence_for_components(plan.components())
}

///|
pub fn rule_summary_json(plan : @plan.RuleSplitPlan) -> String {
  let partitions = plan.partition_weights()
  let counts = plan.partition_counts()
  let mut weight_sum = @bigint.BigInt::from_int(0)
  for partition in partitions {
    weight_sum = weight_sum + @bigint.BigInt::from_int(partition.weight())
  }
  let out = StringBuilder()
  out <+ "{\n"
  out <+ "  \"schema_version\": 2,\n"
  out <+ "  \"algorithm\": \"\{plan.algorithm()}\",\n"
  out <+ "  \"records\": \{plan.components().total_records()},\n"
  out <+ "  \"components\": \{plan.components().count()},\n"
  out <+
    "  \"text_candidate_count\": \{plan.components().text_candidate_count()},\n"
  out <+
    "  \"text_comparison_count\": \{plan.components().text_comparison_count()},\n"
  out <+ "  \"initial_objective\": \"\{plan.initial_objective()}\",\n"
  out <+ "  \"objective\": \"\{plan.objective()}\",\n"
  out <+ "  \"optimization_rounds\": \{plan.optimization_rounds()},\n"
  out <+ "  \"partitions\": [\n"
  for index = 0; index < partitions.length(); index = index + 1 {
    let partition = partitions[index]
    let count = counts[partition.name()]
    let target_bp = v2_basis_points(partition.weight(), weight_sum)
    let actual_bp = v2_basis_points(
      count,
      @bigint.BigInt::from_int(plan.components().total_records()),
    )
    let deviation_bp = if actual_bp >= target_bp {
      actual_bp - target_bp
    } else {
      target_bp - actual_bp
    }
    out <+
      "    {\"name\": \"\{escape_json(partition.name())}\", \"weight\": \{partition.weight()}, \"record_count\": \{count}, \"target_bp\": \{target_bp}, \"actual_bp\": \{actual_bp}, \"deviation_bp\": \{deviation_bp}}"
    if index + 1 < partitions.length() {
      out <+ ","
    }
    out <+ "\n"
  }
  out <+ "  ]\n"
  out <+ "}"
  out.to_string()
}

///|
pub fn rule_report_markdown(plan : @plan.RuleSplitPlan) -> String {
  let out = StringBuilder()
  out <+ "# MoonSplit v2 Audit Report\n\n"
  out <+ "- Algorithm: `\{plan.algorithm()}`\n"
  out <+ "- Kind: `\{v2_kind_name(plan.kind())}`\n"
  out <+ "- Components: \{plan.components().count()}\n"
  out <+ "- Assignments: \{plan.assignments().length()}\n"
  out <+
    "- Text candidates / comparisons: \{plan.components().text_candidate_count()} / \{plan.components().text_comparison_count()}\n"
  out <+
    "- Objective: \{plan.initial_objective()} → \{plan.objective()} after \{plan.optimization_rounds()} local-move rounds\n\n"
  out <+ "## Leakage rules\n\n"
  for rule in plan.rules() {
    out <+ "- `\{rule.id()}`: \{rule_spec_markdown(rule)}\n"
  }
  out <+ "\n## Evidence\n\n"
  out <+
    "`evidence.jsonl` is a deterministic explanatory forest. It shows the edges selected to connect each component, not every matching pair.\n\n"
  out <+ "## Warnings\n\n"
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
pub fn rule_audit_json(
  report : @audit.RuleAuditReport,
  plan : @plan.RuleSplitPlan,
) -> String {
  rule_audit_report_json(
    report,
    plan.components().total_records(),
    plan.assignments().length(),
  )
}

///|
pub fn rule_audit_report_json(
  report : @audit.RuleAuditReport,
  record_count : Int,
  assignment_count : Int,
) -> String {
  let out = StringBuilder()
  out <+ "{\n"
  out <+ "  \"schema_version\": 2,\n"
  out <+ "  \"valid\": \{report.is_valid()},\n"
  out <+ "  \"records\": \{record_count},\n"
  out <+ "  \"assignments\": \{assignment_count},\n"
  out <+ "  \"components\": \{report.components().count()},\n"
  out <+
    "  \"text_candidate_count\": \{report.components().text_candidate_count()},\n"
  out <+
    "  \"text_comparison_count\": \{report.components().text_comparison_count()},\n"
  out <+ "  \"partition_counts\": \{json_int_map(report.partition_counts())},\n"
  out <+ "  \"issues\": \{v2_issues_json(report.issues())}\n"
  out <+ "}"
  out.to_string()
}

///|
pub fn temporal_plan_json(
  plan : @temporal.TemporalPlan,
  spec : @spec.V2Spec,
) -> String {
  let time = plan.time()
  let out = StringBuilder()
  out <+ "{\n"
  out <+ "  \"schema_version\": 2,\n"
  out <+ "  \"algorithm\": \"time-forward-v2\",\n"
  out <+ "  \"kind\": \"time_forward\",\n"
  out <+ "  \"rules\": \{rule_specs_json(spec.rules())},\n"
  out <+
    "  \"time\": {\"interval\": \"\{escape_json(time.interval())}\", \"unit\": \"\{escape_json(time.unit())}\", \"epoch\": \"\{escape_json(time.epoch())}\", \"gap\": \{time.gap()}, \"validation_windows\": \{validation_windows_json(time.validation_windows())}},\n"
  out <+ "  \"component_count\": \{plan.components().count()},\n"
  out <+ "  \"role_count\": \{plan.roles().length()}\n"
  out <+ "}"
  out.to_string()
}

///|
pub fn temporal_roles_jsonl(plan : @temporal.TemporalPlan) -> String {
  let roles = plan.roles()
  let out = StringBuilder()
  for index = 0; index < roles.length(); index = index + 1 {
    if index > 0 {
      out <+ "\n"
    }
    out.write_string(temporal_role_json(roles[index]))
  }
  out.to_string()
}

///|
/// Derived only from the full role manifest; it is not an independent input.
pub fn temporal_exclusions_jsonl(plan : @temporal.TemporalPlan) -> String {
  let excluded : Array[@temporal.TemporalRole] = []
  for role in plan.roles() {
    if role.role() == Excluded {
      excluded.push(role)
    }
  }
  let out = StringBuilder()
  for index = 0; index < excluded.length(); index = index + 1 {
    if index > 0 {
      out <+ "\n"
    }
    out.write_string(temporal_role_json(excluded[index]))
  }
  out.to_string()
}

///|
pub fn temporal_components_jsonl(plan : @temporal.TemporalPlan) -> String {
  let groups = plan.components().groups()
  let out = StringBuilder()
  for index = 0; index < groups.length(); index = index + 1 {
    if index > 0 {
      out <+ "\n"
    }
    let group = groups[index]
    out <+
      "{\"id\": \"\{escape_json(group.id())}\", \"member_ids\": \{json_string_array(group.member_ids())}, \"witness_edge_count\": \{group.witness_edges().length()}}"
  }
  out.to_string()
}

///|
pub fn temporal_witnesses_jsonl(plan : @temporal.TemporalPlan) -> String {
  rule_evidence_for_components(plan.components())
}

///|
pub fn temporal_summary_json(plan : @temporal.TemporalPlan) -> String {
  let time = plan.time()
  let roles = plan.roles()
  let train_counts : Map[String, Int] = Map([])
  let validation_counts : Map[String, Int] = Map([])
  let excluded_counts : Map[String, Int] = Map([])
  for window in time.validation_windows() {
    train_counts[window.id()] = 0
    validation_counts[window.id()] = 0
    excluded_counts[window.id()] = 0
  }
  for role in roles {
    match role.role() {
      Train => train_counts[role.fold_id()] = train_counts[role.fold_id()] + 1
      Validation =>
        validation_counts[role.fold_id()] = validation_counts[role.fold_id()] +
          1
      Excluded =>
        excluded_counts[role.fold_id()] = excluded_counts[role.fold_id()] + 1
    }
  }
  let out = StringBuilder()
  out <+ "{\n"
  out <+ "  \"schema_version\": 2,\n"
  out <+ "  \"algorithm\": \"time-forward-v2\",\n"
  out <+ "  \"records\": \{plan.components().total_records()},\n"
  out <+ "  \"components\": \{plan.components().count()},\n"
  out <+
    "  \"text_candidate_count\": \{plan.components().text_candidate_count()},\n"
  out <+
    "  \"text_comparison_count\": \{plan.components().text_comparison_count()},\n"
  out <+ "  \"folds\": [\n"
  let windows = time.validation_windows()
  for index = 0; index < windows.length(); index = index + 1 {
    let window = windows[index]
    out <+
      "    {\"id\": \"\{escape_json(window.id())}\", \"start\": \{window.start()}, \"end\": \{window.end()}, \"train_count\": \{train_counts[window.id()]}, \"validation_count\": \{validation_counts[window.id()]}, \"excluded_count\": \{excluded_counts[window.id()]}}"
    if index + 1 < windows.length() {
      out <+ ","
    }
    out <+ "\n"
  }
  out <+ "  ]\n"
  out <+ "}"
  out.to_string()
}

///|
pub fn temporal_report_markdown(plan : @temporal.TemporalPlan) -> String {
  let time = plan.time()
  let out = StringBuilder()
  out <+ "# MoonSplit Time-Forward Audit Report\n\n"
  out <+
    "- Coordinate: `\{time.interval()}` in `\{time.unit()}` since `\{time.epoch()}`\n"
  out <+ "- Gap: `\{time.gap()}`\n"
  out <+ "- Components: \{plan.components().count()}\n"
  out <+ "- Role records: \{plan.roles().length()}\n\n"
  out <+
    "Every fold keeps full-window records as validation, excludes other records in their rule components, then admits only records ending no later than `validation_start - gap` to training.\n\n"
  out <+
    "`witnesses.jsonl` is an explanatory forest, not a complete list of matching pairs.\n"
  out.to_string()
}

///|
pub fn temporal_audit_json(
  report : @temporal.TemporalAuditReport,
  plan : @temporal.TemporalPlan,
) -> String {
  temporal_audit_report_json(
    report,
    plan.components().total_records(),
    plan.roles().length(),
  )
}

///|
pub fn temporal_audit_report_json(
  report : @temporal.TemporalAuditReport,
  record_count : Int,
  role_count : Int,
) -> String {
  let out = StringBuilder()
  out <+ "{\n"
  out <+ "  \"schema_version\": 2,\n"
  out <+ "  \"valid\": \{report.is_valid()},\n"
  out <+ "  \"records\": \{record_count},\n"
  out <+ "  \"roles\": \{role_count},\n"
  out <+ "  \"train_counts\": \{json_int_map(report.train_counts())},\n"
  out <+
    "  \"validation_counts\": \{json_int_map(report.validation_counts())},\n"
  out <+ "  \"issues\": \{v2_issues_json(report.issues())}\n"
  out <+ "}"
  out.to_string()
}

///|
fn assignments_to_jsonl(assignments : Array[@record.Assignment]) -> String {
  let out = StringBuilder()
  for index = 0; index < assignments.length(); index = index + 1 {
    if index > 0 {
      out <+ "\n"
    }
    let assignment = assignments[index]
    out <+
      "{\"id\": \"\{escape_json(assignment.id())}\", \"partition\": \"\{escape_json(assignment.partition())}\"}"
  }
  out.to_string()
}

///|
fn rule_evidence_for_components(components : @rules.RuleComponents) -> String {
  let out = StringBuilder()
  let mut line_count = 0
  for group in components.groups() {
    for edge in group.witness_edges() {
      if line_count > 0 {
        out <+ "\n"
      }
      out <+
        "{\"component_id\": \"\{escape_json(group.id())}\", \"left_id\": \"\{escape_json(edge.left_id())}\", \"right_id\": \"\{escape_json(edge.right_id())}\", \"rule_id\": \"\{escape_json(edge.rule_id())}\", \"rule_type\": \"\{escape_json(edge.rule_type())}\", \"detail\": \"\{escape_json(edge.detail())}\"}"
      line_count += 1
    }
  }
  out.to_string()
}

///|
fn rule_specs_json(rules : Array[@spec.LeakageRule]) -> String {
  let out = StringBuilder()
  out <+ "["
  for index = 0; index < rules.length(); index = index + 1 {
    if index > 0 {
      out <+ ", "
    }
    let rule = rules[index]
    match rule.kind() {
      ExactKey => {
        let key = rule.key().unwrap_or("")
        out <+
          "{\"id\": \"\{escape_json(rule.id())}\", \"type\": \"exact_key\", \"key\": \"\{escape_json(key)}\"}"
      }
      TextJaccard =>
        out <+
          "{\"id\": \"\{escape_json(rule.id())}\", \"type\": \"text_jaccard\", \"q\": \{rule.q()}, \"threshold_bp\": \{rule.threshold_bp()}}"
      IntervalOverlap => {
        let source_key = rule.source_key().unwrap_or("")
        let interval = rule.interval().unwrap_or("")
        out <+
          "{\"id\": \"\{escape_json(rule.id())}\", \"type\": \"interval_overlap\", \"source_key\": \"\{escape_json(source_key)}\", \"interval\": \"\{escape_json(interval)}\"}"
      }
    }
  }
  out <+ "]"
  out.to_string()
}

///|
fn rule_partitions_json(partitions : Array[@spec.Partition]) -> String {
  let out = StringBuilder()
  out <+ "["
  for index = 0; index < partitions.length(); index = index + 1 {
    if index > 0 {
      out <+ ", "
    }
    out <+
      "{\"name\": \"\{escape_json(partitions[index].name())}\", \"weight\": \{partitions[index].weight()}}"
  }
  out <+ "]"
  out.to_string()
}

///|
fn rule_spec_markdown(rule : @spec.LeakageRule) -> String {
  match rule.kind() {
    ExactKey => {
      let key = rule.key().unwrap_or("")
      "exact key `\{key}`"
    }
    TextJaccard =>
      "Unicode \{rule.q()}-gram Jaccard, threshold \{rule.threshold_bp()}bp"
    IntervalOverlap => {
      let interval = rule.interval().unwrap_or("")
      let source_key = rule.source_key().unwrap_or("")
      "half-open interval `\{interval}` within source key `\{source_key}`"
    }
  }
}

///|
fn validation_windows_json(windows : Array[@spec.ValidationWindow]) -> String {
  let out = StringBuilder()
  out <+ "["
  for index = 0; index < windows.length(); index = index + 1 {
    if index > 0 {
      out <+ ", "
    }
    let window = windows[index]
    out <+
      "{\"id\": \"\{escape_json(window.id())}\", \"start\": \{window.start()}, \"end\": \{window.end()}}"
  }
  out <+ "]"
  out.to_string()
}

///|
fn temporal_role_json(role : @temporal.TemporalRole) -> String {
  "{\"fold_id\": \"\{escape_json(role.fold_id())}\", \"id\": \"\{escape_json(role.id())}\", \"role\": \"\{role.role().as_string()}\", \"reason\": \"\{role.reason().as_string()}\"}"
}

///|
fn v2_issues_json(issues : Array[@record.Issue]) -> String {
  let out = StringBuilder()
  out <+ "["
  for index = 0; index < issues.length(); index = index + 1 {
    if index > 0 {
      out <+ ", "
    }
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
      "{\"severity\": \"\{severity}\", \"code\": \"\{escape_json(issue.code())}\", \"message\": \"\{escape_json(issue.message())}\", \"line\": \{line}}"
  }
  out <+ "]"
  out.to_string()
}

///|
fn v2_kind_name(kind : @spec.V2Kind) -> String {
  match kind {
    GroupedHoldout => "holdout"
    GroupedKFold => "kfold"
    TimeForward => "time_forward"
  }
}

///|
fn v2_basis_points(numerator : Int, denominator : @bigint.BigInt) -> Int {
  if denominator <= @bigint.BigInt::from_int(0) {
    return 0
  }
  let rounded = (
      @bigint.BigInt::from_int(numerator) * @bigint.BigInt::from_int(10000) +
      denominator / @bigint.BigInt::from_int(2)
    ) /
    denominator
  rounded.to_int()
}
