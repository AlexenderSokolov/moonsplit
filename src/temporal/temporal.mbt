///|
pub(all) enum TemporalRoleKind {
  Train
  Validation
  Excluded
} derive(Eq, Debug)

///|
pub(all) enum TemporalReason {
  ValidationWindow
  ComponentConflict
  Historical
  Gap
  Future
  BoundaryOverlap
} derive(Eq, Debug)

///|
pub struct TemporalRole {
  priv fold_id : String
  priv id : String
  priv role : TemporalRoleKind
  priv reason : TemporalReason
} derive(Debug)

///|
pub struct TemporalPlan {
  priv roles : Array[TemporalRole]
  priv components : @rules.RuleComponents
  priv time : @spec.TimeConfig
} derive(Debug)

///|
pub struct TemporalAuditReport {
  priv is_valid : Bool
  priv issues : Array[@record.Issue]
  priv train_counts : Map[String, Int]
  priv validation_counts : Map[String, Int]
} derive(Debug)

///|
pub fn TemporalRole::new(
  fold_id : String,
  id : String,
  role : TemporalRoleKind,
  reason : TemporalReason,
) -> TemporalRole {
  { fold_id, id, role, reason, }
}

///|
pub fn TemporalRole::fold_id(self : TemporalRole) -> String {
  self.fold_id
}

///|
pub fn TemporalRole::id(self : TemporalRole) -> String {
  self.id
}

///|
pub fn TemporalRole::role(self : TemporalRole) -> TemporalRoleKind {
  self.role
}

///|
pub fn TemporalRole::reason(self : TemporalRole) -> TemporalReason {
  self.reason
}

///|
pub fn TemporalRoleKind::as_string(self : TemporalRoleKind) -> String {
  match self {
    Train => "train"
    Validation => "validation"
    Excluded => "excluded"
  }
}

///|
pub fn TemporalReason::as_string(self : TemporalReason) -> String {
  match self {
    ValidationWindow => "validation_window"
    ComponentConflict => "component_conflict"
    Historical => "historical"
    Gap => "gap"
    Future => "future"
    BoundaryOverlap => "boundary_overlap"
  }
}

///|
fn TemporalPlan::new(
  roles : Array[TemporalRole],
  components : @rules.RuleComponents,
  time : @spec.TimeConfig,
) -> TemporalPlan {
  let sorted_roles = roles.copy()
  let fold_order : Map[String, Int] = Map([])
  for index = 0; index < time.validation_windows().length(); index = index + 1 {
    fold_order[time.validation_windows()[index].id()] = index
  }
  sorted_roles.sort_by((left, right) => {
    let left_order = fold_order.get(left.fold_id()).unwrap_or(-1)
    let right_order = fold_order.get(right.fold_id()).unwrap_or(-1)
    if left_order < right_order {
      -1
    } else if left_order > right_order {
      1
    } else {
      left.id().lexical_compare(right.id())
    }
  })
  { roles: sorted_roles, components, time, }
}

///|
pub fn TemporalPlan::roles(self : TemporalPlan) -> Array[TemporalRole] {
  self.roles.copy()
}

///|
pub fn TemporalPlan::components(self : TemporalPlan) -> @rules.RuleComponents {
  self.components
}

///|
pub fn TemporalPlan::time(self : TemporalPlan) -> @spec.TimeConfig {
  self.time
}

///|
fn TemporalAuditReport::new(
  is_valid : Bool,
  issues : Array[@record.Issue],
  train_counts : Map[String, Int],
  validation_counts : Map[String, Int],
) -> TemporalAuditReport {
  {
    is_valid,
    issues: issues.copy(),
    train_counts: copy_temporal_counts(train_counts),
    validation_counts: copy_temporal_counts(validation_counts),
  }
}

///|
pub fn TemporalAuditReport::is_valid(self : TemporalAuditReport) -> Bool {
  self.is_valid
}

///|
pub fn TemporalAuditReport::issues(
  self : TemporalAuditReport,
) -> Array[@record.Issue] {
  self.issues.copy()
}

///|
pub fn TemporalAuditReport::train_counts(
  self : TemporalAuditReport,
) -> Map[String, Int] {
  copy_temporal_counts(self.train_counts)
}

///|
pub fn TemporalAuditReport::validation_counts(
  self : TemporalAuditReport,
) -> Map[String, Int] {
  copy_temporal_counts(self.validation_counts)
}

