///|
pub(all) enum LeakageRuleKind {
  ExactKey
  TextJaccard
  IntervalOverlap
} derive(Eq, Debug)

///|
pub(all) enum V2Kind {
  GroupedHoldout
  GroupedKFold
  TimeForward
} derive(Eq, Debug)

///|
pub struct ValidationWindow {
  priv id : String
  priv start : Int64
  priv end : Int64
} derive(Debug)

///|
pub struct TimeConfig {
  priv interval : String
  priv unit : String
  priv epoch : String
  priv gap : Int64
  priv validation_windows : Array[ValidationWindow]
} derive(Debug)

///|
pub struct LeakageRule {
  priv id : String
  priv kind : LeakageRuleKind
  priv key : String?
  priv q : Int
  priv threshold_bp : Int
  priv source_key : String?
  priv interval : String?
} derive(Debug)

///|
pub struct V2Spec {
  priv kind : V2Kind
  priv rules : Array[LeakageRule]
  priv seed : UInt
  priv balance_labels : Bool
  priv ratio_tolerance_bp : Int
  priv partitions : Array[Partition]
  priv k : Int
  priv algorithm : String
  priv time : TimeConfig?
} derive(Debug)

///|
pub fn ValidationWindow::new(
  id : String,
  start : Int64,
  end : Int64,
) -> ValidationWindow {
  { id, start, end, }
}

///|
pub fn ValidationWindow::id(self : ValidationWindow) -> String {
  self.id
}

///|
pub fn ValidationWindow::start(self : ValidationWindow) -> Int64 {
  self.start
}

///|
pub fn ValidationWindow::end(self : ValidationWindow) -> Int64 {
  self.end
}

///|
pub fn TimeConfig::new(
  interval : String,
  unit : String,
  epoch : String,
  gap : Int64,
  validation_windows : Array[ValidationWindow],
) -> TimeConfig {
  { interval, unit, epoch, gap, validation_windows: validation_windows.copy(), }
}

///|
pub fn TimeConfig::interval(self : TimeConfig) -> String {
  self.interval
}

///|
pub fn TimeConfig::unit(self : TimeConfig) -> String {
  self.unit
}

///|
pub fn TimeConfig::epoch(self : TimeConfig) -> String {
  self.epoch
}

///|
pub fn TimeConfig::gap(self : TimeConfig) -> Int64 {
  self.gap
}

///|
pub fn TimeConfig::validation_windows(
  self : TimeConfig,
) -> Array[ValidationWindow] {
  self.validation_windows.copy()
}

///|
pub fn LeakageRule::id(self : LeakageRule) -> String {
  self.id
}

///|
pub fn LeakageRule::kind(self : LeakageRule) -> LeakageRuleKind {
  self.kind
}

///|
pub fn LeakageRule::key(self : LeakageRule) -> String? {
  self.key
}

///|
pub fn LeakageRule::q(self : LeakageRule) -> Int {
  self.q
}

///|
pub fn LeakageRule::threshold_bp(self : LeakageRule) -> Int {
  self.threshold_bp
}

///|
pub fn LeakageRule::source_key(self : LeakageRule) -> String? {
  self.source_key
}

///|
pub fn LeakageRule::interval(self : LeakageRule) -> String? {
  self.interval
}

///|
pub fn V2Spec::kind(self : V2Spec) -> V2Kind {
  self.kind
}

///|
pub fn V2Spec::rules(self : V2Spec) -> Array[LeakageRule] {
  self.rules.copy()
}

///|
pub fn V2Spec::seed(self : V2Spec) -> UInt {
  self.seed
}

///|
pub fn V2Spec::balance_labels(self : V2Spec) -> Bool {
  self.balance_labels
}

///|
pub fn V2Spec::ratio_tolerance_bp(self : V2Spec) -> Int {
  self.ratio_tolerance_bp
}

///|
pub fn V2Spec::partitions(self : V2Spec) -> Array[Partition] {
  self.partitions.copy()
}

///|
pub fn V2Spec::k(self : V2Spec) -> Int {
  self.k
}

///|
pub fn V2Spec::algorithm(self : V2Spec) -> String {
  self.algorithm
}

///|
pub fn V2Spec::time(self : V2Spec) -> TimeConfig? {
  self.time
}

