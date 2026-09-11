///|
pub(all) enum SplitKind {
  Holdout
  KFold
} derive(Eq, Debug)

///|
pub struct Partition {
  priv name : String
  priv weight : Int
} derive(Debug)

///|
pub struct SplitSpec {
  priv kind : SplitKind
  priv isolation_keys : Array[String]
  priv seed : UInt
  priv balance_labels : Bool
  priv ratio_tolerance_bp : Int
  priv partitions : Array[Partition]
  priv k : Int
} derive(Debug)

///|
pub fn Partition::new(name : String, weight : Int) -> Partition {
  { name, weight }
}

///|
pub fn Partition::name(self : Partition) -> String {
  self.name
}

///|
pub fn Partition::weight(self : Partition) -> Int {
  self.weight
}

///|
pub fn SplitSpec::kind(self : SplitSpec) -> SplitKind {
  self.kind
}

///|
pub fn SplitSpec::isolation_keys(self : SplitSpec) -> Array[String] {
  self.isolation_keys.copy()
}

///|
pub fn SplitSpec::seed(self : SplitSpec) -> UInt {
  self.seed
}

///|
pub fn SplitSpec::balance_labels(self : SplitSpec) -> Bool {
  self.balance_labels
}

///|
pub fn SplitSpec::ratio_tolerance_bp(self : SplitSpec) -> Int {
  self.ratio_tolerance_bp
}

///|
pub fn SplitSpec::partitions(self : SplitSpec) -> Array[Partition] {
  self.partitions.copy()
}

///|
pub fn SplitSpec::k(self : SplitSpec) -> Int {
  self.k
}

///|
pub fn SplitSpec::partition_names(self : SplitSpec) -> Array[String] {
  let names : Array[String] = []
  for partition in self.partitions {
    names.push(partition.name())
  }
  names
}

///|
/// Canonical, human-readable serialization of a split specification.
pub fn SplitSpec::to_json(self : SplitSpec) -> String {
  let out = StringBuilder()
  out <+ "{\n"
  out <+ "  \"schema_version\": 1,\n"
  let kind_name = match self.kind {
    Holdout => "holdout"
    KFold => "kfold"
  }
  out <+ "  \"kind\": \"\{kind_name}\",\n"
  let isolation_keys = self.isolation_keys.copy()
  isolation_keys.sort_by((left, right) => left.lexical_compare(right))
  out <+ "  \"isolation_keys\": ["
  for index = 0; index < isolation_keys.length(); index = index + 1 {
    if index > 0 {
      out <+ ", "
    }
    out <+ "\"\{escape_json_string(isolation_keys[index])}\""
  }
  out <+ "],\n"
  out <+ "  \"seed\": \{self.seed},\n"
  out <+ "  \"balance_labels\": \{self.balance_labels},\n"
  out <+ "  \"ratio_tolerance_bp\": \{self.ratio_tolerance_bp},\n"
  match self.kind {
    Holdout => {
      out <+ "  \"partitions\": [\n"
      for index = 0; index < self.partitions.length(); index = index + 1 {
        let partition = self.partitions[index]
        out <+
          "    {\"name\": \"\{escape_json_string(partition.name())}\", \"weight\": \{partition.weight()}}"
        if index + 1 < self.partitions.length() {
          out <+ ","
        }
        out <+ "\n"
      }
      out <+ "  ]\n"
    }
    KFold => out <+ "  \"k\": \{self.k}\n"
  }
  out <+ "}"
  out.to_string()
}

