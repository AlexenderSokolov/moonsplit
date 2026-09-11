///|
pub(all) enum InputFormat {
  Json
  Jsonl
} derive(Eq, Debug)

///|
pub struct Issue {
  priv severity : IssueSeverity
  priv code : String
  priv message : String
  priv line : Int?
} derive(Debug)

///|
pub(all) enum IssueSeverity {
  Error
  Warning
} derive(Eq, Debug)

///|
pub struct Record {
  priv id : String
  priv label : String?
  priv keys : Map[String, String]
} derive(Debug)

///|
pub struct Assignment {
  priv id : String
  priv partition : String
} derive(Debug)

///|
pub fn Record::new(
  id : String,
  label : String?,
  keys : Map[String, String],
) -> Record {
  let copied : Map[String, String] = Map([])
  for key in keys.keys() {
    copied[key] = keys[key]
  }
  { id, label, keys: copied, }
}

///|
pub fn Record::id(self : Record) -> String {
  self.id
}

///|
pub fn Record::label(self : Record) -> String? {
  self.label
}

///|
pub fn Record::keys(self : Record) -> Map[String, String] {
  let out : Map[String, String] = Map([])
  for key in self.keys.keys() {
    out[key] = self.keys[key]
  }
  out
}

///|
pub fn Record::key(self : Record, name : String) -> String? {
  self.keys.get(name)
}

///|
pub fn Record::snapshot(self : Record) -> Record {
  Record::new(self.id, self.label, self.keys)
}

///|
pub fn Assignment::new(id : String, partition : String) -> Assignment {
  { id, partition, }
}

///|
pub fn Assignment::id(self : Assignment) -> String {
  self.id
}

///|
pub fn Assignment::partition(self : Assignment) -> String {
  self.partition
}

///|
pub fn Issue::error(code : String, message : String) -> Issue {
  { severity: Error, code, message, line: None, }
}

///|
pub fn Issue::error_at_line(
  code : String,
  message : String,
  line : Int,
) -> Issue {
  { severity: Error, code, message, line: Some(line), }
}

///|
pub fn Issue::warning(code : String, message : String) -> Issue {
  { severity: Warning, code, message, line: None, }
}

///|
pub fn Issue::severity(self : Issue) -> IssueSeverity {
  self.severity
}

///|
pub fn Issue::code(self : Issue) -> String {
  self.code
}

///|
pub fn Issue::message(self : Issue) -> String {
  self.message
}

///|
pub fn Issue::line(self : Issue) -> Int? {
  self.line
}

///|
pub fn parse_records(
  input : String,
  format : InputFormat,
) -> Result[Array[Record], Array[Issue]] {
  match format {
    Json => parse_records_json(input)
    Jsonl => parse_records_jsonl(input)
  }
}

///|
fn parse_records_json(input : String) -> Result[Array[Record], Array[Issue]] {
  let normalized = input.trim(char_set="\u{feff} \t\r\n").to_owned()
  let json = @json.parse(normalized) catch {
    err => return Err([Issue::error("invalid_json", "invalid JSON: \{err}")])
  }
  guard json is Array(items) else {
    return Err([Issue::error("invalid_shape", "expected JSON array")])
  }
  let records : Array[Record] = []
  let issues : Array[Issue] = []
  for index = 0; index < items.length(); index = index + 1 {
    match parse_record_json(items[index], index + 1) {
      Err(issue) => issues.push(issue)
      Ok(record) => records.push(record)
    }
  }
  if issues.length() > 0 {
    Err(issues)
  } else {
    validate_record_ids(records)
  }
}

///|
fn parse_records_jsonl(input : String) -> Result[Array[Record], Array[Issue]] {
  let lines = input.split("\n").to_array()
  let records : Array[Record] = []
  let issues : Array[Issue] = []
  for line_number = 1
      line_number <= lines.length()
      line_number = line_number + 1 {
    let line = lines[line_number - 1]
    let line = if line_number == 1 {
      line.trim(char_set="\u{feff} \t\r\n")
    } else {
      line.trim(char_set=" \t\r\n")
    }
    if line == "" {
      continue
    }
    let json = @json.parse(line) catch {
      err => {
        issues.push(
          Issue::error_at_line(
            "invalid_json",
            "invalid JSON on line \{line_number}: \{err}",
            line_number,
          ),
        )
        continue
      }
    }
    match parse_record_json(json, line_number) {
      Err(issue) => issues.push(issue)
      Ok(record) => records.push(record)
    }
  }
  if issues.length() > 0 {
    Err(issues)
  } else {
    validate_record_ids(records)
  }
}

///|
fn parse_record_json(json : Json, line_number : Int) -> Result[Record, Issue] {
  guard json is Object(obj) else {
    return Err(
      Issue::error_at_line("invalid_record", "expected object", line_number),
    )
  }
  let id = match obj.get("id") {
    Some(String(value)) => value
    Some(_) =>
      return Err(
        Issue::error_at_line(
          "invalid_record_id", "record id must be a string", line_number,
        ),
      )
    None =>
      return Err(
        Issue::error_at_line(
          "missing_record_id", "record id is missing", line_number,
        ),
      )
  }
  if id == "" {
    return Err(
      Issue::error_at_line(
        "empty_record_id", "record id cannot be empty", line_number,
      ),
    )
  }
  let label : String? = match obj.get("label") {
    None => None
    Some(String(value)) => Some(value)
    Some(_) =>
      return Err(
        Issue::error_at_line(
          "invalid_label", "label must be a string", line_number,
        ),
      )
  }
  guard obj.get("keys") is Some(Object(key_obj)) else {
    return Err(
      Issue::error_at_line(
        "missing_keys", "keys must be an object", line_number,
      ),
    )
  }
  let keys : Map[String, String] = Map([])
  for key in key_obj.keys() {
    match key_obj[key] {
      String(value) => keys[key] = value
      _ =>
        return Err(
          Issue::error_at_line(
            "invalid_key_value",
            "key \{key} must be a string",
            line_number,
          ),
        )
    }
  }
  Ok(Record::new(id, label, keys))
}

///|
fn validate_record_ids(
  records : Array[Record],
) -> Result[Array[Record], Array[Issue]] {
  let seen : Map[String, Int] = Map([])
  let issues : Array[Issue] = []
  for record in records {
    let id = record.id()
    match seen.get(id) {
      Some(_) =>
        issues.push(
          Issue::error("duplicate_record_id", "duplicate record id: \{id}"),
        )
      None => seen[id] = records.length()
    }
  }
  if records.length() == 0 {
    issues.push(Issue::error("empty_records", "record list is empty"))
  }
  if issues.length() > 0 {
    Err(issues)
  } else {
    Ok(records)
  }
}