///|
pub fn parse_v2_spec(input : String) -> Result[V2Spec, Array[@record.Issue]] {
  let normalized = input.trim(char_set="\u{feff} \t\r\n").to_owned()
  let json = @json.parse(normalized) catch {
    err =>
      return Err([
        @record.Issue::error("invalid_json", "invalid spec JSON: \{err}"),
      ])
  }
  guard json is Object(obj) else {
    return Err([@record.Issue::error("invalid_spec", "expected spec object")])
  }
  match obj.get("schema_version") {
    Some(Number(2.0, ..)) => ()
    Some(Number(version, ..)) =>
      return Err([
        @record.Issue::error(
          "unsupported_schema_version",
          "unsupported spec schema_version: \{version}",
        ),
      ])
    Some(_) =>
      return Err([
        @record.Issue::error(
          "invalid_schema_version", "schema_version must be number 2",
        ),
      ])
    None =>
      return Err([
        @record.Issue::error(
          "missing_schema_version", "schema_version is missing",
        ),
      ])
  }
  let kind = match obj.get("kind") {
    Some(String("holdout")) => GroupedHoldout
    Some(String("kfold")) => GroupedKFold
    Some(String("time_forward")) => TimeForward
    Some(String(value)) =>
      return Err([
        @record.Issue::error(
          "invalid_spec_kind",
          "invalid v2 spec kind: \{value}",
        ),
      ])
    Some(_) =>
      return Err([
        @record.Issue::error("invalid_spec_kind", "spec kind must be a string"),
      ])
    None =>
      return Err([
        @record.Issue::error("missing_spec_kind", "spec kind is missing"),
      ])
  }
  let rules = match parse_leakage_rules(obj) {
    Ok(value) => value
    Err(issues) => return Err(issues)
  }
  let seed = match parse_non_negative_uint(obj, "seed", 42U, "invalid_seed") {
    Ok(value) => value
    Err(issues) => return Err(issues)
  }
  let balance_labels = match obj.get("balance_labels") {
    None => false
    Some(True) => true
    Some(False) => false
    Some(_) =>
      return Err([
        @record.Issue::error(
          "invalid_balance_labels", "balance_labels must be a boolean",
        ),
      ])
  }
  let ratio_tolerance_bp = match
    parse_integer(
      obj, "ratio_tolerance_bp", 500, "invalid_ratio_tolerance_bp", "ratio_tolerance_bp must be an integer",
    ) {
    Ok(value) => value
    Err(issues) => return Err(issues)
  }
  if ratio_tolerance_bp < 0 || ratio_tolerance_bp > 10000 {
    return Err([
      @record.Issue::error(
        "invalid_ratio_tolerance_bp", "ratio_tolerance_bp must be between 0 and 10000",
      ),
    ])
  }
  let algorithm = match kind {
    TimeForward => {
      if obj.contains("algorithm") {
        return Err([
          @record.Issue::error(
            "invalid_time_algorithm", "time_forward cannot declare algorithm",
          ),
        ])
      }
      "time-forward-v2"
    }
    _ =>
      match obj.get("algorithm") {
        None => "group-local-v2"
        Some(String("group-local-v2")) => "group-local-v2"
        Some(String(value)) =>
          return Err([
            @record.Issue::error(
              "invalid_algorithm",
              "unsupported v2 algorithm: \{value}",
            ),
          ])
        Some(_) =>
          return Err([
            @record.Issue::error(
              "invalid_algorithm", "algorithm must be a string",
            ),
          ])
      }
  }
  match kind {
    GroupedHoldout => {
      let partitions = match parse_v2_partitions(obj) {
        Ok(value) => value
        Err(issues) => return Err(issues)
      }
      Ok({
        kind,
        rules,
        seed,
        balance_labels,
        ratio_tolerance_bp,
        partitions,
        k: 0,
        algorithm,
        time: None,
      })
    }
    GroupedKFold => {
      let k = match
        parse_integer(obj, "k", 0, "invalid_k", "k must be an integer") {
        Ok(value) => value
        Err(issues) => return Err(issues)
      }
      if !obj.contains("k") {
        return Err([@record.Issue::error("missing_k", "k is missing")])
      }
      if k < 2 || k > 20 {
        return Err([
          @record.Issue::error("invalid_k", "k must be between 2 and 20"),
        ])
      }
      if obj.contains("partitions") {
        return Err([
          @record.Issue::error(
            "invalid_kfold_partitions", "kfold cannot declare partitions",
          ),
        ])
      }
      let partitions : Array[Partition] = []
      for index = 0; index < k; index = index + 1 {
        partitions.push(Partition::new("fold_\{index}", 1))
      }
      Ok({
        kind,
        rules,
        seed,
        balance_labels,
        ratio_tolerance_bp,
        partitions,
        k,
        algorithm,
        time: None,
      })
    }
    TimeForward => {
      if obj.contains("partitions") {
        return Err([
          @record.Issue::error(
            "invalid_time_partitions", "time_forward cannot declare partitions",
          ),
        ])
      }
      if obj.contains("k") {
        return Err([
          @record.Issue::error(
            "invalid_time_k", "time_forward cannot declare k",
          ),
        ])
      }
      let time = match parse_time_config(obj) {
        Ok(value) => value
        Err(issues) => return Err(issues)
      }
      Ok({
        kind,
        rules,
        seed,
        balance_labels,
        ratio_tolerance_bp,
        partitions: [],
        k: 0,
        algorithm,
        time: Some(time),
      })
    }
  }
}

