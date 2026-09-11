///|
pub fn parse_assignments(
  input : String,
) -> Result[Array[Assignment], Array[Issue]] {
  let lines = input.split("\n").to_array()
  let assignments : Array[Assignment] = []
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
            "invalid_assignment",
            "invalid assignment JSON on line \{line_number}: \{err}",
            line_number,
          ),
        )
        continue
      }
    }
    guard json is Object(obj) else {
      issues.push(
        Issue::error_at_line(
          "invalid_assignment", "assignment must be an object", line_number,
        ),
      )
      continue
    }
    let id = match obj.get("id") {
      Some(String(value)) => value
      Some(_) => {
        issues.push(
          Issue::error_at_line(
            "invalid_assignment_id", "assignment id must be a string", line_number,
          ),
        )
        continue
      }
      None => {
        issues.push(
          Issue::error_at_line(
            "missing_assignment_id", "assignment id is missing", line_number,
          ),
        )
        continue
      }
    }
    if id == "" {
      issues.push(
        Issue::error_at_line(
          "empty_assignment_id", "assignment id cannot be empty", line_number,
        ),
      )
      continue
    }
    let partition = match obj.get("partition") {
      Some(String(value)) => value
      Some(_) => {
        issues.push(
          Issue::error_at_line(
            "invalid_assignment_partition", "assignment partition must be a string",
            line_number,
          ),
        )
        continue
      }
      None => {
        issues.push(
          Issue::error_at_line(
            "missing_assignment_partition", "assignment partition is missing", line_number,
          ),
        )
        continue
      }
    }
    if partition == "" {
      issues.push(
        Issue::error_at_line(
          "empty_assignment_partition", "assignment partition cannot be empty", line_number,
        ),
      )
      continue
    }
    assignments.push(Assignment::new(id, partition))
  }
  if issues.length() > 0 {
    Err(issues)
  } else {
    Ok(assignments)
  }
}