///|
/// Build a forward-validation role manifest.  Every record gets exactly one role
/// in every declared window; excluded records are never implicit training data.
pub fn plan_temporal(
  records : Array[@record.V2Record],
  spec : @spec.V2Spec,
) -> Result[TemporalPlan, Array[@record.Issue]] {
  let time = match temporal_time_config(spec) {
    Ok(value) => value
    Err(issues) => return Err(issues)
  }
  let components = match @rules.build_rule_components(records, spec.rules()) {
    Ok(value) => value
    Err(issues) => return Err(issues)
  }
  let roles = match build_temporal_roles(records, time, components) {
    Ok(value) => value
    Err(issues) => return Err(issues)
  }
  let audit = match audit_temporal(records, spec, roles) {
    Ok(value) => value
    Err(issues) => return Err(issues)
  }
  if !audit.is_valid() {
    return Err(audit.issues())
  }
  Ok(TemporalPlan::new(roles, components, time))
}

///|
/// Independently rebuild the expected roles from original records, time config,
/// and rule components.  The supplied manifest is never trusted as a summary.
pub fn audit_temporal(
  records : Array[@record.V2Record],
  spec : @spec.V2Spec,
  roles : Array[TemporalRole],
) -> Result[TemporalAuditReport, Array[@record.Issue]] {
  let time = match temporal_time_config(spec) {
    Ok(value) => value
    Err(issues) => return Err(issues)
  }
  let components = match @rules.build_rule_components(records, spec.rules()) {
    Ok(value) => value
    Err(issues) => return Err(issues)
  }
  let expected_roles = match build_temporal_roles(records, time, components) {
    Ok(value) => value
    Err(issues) => return Err(issues)
  }
  let issues : Array[@record.Issue] = []
  let expected_by_key : Map[(String, String), TemporalRole] = Map([])
  let expected_folds : Map[String, Bool] = Map([])
  let record_ids : Map[String, Bool] = Map([])
  for record in records {
    record_ids[record.id()] = true
  }
  for role in expected_roles {
    expected_folds[role.fold_id()] = true
    expected_by_key[(role.fold_id(), role.id())] = role
  }
  let supplied = roles.copy()
  supplied.sort_by(compare_temporal_roles)
  let actual_by_key : Map[(String, String), TemporalRole] = Map([])
  for role in supplied {
    let key = (role.fold_id(), role.id())
    if !expected_folds.contains(role.fold_id()) {
      issues.push(
        @record.Issue::error(
          "unknown_temporal_fold",
          "role refers to unknown fold \{role.fold_id()}",
        ),
      )
    } else if !record_ids.contains(role.id()) {
      issues.push(
        @record.Issue::error(
          "unknown_temporal_record",
          "role refers to unknown record \{role.id()}",
        ),
      )
    } else if actual_by_key.contains(key) {
      issues.push(
        @record.Issue::error(
          "duplicate_temporal_role",
          "record \{role.id()} has multiple roles in fold \{role.fold_id()}",
        ),
      )
    } else {
      actual_by_key[key] = role
      match expected_by_key.get(key) {
        Some(expected) =>
          if role.role() != expected.role() ||
            role.reason() != expected.reason() {
            issues.push(
              @record.Issue::error(
                "invalid_temporal_role",
                "record \{role.id()} in fold \{role.fold_id()} has role or reason inconsistent with the time policy",
              ),
            )
          }
        None => ()
      }
    }
  }
  for key in expected_by_key.keys() {
    if !actual_by_key.contains(key) {
      issues.push(
        @record.Issue::error(
          "missing_temporal_role",
          "manifest is missing role for record \{key.1} in fold \{key.0}",
        ),
      )
    }
  }
  let train_counts : Map[String, Int] = Map([])
  let validation_counts : Map[String, Int] = Map([])
  for window in time.validation_windows() {
    train_counts[window.id()] = 0
    validation_counts[window.id()] = 0
  }
  let component_roles : Map[(String, String), (Bool, Bool)] = Map([])
  let component_by_id : Map[String, String] = Map([])
  for component in components.groups() {
    for id in component.member_ids() {
      component_by_id[id] = component.id()
    }
  }
  for key in actual_by_key.keys() {
    let role = actual_by_key[key]
    match role.role() {
      Train => train_counts[role.fold_id()] = train_counts[role.fold_id()] + 1
      Validation =>
        validation_counts[role.fold_id()] = validation_counts[role.fold_id()] +
          1
      Excluded => ()
    }
    let component = component_by_id.get(role.id()).unwrap_or("")
    let component_key = (role.fold_id(), component)
    let state = component_roles.get(component_key).unwrap_or((false, false))
    let next_state = match role.role() {
      Train => (true, state.1)
      Validation => (state.0, true)
      Excluded => state
    }
    component_roles[component_key] = next_state
  }
  for window in time.validation_windows() {
    if train_counts[window.id()] == 0 {
      issues.push(
        @record.Issue::error(
          "empty_temporal_train",
          "fold \{window.id()} has no training records",
        ),
      )
    }
    if validation_counts[window.id()] == 0 {
      issues.push(
        @record.Issue::error(
          "empty_temporal_validation",
          "fold \{window.id()} has no validation records",
        ),
      )
    }
  }
  let component_keys : Array[(String, String)] = []
  for key in component_roles.keys() {
    component_keys.push(key)
  }
  component_keys.sort_by(compare_temporal_component_keys)
  for key in component_keys {
    let state = component_roles[key]
    if state.0 && state.1 {
      issues.push(
        @record.Issue::error(
          "temporal_component_leak",
          "component \{key.1} has both train and validation records in fold \{key.0}",
        ),
      )
    }
  }
  Ok(
    TemporalAuditReport::new(
      issues.length() == 0,
      issues,
      train_counts,
      validation_counts,
    ),
  )
}