///|
fn parse_time_config(
  obj : Map[String, Json],
) -> Result[TimeConfig, Array[@record.Issue]] {
  let time_obj = match obj.get("time") {
    Some(Object(value)) => value
    Some(_) =>
      return Err([
        @record.Issue::error("invalid_time", "time must be an object"),
      ])
    None =>
      return Err([@record.Issue::error("missing_time", "time is missing")])
  }
  let interval = match
    required_non_empty_string(time_obj, "interval", "invalid_time_interval") {
    Ok(value) => value
    Err(issues) => return Err(issues)
  }
  let unit = match
    required_non_empty_string(time_obj, "unit", "invalid_time_unit") {
    Ok(value) => value
    Err(issues) => return Err(issues)
  }
  let epoch = match
    required_non_empty_string(time_obj, "epoch", "invalid_time_epoch") {
    Ok(value) => value
    Err(issues) => return Err(issues)
  }
  let gap_json = match time_obj.get("gap") {
    Some(value) => value
    None =>
      return Err([
        @record.Issue::error("missing_time_gap", "time gap is missing"),
      ])
  }
  let gap = match parse_safe_time_int64(gap_json, "gap") {
    Ok(value) => value
    Err(issues) => return Err(issues)
  }
  if gap < 0L {
    return Err([
      @record.Issue::error("invalid_time_gap", "time gap must be non-negative"),
    ])
  }
  let windows_json = match time_obj.get("validation_windows") {
    Some(Array(value)) if value.length() > 0 => value
    Some(Array(_)) =>
      return Err([
        @record.Issue::error(
          "invalid_validation_windows", "validation_windows must be non-empty",
        ),
      ])
    Some(_) =>
      return Err([
        @record.Issue::error(
          "invalid_validation_windows", "validation_windows must be an array",
        ),
      ])
    None =>
      return Err([
        @record.Issue::error(
          "missing_validation_windows", "validation_windows is missing",
        ),
      ])
  }
  let windows : Array[ValidationWindow] = []
  let ids : Map[String, Bool] = Map([])
  let mut previous_end : Int64? = None
  for item in windows_json {
    guard item is Object(window_obj) else {
      return Err([
        @record.Issue::error(
          "invalid_validation_windows", "validation windows must be objects",
        ),
      ])
    }
    let id = match
      required_non_empty_string(
        window_obj, "id", "invalid_validation_window_id",
      ) {
      Ok(value) => value
      Err(issues) => return Err(issues)
    }
    if ids.contains(id) {
      return Err([
        @record.Issue::error(
          "duplicate_validation_window_id",
          "duplicate validation window id: \{id}",
        ),
      ])
    }
    ids[id] = true
    let start = match window_obj.get("start") {
      Some(value) =>
        match parse_safe_time_int64(value, "validation_window_start") {
          Ok(parsed) => parsed
          Err(issues) => return Err(issues)
        }
      None =>
        return Err([
          @record.Issue::error(
            "missing_validation_window_start", "validation window start is missing",
          ),
        ])
    }
    let end = match window_obj.get("end") {
      Some(value) =>
        match parse_safe_time_int64(value, "validation_window_end") {
          Ok(parsed) => parsed
          Err(issues) => return Err(issues)
        }
      None =>
        return Err([
          @record.Issue::error(
            "missing_validation_window_end", "validation window end is missing",
          ),
        ])
    }
    if start >= end {
      return Err([
        @record.Issue::error(
          "invalid_validation_window", "validation window must satisfy start < end",
        ),
      ])
    }
    match previous_end {
      Some(previous) =>
        if start < previous {
          return Err([
            @record.Issue::error(
              "invalid_validation_windows", "validation windows must be ordered and non-overlapping",
            ),
          ])
        }
      None => ()
    }
    previous_end = Some(end)
    windows.push(ValidationWindow::new(id, start, end))
  }
  Ok(TimeConfig::new(interval, unit, epoch, gap, windows))
}

