///|
pub struct Interval {
  priv start : Int64
  priv end : Int64
} derive(Debug)

///|
pub struct V2Record {
  priv id : String
  priv label : String?
  priv keys : Map[String, String]
  priv text : String?
  priv intervals : Map[String, Interval]
} derive(Debug)

///|
pub fn Interval::new(start : Int64, end : Int64) -> Interval {
  { start, end, }
}

///|
pub fn Interval::start(self : Interval) -> Int64 {
  self.start
}

///|
pub fn Interval::end(self : Interval) -> Int64 {
  self.end
}

///|
pub fn V2Record::new(
  id : String,
  label : String?,
  keys : Map[String, String],
  text : String?,
  intervals : Map[String, Interval],
) -> V2Record {
  {
    id,
    label,
    keys: copy_v2_keys(keys),
    text,
    intervals: copy_intervals(intervals),
  }
}

///|
pub fn V2Record::id(self : V2Record) -> String {
  self.id
}

///|
pub fn V2Record::label(self : V2Record) -> String? {
  self.label
}

///|
pub fn V2Record::keys(self : V2Record) -> Map[String, String] {
  copy_v2_keys(self.keys)
}

///|
pub fn V2Record::key(self : V2Record, name : String) -> String? {
  self.keys.get(name)
}

///|
pub fn V2Record::text(self : V2Record) -> String? {
  self.text
}

///|
pub fn V2Record::intervals(self : V2Record) -> Map[String, Interval] {
  copy_intervals(self.intervals)
}

///|
pub fn V2Record::interval(self : V2Record, name : String) -> Interval? {
  self.intervals.get(name)
}

///|
pub fn V2Record::snapshot(self : V2Record) -> V2Record {
  V2Record::new(self.id, self.label, self.keys, self.text, self.intervals)
}

///|
pub fn parse_v2_records(
  input : String,
  format : InputFormat,
) -> Result[Array[V2Record], Array[Issue]] {
  match format {
    Json => parse_v2_records_json(input)
    Jsonl => parse_v2_records_jsonl(input)
  }
}

///|
fn copy_v2_keys(keys : Map[String, String]) -> Map[String, String] {
  let copied : Map[String, String] = Map([])
  for key in keys.keys() {
    copied[key] = keys[key]
  }
  copied
}

///|
fn copy_intervals(intervals : Map[String, Interval]) -> Map[String, Interval] {
  let copied : Map[String, Interval] = Map([])
  for name in intervals.keys() {
    copied[name] = intervals[name]
  }
  copied
}

///|
fn parse_v2_records_json(
  input : String,
) -> Result[Array[V2Record], Array[Issue]] {
  let normalized = input.trim(char_set="\u{feff} \t\r\n").to_owned()
  let json = @json.parse(normalized) catch {
    err => return Err([Issue::error("invalid_json", "invalid JSON: \{err}")])
  }
  guard json is Array(items) else {
    return Err([Issue::error("invalid_shape", "expected JSON array")])
  }
  let records : Array[V2Record] = []
  let issues : Array[Issue] = []
  for index = 0; index < items.length(); index = index + 1 {
    match parse_v2_record_json(items[index], index + 1) {
      Ok(record) => records.push(record)
      Err(issue) => issues.push(issue)
    }
  }
  if issues.length() > 0 {
    Err(issues)
  } else {
    validate_v2_record_ids(records)
  }
}

///|
fn parse_v2_records_jsonl(
  input : String,
) -> Result[Array[V2Record], Array[Issue]] {
  let lines = input.split("\n").to_array()
  let records : Array[V2Record] = []
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
    match parse_v2_record_json(json, line_number) {
      Ok(record) => records.push(record)
      Err(issue) => issues.push(issue)
    }
  }
  if issues.length() > 0 {
    Err(issues)
  } else {
    validate_v2_record_ids(records)
  }
}