///|
/// Read a `roles.jsonl` manifest for the temporal CLI audit entrypoint.
pub fn parse_temporal_roles(
  input : String,
) -> Result[Array[TemporalRole], Array[@record.Issue]] {
  let lines = input.split("\n").to_array()
  let roles : Array[TemporalRole] = []
  let issues : Array[@record.Issue] = []
  for line_number = 1
      line_number <= lines.length()
      line_number = line_number + 1 {
    let line = lines[line_number - 1].trim(char_set="\u{feff} \t\r\n")
    if line == "" {
      continue
    }
    let json = @json.parse(line) catch {
      err => {
        issues.push(
          @record.Issue::error_at_line(
            "invalid_json",
            "invalid JSON on line \{line_number}: \{err}",
            line_number,
          ),
        )
        continue
      }
    }
    match parse_temporal_role_json(json, line_number) {
      Ok(role) => roles.push(role)
      Err(issue) => issues.push(issue)
    }
  }
  if issues.length() > 0 {
    Err(issues)
  } else if roles.length() == 0 {
    Err([@record.Issue::error("empty_temporal_roles", "role manifest is empty")])
  } else {
    Ok(roles)
  }
}

///|
fn temporal_time_config(
  spec : @spec.V2Spec,
) -> Result[@spec.TimeConfig, Array[@record.Issue]] {
  if spec.kind() != TimeForward {
    return Err([
      @record.Issue::error(
        "invalid_spec_kind", "temporal planning requires kind time_forward",
      ),
    ])
  }
  match spec.time() {
    Some(value) => Ok(value)
    None => Err([@record.Issue::error("missing_time", "time is missing")])
  }
}