///|
fn parse_safe_time_int64(
  json : Json,
  field : String,
) -> Result[Int64, Array[@record.Issue]] {
  guard json is Number(value, ..) else {
    return Err([
      @record.Issue::error(
        "invalid_time_\{field}",
        "\{field} must be a safe integer",
      ),
    ])
  }
  let max_safe = 9007199254740991.0
  if value != value || value < -max_safe || value > max_safe {
    return Err([
      @record.Issue::error(
        "unsafe_time_\{field}",
        "\{field} must be within the safe JSON integer range",
      ),
    ])
  }
  let converted = value.to_int64()
  if converted.to_double() != value {
    return Err([
      @record.Issue::error(
        "invalid_time_\{field}",
        "\{field} must be an integer",
      ),
    ])
  }
  Ok(converted)
}

///|
fn parse_leakage_rules(
  obj : Map[String, Json],
) -> Result[Array[LeakageRule], Array[@record.Issue]] {
  guard obj.get("rules") is Some(Array(items)) else {
    return Err([
      @record.Issue::error("missing_rules", "rules must be a non-empty array"),
    ])
  }
  if items.length() == 0 {
    return Err([
      @record.Issue::error("missing_rules", "rules must be a non-empty array"),
    ])
  }
  let rules : Array[LeakageRule] = []
  let ids : Map[String, Bool] = Map([])
  for item in items {
    guard item is Object(rule_obj) else {
      return Err([
        @record.Issue::error("invalid_rule", "rules must contain objects"),
      ])
    }
    let id = match rule_obj.get("id") {
      Some(String(value)) if value != "" => value
      Some(String(_)) =>
        return Err([
          @record.Issue::error("invalid_rule_id", "rule id cannot be empty"),
        ])
      Some(_) =>
        return Err([
          @record.Issue::error("invalid_rule_id", "rule id must be a string"),
        ])
      None =>
        return Err([
          @record.Issue::error("missing_rule_id", "rule id is missing"),
        ])
    }
    if ids.contains(id) {
      return Err([
        @record.Issue::error("duplicate_rule_id", "duplicate rule id: \{id}"),
      ])
    }
    ids[id] = true
    let kind = match rule_obj.get("type") {
      Some(String("exact_key")) => ExactKey
      Some(String("text_jaccard")) => TextJaccard
      Some(String("interval_overlap")) => IntervalOverlap
      Some(String(value)) =>
        return Err([
          @record.Issue::error(
            "invalid_rule_type",
            "invalid rule type: \{value}",
          ),
        ])
      Some(_) =>
        return Err([
          @record.Issue::error(
            "invalid_rule_type", "rule type must be a string",
          ),
        ])
      None =>
        return Err([
          @record.Issue::error("missing_rule_type", "rule type is missing"),
        ])
    }
    match kind {
      ExactKey => {
        let key = match
          required_non_empty_string(rule_obj, "key", "invalid_rule_key") {
          Ok(value) => value
          Err(issues) => return Err(issues)
        }
        rules.push({
          id,
          kind,
          key: Some(key),
          q: 0,
          threshold_bp: 0,
          source_key: None,
          interval: None,
        })
      }
      TextJaccard => {
        let q = match
          parse_integer(
            rule_obj, "q", 3, "invalid_text_q", "text q must be a positive integer",
          ) {
          Ok(value) => value
          Err(issues) => return Err(issues)
        }
        let threshold_bp = match
          parse_integer(
            rule_obj, "threshold_bp", 8000, "invalid_text_threshold_bp", "text threshold_bp must be an integer",
          ) {
          Ok(value) => value
          Err(issues) => return Err(issues)
        }
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
        rules.push({
          id,
          kind,
          key: None,
          q,
          threshold_bp,
          source_key: None,
          interval: None,
        })
      }
      IntervalOverlap => {
        let source_key = match
          required_non_empty_string(
            rule_obj, "source_key", "invalid_rule_source_key",
          ) {
          Ok(value) => value
          Err(issues) => return Err(issues)
        }
        let interval = match
          required_non_empty_string(
            rule_obj, "interval", "invalid_rule_interval",
          ) {
          Ok(value) => value
          Err(issues) => return Err(issues)
        }
        rules.push({
          id,
          kind,
          key: None,
          q: 0,
          threshold_bp: 0,
          source_key: Some(source_key),
          interval: Some(interval),
        })
      }
    }
  }
  rules.sort_by((left, right) => left.id().lexical_compare(right.id()))
  Ok(rules)
}