///|
pub fn parse_spec(input : String) -> Result[SplitSpec, Array[@record.Issue]] {
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
    Some(Number(1.0, ..)) => ()
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
          "invalid_schema_version", "schema_version must be number 1",
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
    Some(String("holdout")) => Holdout
    Some(String("kfold")) => KFold
    Some(String(value)) =>
      return Err([
        @record.Issue::error("invalid_spec_kind", "invalid spec kind: \{value}"),
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
  let isolation_keys = match string_array_field(obj, "isolation_keys") {
    Err(issues) => return Err(issues)
    Ok(value) => value
  }
  if isolation_keys.length() < 1 || isolation_keys.length() > 8 {
    return Err([
      @record.Issue::error(
        "invalid_isolation_keys", "isolation_keys must contain 1 to 8 unique non-empty names",
      ),
    ])
  }
  let key_set : Map[String, Bool] = Map([])
  for key in isolation_keys {
    if key == "" || key_set.contains(key) {
      return Err([
        @record.Issue::error(
          "invalid_isolation_keys", "isolation_keys must contain 1 to 8 unique non-empty names",
        ),
      ])
    }
    key_set[key] = true
  }
  let seed = match obj.get("seed") {
    None => 42U
    Some(Number(value, ..)) => {
      let integer = value.to_int()
      if integer < 0 || integer.to_double() != value {
        return Err([
          @record.Issue::error(
            "invalid_seed", "seed must be a non-negative integer",
          ),
        ])
      }
      integer.reinterpret_as_uint()
    }
    Some(_) =>
      return Err([@record.Issue::error("invalid_seed", "seed must be a number")])
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
  let ratio_tolerance_bp = match obj.get("ratio_tolerance_bp") {
    None => 500
    Some(Number(value, ..)) => {
      let integer = value.to_int()
      if integer.to_double() != value {
        return Err([
          @record.Issue::error(
            "invalid_ratio_tolerance_bp", "ratio_tolerance_bp must be an integer",
          ),
        ])
      }
      integer
    }
    Some(_) =>
      return Err([
        @record.Issue::error(
          "invalid_ratio_tolerance_bp", "ratio_tolerance_bp must be an integer",
        ),
      ])
  }
  if ratio_tolerance_bp < 0 || ratio_tolerance_bp > 10000 {
    return Err([
      @record.Issue::error(
        "invalid_ratio_tolerance_bp", "ratio_tolerance_bp must be between 0 and 10000",
      ),
    ])
  }
  match kind {
    KFold => {
      let k = match obj.get("k") {
        Some(Number(value, ..)) => {
          let integer = value.to_int()
          if integer.to_double() != value {
            return Err([
              @record.Issue::error("invalid_k", "k must be an integer"),
            ])
          }
          integer
        }
        Some(_) =>
          return Err([@record.Issue::error("invalid_k", "k must be a number")])
        None => return Err([@record.Issue::error("missing_k", "k is missing")])
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
      for i = 0; i < k; i = i + 1 {
        partitions.push(Partition::new("fold_\{i}", 1))
      }
      Ok(
        SplitSpec::new(
          kind, isolation_keys, seed, balance_labels, ratio_tolerance_bp, partitions,
          k,
        ),
      )
    }
    Holdout => {
      let partitions = match obj.get("partitions") {
        None => {
          let defaults : Array[Partition] = [
            Partition::new("train", 8),
            Partition::new("validation", 1),
            Partition::new("test", 1),
          ]
          defaults
        }
        Some(Array(items)) => {
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
            let name = match partition_obj.get("name") {
              Some(String(value)) => value
              Some(_) =>
                return Err([
                  @record.Issue::error(
                    "invalid_partition_name", "partition name must be a string",
                  ),
                ])
              None =>
                return Err([
                  @record.Issue::error(
                    "missing_partition_name", "partition name is missing",
                  ),
                ])
            }
            if name == "" || names.contains(name) {
              return Err([
                @record.Issue::error(
                  "invalid_partition_name", "partition names must be unique and non-empty",
                ),
              ])
            }
            names[name] = true
            let weight = match partition_obj.get("weight") {
              Some(Number(value, ..)) => {
                let integer = value.to_int()
                if integer.to_double() != value {
                  return Err([
                    @record.Issue::error(
                      "invalid_partition_weight", "partition weight must be an integer",
                    ),
                  ])
                }
                integer
              }
              Some(_) =>
                return Err([
                  @record.Issue::error(
                    "invalid_partition_weight", "partition weight must be a number",
                  ),
                ])
              None =>
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
          if parsed.length() < 2 || parsed.length() > 8 {
            return Err([
              @record.Issue::error(
                "invalid_partitions", "holdout must have 2 to 8 partitions",
              ),
            ])
          }
          let mut weight_sum = 0
          for partition in parsed {
            weight_sum += partition.weight()
          }
          if weight_sum > 1000 {
            return Err([
              @record.Issue::error(
                "invalid_partition_weights", "partition weights sum must not exceed 1000",
              ),
            ])
          }
          parsed
        }
        Some(_) =>
          return Err([
            @record.Issue::error(
              "invalid_partitions", "partitions must be an array",
            ),
          ])
      }
      Ok(
        SplitSpec::new(
          kind, isolation_keys, seed, balance_labels, ratio_tolerance_bp, partitions,
          0,
        ),
      )
    }
  }
}

///|
fn string_array_field(
  obj : Map[String, Json],
  field : String,
) -> Result[Array[String], Array[@record.Issue]] {
  match obj.get(field) {
    Some(Array(items)) => {
      let values : Array[String] = []
      for item in items {
        match item {
          String(value) => values.push(value)
          _ =>
            return Err([
              @record.Issue::error(
                "invalid_array_field",
                "field \{field} must contain strings",
              ),
            ])
        }
      }
      Ok(values)
    }
    Some(_) =>
      Err([
        @record.Issue::error(
          "invalid_array_field",
          "field \{field} must be an array",
        ),
      ])
    None =>
      Err([
        @record.Issue::error("missing_array_field", "field \{field} is missing"),
      ])
  }
}

///|
/// Escape a string for use inside a JSON string literal.
fn escape_json_string(value : String) -> String {
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