///|
fn parse_v2_record_json(
  json : Json,
  line_number : Int,
) -> Result[V2Record, Issue] {
  guard json is Object(obj) else {
    return Err(
      Issue::error_at_line("invalid_record", "expected object", line_number),
    )
  }
  let id = match obj.get("id") {
    Some(String(value)) if value != "" => value
    Some(String(_)) =>
      return Err(
        Issue::error_at_line(
          "empty_record_id", "record id cannot be empty", line_number,
        ),
      )
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
  let keys = match parse_v2_keys(obj, line_number) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let text : String? = match obj.get("text") {
    None => None
    Some(String(value)) => Some(value)
    Some(_) =>
      return Err(
        Issue::error_at_line(
          "invalid_text", "text must be a string", line_number,
        ),
      )
  }
  let intervals = match parse_intervals(obj, line_number) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok(V2Record::new(id, label, keys, text, intervals))
}

///|
fn parse_v2_keys(
  obj : Map[String, Json],
  line_number : Int,
) -> Result[Map[String, String], Issue] {
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
  Ok(keys)
}

///|
fn parse_intervals(
  obj : Map[String, Json],
  line_number : Int,
) -> Result[Map[String, Interval], Issue] {
  let intervals : Map[String, Interval] = Map([])
  match obj.get("intervals") {
    None => Ok(intervals)
    Some(Object(interval_obj)) => {
      for name in interval_obj.keys() {
        if name == "" {
          return Err(
            Issue::error_at_line(
              "empty_interval_name", "interval name cannot be empty", line_number,
            ),
          )
        }
        let interval = match
          parse_interval(interval_obj[name], name, line_number) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        intervals[name] = interval
      }
      Ok(intervals)
    }
    Some(_) =>
      Err(
        Issue::error_at_line(
          "invalid_intervals", "intervals must be an object", line_number,
        ),
      )
  }
}

///|
fn parse_interval(
  json : Json,
  name : String,
  line_number : Int,
) -> Result[Interval, Issue] {
  guard json is Object(bounds) else {
    return Err(
      Issue::error_at_line(
        "invalid_interval",
        "interval \{name} must be an object",
        line_number,
      ),
    )
  }
  let start_json = match bounds.get("start") {
    Some(value) => value
    None =>
      return Err(
        Issue::error_at_line(
          "missing_interval_start",
          "interval \{name} start is missing",
          line_number,
        ),
      )
  }
  let end_json = match bounds.get("end") {
    Some(value) => value
    None =>
      return Err(
        Issue::error_at_line(
          "missing_interval_end",
          "interval \{name} end is missing",
          line_number,
        ),
      )
  }
  let start = match
    parse_safe_json_int64(start_json, "start", name, line_number) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let end = match parse_safe_json_int64(end_json, "end", name, line_number) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if start >= end {
    return Err(
      Issue::error_at_line(
        "invalid_interval_bounds",
        "interval \{name} must satisfy start < end",
        line_number,
      ),
    )
  }
  Ok(Interval::new(start, end))
}

///|
fn parse_safe_json_int64(
  json : Json,
  field : String,
  interval_name : String,
  line_number : Int,
) -> Result[Int64, Issue] {
  guard json is Number(value, ..) else {
    return Err(
      Issue::error_at_line(
        "invalid_interval_\{field}",
        "interval \{interval_name} \{field} must be a safe integer",
        line_number,
      ),
    )
  }
  let max_safe = 9007199254740991.0
  if value != value || value < -max_safe || value > max_safe {
    return Err(
      Issue::error_at_line(
        "unsafe_interval_\{field}",
        "interval \{interval_name} \{field} must be within the safe JSON integer range",
        line_number,
      ),
    )
  }
  let converted = value.to_int64()
  if converted.to_double() != value {
    return Err(
      Issue::error_at_line(
        "invalid_interval_\{field}",
        "interval \{interval_name} \{field} must be an integer",
        line_number,
      ),
    )
  }
  Ok(converted)
}

///|
fn validate_v2_record_ids(
  records : Array[V2Record],
) -> Result[Array[V2Record], Array[Issue]] {
  let seen : Map[String, Bool] = Map([])
  let issues : Array[Issue] = []
  for record in records {
    let id = record.id()
    if seen.contains(id) {
      issues.push(
        Issue::error("duplicate_record_id", "duplicate record id: \{id}"),
      )
    } else {
      seen[id] = true
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