///|
fn required_non_empty_string(
  obj : Map[String, Json],
  field : String,
  code : String,
) -> Result[String, Array[@record.Issue]] {
  match obj.get(field) {
    Some(String(value)) if value != "" => Ok(value)
    Some(String(_)) =>
      Err([@record.Issue::error(code, "field \{field} cannot be empty")])
    Some(_) =>
      Err([@record.Issue::error(code, "field \{field} must be a string")])
    None => Err([@record.Issue::error(code, "field \{field} is missing")])
  }
}

///|
fn parse_non_negative_uint(
  obj : Map[String, Json],
  field : String,
  default_value : UInt,
  code : String,
) -> Result[UInt, Array[@record.Issue]] {
  match obj.get(field) {
    None => Ok(default_value)
    Some(Number(value, ..)) => {
      let max_int = 2147483647.0
      if value != value || value < 0.0 || value > max_int {
        return Err([
          @record.Issue::error(
            code,
            "\{field} must be a non-negative integer within the supported range",
          ),
        ])
      }
      let integer = value.to_int()
      if integer < 0 || integer.to_double() != value {
        Err([
          @record.Issue::error(code, "\{field} must be a non-negative integer"),
        ])
      } else {
        Ok(integer.reinterpret_as_uint())
      }
    }
    Some(_) => Err([@record.Issue::error(code, "\{field} must be a number")])
  }
}

///|
fn parse_integer(
  obj : Map[String, Json],
  field : String,
  default_value : Int,
  code : String,
  message : String,
) -> Result[Int, Array[@record.Issue]] {
  match obj.get(field) {
    None => Ok(default_value)
    Some(Number(value, ..)) => {
      let min_int = -2147483648.0
      let max_int = 2147483647.0
      if value != value || value < min_int || value > max_int {
        return Err([@record.Issue::error(code, message)])
      }
      let integer = value.to_int()
      if integer.to_double() != value {
        Err([@record.Issue::error(code, message)])
      } else {
        Ok(integer)
      }
    }
    Some(_) => Err([@record.Issue::error(code, message)])
  }
}

///|
fn parse_v2_partitions(
  obj : Map[String, Json],
) -> Result[Array[Partition], Array[@record.Issue]] {
  let items = match obj.get("partitions") {
    Some(Array(value)) => value
    Some(_) =>
      return Err([
        @record.Issue::error(
          "invalid_partitions", "partitions must be an array",
        ),
      ])
    None =>
      return Err([
        @record.Issue::error(
          "missing_partitions", "holdout partitions are required",
        ),
      ])
  }
  if items.length() < 2 || items.length() > 8 {
    return Err([
      @record.Issue::error(
        "invalid_partitions", "holdout must have 2 to 8 partitions",
      ),
    ])
  }
  let parsed : Array[Partition] = []
  let names : Map[String, Bool] = Map([])
  for item in items {
    guard item is Object(partition_obj) else {
      return Err([
        @record.Issue::error(
          "invalid_partition", "partition entries must be objects",
        ),
      ])
    }
    let name = match
      required_non_empty_string(partition_obj, "name", "invalid_partition_name") {
      Ok(value) => value
      Err(issues) => return Err(issues)
    }
    if names.contains(name) {
      return Err([
        @record.Issue::error(
          "invalid_partition_name", "partition names must be unique and non-empty",
        ),
      ])
    }
    names[name] = true
    let weight = match
      parse_integer(
        partition_obj, "weight", 0, "invalid_partition_weight", "partition weight must be an integer",
      ) {
      Ok(value) => value
      Err(issues) => return Err(issues)
    }
    if !partition_obj.contains("weight") {
      return Err([
        @record.Issue::error(
          "missing_partition_weight", "partition weight is missing",
        ),
      ])
    }
    if weight <= 0 {
      return Err([
        @record.Issue::error(
          "invalid_partition_weight", "partition weights must be positive",
        ),
      ])
    }
    parsed.push(Partition::new(name, weight))
  }
  // Individual weights remain `Int` for the compatible public `Partition`
  // API.  All multi-weight arithmetic happens in the planning/export paths as
  // `BigInt`, so a valid set must not be rejected merely because its total is
  // larger than an `Int`.
  Ok(parsed)
}