///|
fn build_temporal_roles(
  records : Array[@record.V2Record],
  time : @spec.TimeConfig,
  components : @rules.RuleComponents,
) -> Result[Array[TemporalRole], Array[@record.Issue]] {
  let sorted_records = records.copy()
  sorted_records.sort_by((left, right) => left.id().lexical_compare(right.id()))
  let intervals : Map[String, @record.Interval] = Map([])
  for record in sorted_records {
    let interval = match record.interval(time.interval()) {
      Some(value) => value
      None =>
        return Err([
          @record.Issue::error(
            "missing_time_interval",
            "record \{record.id()} is missing time interval \{time.interval()}",
          ),
        ])
    }
    if interval.start() >= interval.end() {
      return Err([
        @record.Issue::error(
          "invalid_interval_bounds",
          "record \{record.id()} time interval \{time.interval()} must satisfy start < end",
        ),
      ])
    }
    intervals[record.id()] = interval
  }
  let component_by_id : Map[String, String] = Map([])
  for component in components.groups() {
    for id in component.member_ids() {
      component_by_id[id] = component.id()
    }
  }
  let roles : Array[TemporalRole] = []
  for window in time.validation_windows() {
    let validation_components : Map[String, Bool] = Map([])
    for record in sorted_records {
      let interval = intervals[record.id()]
      if interval.start() >= window.start() && interval.end() <= window.end() {
        validation_components[component_by_id[record.id()]] = true
      }
    }
    let history_cutoff = window.start() - time.gap()
    let mut train_count = 0
    let mut validation_count = 0
    for record in sorted_records {
      let interval = intervals[record.id()]
      let component = component_by_id[record.id()]
      let role = if interval.start() >= window.start() &&
        interval.end() <= window.end() {
        validation_count += 1
        TemporalRole::new(
          window.id(),
          record.id(),
          Validation,
          ValidationWindow,
        )
      } else if validation_components.contains(component) {
        TemporalRole::new(window.id(), record.id(), Excluded, ComponentConflict)
      } else if interval.end() <= history_cutoff {
        train_count += 1
        TemporalRole::new(window.id(), record.id(), Train, Historical)
      } else if interval.end() <= window.start() {
        TemporalRole::new(window.id(), record.id(), Excluded, Gap)
      } else if interval.start() >= window.end() {
        TemporalRole::new(window.id(), record.id(), Excluded, Future)
      } else {
        TemporalRole::new(window.id(), record.id(), Excluded, BoundaryOverlap)
      }
      roles.push(role)
    }
    if train_count == 0 {
      return Err([
        @record.Issue::error(
          "empty_temporal_train",
          "fold \{window.id()} has no training records",
        ),
      ])
    }
    if validation_count == 0 {
      return Err([
        @record.Issue::error(
          "empty_temporal_validation",
          "fold \{window.id()} has no validation records",
        ),
      ])
    }
  }
  Ok(roles)
}

///|
fn parse_temporal_role_json(
  json : Json,
  line_number : Int,
) -> Result[TemporalRole, @record.Issue] {
  guard json is Object(obj) else {
    return Err(
      @record.Issue::error_at_line(
        "invalid_temporal_role", "role entry must be an object", line_number,
      ),
    )
  }
  let fold_id = match temporal_role_string(obj, "fold_id", line_number) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let id = match temporal_role_string(obj, "id", line_number) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let role_text = match temporal_role_string(obj, "role", line_number) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let reason_text = match temporal_role_string(obj, "reason", line_number) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let role = match role_text {
    "train" => Train
    "validation" => Validation
    "excluded" => Excluded
    _ =>
      return Err(
        @record.Issue::error_at_line(
          "invalid_temporal_role",
          "unknown temporal role \{role_text}",
          line_number,
        ),
      )
  }
  let reason = match reason_text {
    "validation_window" => ValidationWindow
    "component_conflict" => ComponentConflict
    "historical" => Historical
    "gap" => Gap
    "future" => Future
    "boundary_overlap" => BoundaryOverlap
    _ =>
      return Err(
        @record.Issue::error_at_line(
          "invalid_temporal_reason",
          "unknown temporal reason \{reason_text}",
          line_number,
        ),
      )
  }
  Ok(TemporalRole::new(fold_id, id, role, reason))
}

///|
fn temporal_role_string(
  obj : Map[String, Json],
  field : String,
  line_number : Int,
) -> Result[String, @record.Issue] {
  match obj.get(field) {
    Some(String(value)) if value != "" => Ok(value)
    _ =>
      Err(
        @record.Issue::error_at_line(
          "invalid_temporal_role",
          "field \{field} must be a non-empty string",
          line_number,
        ),
      )
  }
}

///|
fn compare_temporal_roles(left : TemporalRole, right : TemporalRole) -> Int {
  let fold_comparison = left.fold_id().lexical_compare(right.fold_id())
  if fold_comparison != 0 {
    return fold_comparison
  }
  left.id().lexical_compare(right.id())
}

///|
fn compare_temporal_component_keys(
  left : (String, String),
  right : (String, String),
) -> Int {
  let fold_comparison = left.0.lexical_compare(right.0)
  if fold_comparison != 0 {
    fold_comparison
  } else {
    left.1.lexical_compare(right.1)
  }
}

///|
fn copy_temporal_counts(source : Map[String, Int]) -> Map[String, Int] {
  let copied : Map[String, Int] = Map([])
  for key in source.keys() {
    copied[key] = source[key]
  }
  copied
}
