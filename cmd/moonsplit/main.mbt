///|
fn usage() -> String {
  let text =
    #|MoonSplit 0.1.0
    #|
    #|Usage:
    #|  moon run cmd/moonsplit -- plan --data <records> --spec <spec> --out <dir> [--format json|jsonl]
    #|  moon run cmd/moonsplit -- audit --data <records> --spec <spec> --assignments <manifest> [--format json|jsonl]
    #|  moon run cmd/moonsplit -- demo --out <dir>
    #|  moon run cmd/moonsplit -- bench --records 100000 --speakers 20000
    #|  moon run cmd/moonsplit -- smoke --data <file>
    #|
    #|Exit codes:
    #|  0 success
    #|  2 usage, input, or read error
    #|  3 audit failure
    #|  4 output write error
    #|
  text
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 2 {
    println(usage())
    @sys.exit(2)
  }
  match args[1] {
    "--help" | "-h" => {
      println(usage())
      @sys.exit(0)
    }
    "plan" => run_plan_command(args)
    "audit" => run_audit_command(args)
    "demo" => run_demo_command(args)
    "bench" => run_bench_command(args)
    "smoke" => run_smoke_command(args)
    command => {
      println("error: unknown command: \{command}")
      println(usage())
      @sys.exit(2)
    }
  }
}

///|
fn run_plan_command(args : Array[String]) -> Unit {
  match parse_flags(args, 2, ["--data", "--spec", "--out", "--format"]) {
    Err(message) => fail_usage(message)
    Ok(flags) => {
      let data_path = require_flag(flags, "--data")
      let spec_path = require_flag(flags, "--spec")
      let out_path = require_flag(flags, "--out")
      let format = command_format(flags, data_path)
      let records = load_records(data_path, format)
      let spec = load_spec(spec_path)
      match @plan.plan_split(records, spec) {
        Err(issues) => fail_input(issues)
        Ok(plan) =>
          match write_plan_output(out_path, plan) {
            Err(message) => {
              println("error: \{message}")
              @sys.exit(4)
            }
            Ok(file_count) => {
              println("plan=ok")
              println("records=\{records.length()}")
              println("components=\{plan.components().count()}")
              println("assignments=\{plan.assignments().length()}")
              println("files=\{file_count}")
              @sys.exit(0)
            }
          }
      }
    }
  }
}

///|
fn run_audit_command(args : Array[String]) -> Unit {
  match
    parse_flags(args, 2, ["--data", "--spec", "--assignments", "--format"]) {
    Err(message) => fail_usage(message)
    Ok(flags) => {
      let data_path = require_flag(flags, "--data")
      let spec_path = require_flag(flags, "--spec")
      let assignments_path = require_flag(flags, "--assignments")
      let format = command_format(flags, data_path)
      let records = load_records(data_path, format)
      let spec = load_spec(spec_path)
      let assignments = load_assignments(assignments_path)
      match @audit.audit_split(records, spec, assignments) {
        Err(issues) => fail_input(issues)
        Ok(report) =>
          if report.is_valid() {
            println("audit=pass")
            println("records=\{records.length()}")
            println("assignments=\{assignments.length()}")
            for partition in spec.partitions() {
              match report.partition_counts().get(partition.name()) {
                Some(count) => println("\{partition.name()}=\{count}")
                None => ()
              }
            }
            @sys.exit(0)
          } else {
            println("audit=fail")
            print_issues(report.issues())
            @sys.exit(3)
          }
      }
    }
  }
}

///|
fn run_demo_command(args : Array[String]) -> Unit {
  match parse_flags(args, 2, ["--out"]) {
    Err(message) => fail_usage(message)
    Ok(flags) => {
      let out_path = require_flag(flags, "--out")
      let records = demo_records()
      let spec = demo_spec()
      match @plan.plan_split(records, spec) {
        Err(issues) => fail_input(issues)
        Ok(plan) =>
          match write_plan_output(out_path, plan) {
            Err(message) => {
              println("error: \{message}")
              @sys.exit(4)
            }
            Ok(file_count) => {
              println("demo=ok")
              println("records=\{records.length()}")
              println("components=\{plan.components().count()}")
              println("assignments=\{plan.assignments().length()}")
              println("files=\{file_count}")
              @sys.exit(0)
            }
          }
      }
    }
  }
}

///|
fn run_smoke_command(args : Array[String]) -> Unit {
  match parse_flags(args, 2, ["--data"]) {
    Err(message) => fail_usage(message)
    Ok(flags) => {
      let data_path = require_flag(flags, "--data")
      match read_text(data_path) {
        Err(message) => {
          println("error: read failed: \{message}")
          @sys.exit(2)
        }
        Ok(text) => {
          println("read_chars=\{text.length()}")
          @sys.exit(0)
        }
      }
    }
  }
}

///|
fn run_bench_command(args : Array[String]) -> Unit {
  match parse_flags(args, 2, ["--records", "--speakers"]) {
    Err(message) => fail_usage(message)
    Ok(flags) => {
      let record_count = optional_int(flags, "--records", 100000)
      let speaker_count = optional_int(flags, "--speakers", 20000)
      if record_count < 100 || speaker_count < 2 {
        fail_usage("records must be at least 100 and speakers at least 2")
      }
      let records = bench_records(record_count, speaker_count)
      let spec = balanced_spec()
      match @plan.plan_split(records, spec) {
        Err(issues) => fail_input(issues)
        Ok(plan) => {
          println("bench=ok")
          println("records=\{records.length()}")
          println("components=\{plan.components().count()}")
          println("assignments=\{plan.assignments().length()}")
          @sys.exit(0)
        }
      }
    }
  }
}

///|
fn parse_flags(
  args : Array[String],
  start : Int,
  allowed : Array[String],
) -> Result[Map[String, String], String] {
  let flags : Map[String, String] = Map([])
  let allowed_set : Map[String, Bool] = Map([])
  for name in allowed {
    allowed_set[name] = true
  }
  let mut index = start
  while index < args.length() {
    let name = args[index]
    if !allowed_set.contains(name) {
      return Err("unknown option: \{name}")
    }
    if index + 1 >= args.length() {
      return Err("missing value for \{name}")
    }
    flags[name] = args[index + 1]
    index = index + 2
  }
  Ok(flags)
}

///|
fn require_flag(flags : Map[String, String], name : String) -> String {
  match flags.get(name) {
    Some(value) => value
    None => {
      println("error: \{name} is required")
      println(usage())
      @sys.exit(2)
      ""
    }
  }
}

///|
fn command_format(
  flags : Map[String, String],
  path : String,
) -> @record.InputFormat {
  match flags.get("--format") {
    Some(value) =>
      match value {
        "json" => Json
        "jsonl" => Jsonl
        _ => {
          println("error: format must be json or jsonl")
          println(usage())
          @sys.exit(2)
          Json
        }
      }
    None => if path.to_lower().has_suffix(".jsonl") { Jsonl } else { Json }
  }
}

///|
fn load_records(
  path : String,
  format : @record.InputFormat,
) -> Array[@record.Record] {
  let text = read_text_or_exit(path)
  match @record.parse_records(text, format) {
    Err(issues) => {
      println("error: invalid input")
      print_issues(issues)
      @sys.exit(2)
      []
    }
    Ok(records) => records
  }
}

///|
fn load_spec(path : String) -> @spec.SplitSpec {
  let text = read_text_or_exit(path)
  match @spec.parse_spec(text) {
    Err(issues) => {
      println("error: invalid input")
      print_issues(issues)
      @sys.exit(2)
      demo_spec()
    }
    Ok(spec) => spec
  }
}

///|
fn load_assignments(path : String) -> Array[@record.Assignment] {
  let text = read_text_or_exit(path)
  match @record.parse_assignments(text) {
    Err(issues) => {
      println("error: invalid input")
      print_issues(issues)
      @sys.exit(2)
      []
    }
    Ok(assignments) => assignments
  }
}

///|
fn write_plan_output(
  out_path : String,
  plan : @plan.SplitPlan,
) -> Result[Int, String] {
  if @fs.path_exists(out_path) {
    return Err("output path already exists: \{out_path}")
  }
  let parent = parent_path(out_path)
  if !@fs.path_exists(parent) {
    return Err("output parent directory does not exist: \{parent}")
  }
  let parent_is_dir = @fs.is_dir(parent) catch {
    err =>
      match err {
        IOError(message) =>
          return Err("cannot inspect parent directory: \{message}")
      }
  }
  if !parent_is_dir {
    return Err("output parent directory does not exist: \{parent}")
  }
  @fs.create_dir(out_path) catch {
    err =>
      match err {
        IOError(message) =>
          return Err("cannot create output directory: \{message}")
      }
  }
  let output_is_dir = @fs.is_dir(out_path) catch {
    err =>
      match err {
        IOError(message) =>
          return Err("cannot inspect output directory: \{message}")
      }
  }
  if !output_is_dir {
    return Err("output path is not a directory: \{out_path}")
  }
  let files = [
    ("plan.json", @export.plan_json(plan)),
    ("assignments.jsonl", @export.assignments_jsonl(plan)),
    ("components.jsonl", @export.components_jsonl(plan)),
    ("report.md", @export.report_markdown(plan)),
  ]
  for file in files {
    let path = "\{out_path}/\{file.0}"
    @fs.write_string_to_file(path, file.1) catch {
      err =>
        match err {
          IOError(message) => return Err("cannot write \{path}: \{message}")
        }
    }
  }
  Ok(4)
}

///|
fn parent_path(path : String) -> String {
  let normal = StringBuilder()
  for ch in path {
    if ch == '\\' {
      normal <+ "/"
    } else {
      normal <+ "\{ch}"
    }
  }
  let parts = normal.to_string().split("/").to_array()
  if parts.length() <= 1 {
    "."
  } else if parts[0].to_owned() == "" {
    let mut parent = ""
    for index = 1; index < parts.length() - 1; index = index + 1 {
      parent = parent + "/" + parts[index].to_owned()
    }
    if parent == "" {
      "/"
    } else {
      parent
    }
  } else {
    let mut parent = parts[0].to_owned()
    for index = 1; index < parts.length() - 1; index = index + 1 {
      parent = parent + "/" + parts[index].to_owned()
    }
    parent
  }
}

///|
fn demo_records() -> Array[@record.Record] {
  let records : Array[@record.Record] = []
  for index = 0; index < 20; index = index + 1 {
    let keys : Map[String, String] = Map([])
    keys["speaker_id"] = "speaker_\{index}"
    let label = if index % 2 == 0 { "positive" } else { "negative" }
    records.push(@record.Record::new("record_\{index}", Some(label), keys))
  }
  records
}

///|
fn demo_spec() -> @spec.SplitSpec {
  let partitions = [
    @spec.Partition::new("train", 8),
    @spec.Partition::new("validation", 1),
    @spec.Partition::new("test", 1),
  ]
  @spec.SplitSpec::new(Holdout, ["speaker_id"], 42U, false, 500, partitions, 0)
}

///|
fn balanced_spec() -> @spec.SplitSpec {
  @spec.SplitSpec::new(
    Holdout,
    ["speaker_id"],
    42U,
    false,
    500,
    [
      @spec.Partition::new("train", 8),
      @spec.Partition::new("validation", 1),
      @spec.Partition::new("test", 1),
    ],
    0,
  )
}

///|
fn bench_records(count : Int, speaker_count : Int) -> Array[@record.Record] {
  let records : Array[@record.Record] = []
  for index = 0; index < count; index = index + 1 {
    let keys : Map[String, String] = Map([])
    keys["speaker_id"] = "speaker_\{index % speaker_count}"
    keys["utterance_id"] = "utterance_\{index}"
    let label = if index % 2 == 0 { "positive" } else { "negative" }
    records.push(@record.Record::new("record_\{index}", Some(label), keys))
  }
  records
}

///|
fn optional_int(
  flags : Map[String, String],
  name : String,
  default_value : Int,
) -> Int {
  match flags.get(name) {
    Some(value) => parse_int(value)
    None => default_value
  }
}

///|
fn parse_int(value : String) -> Int {
  let parsed = @string.parse_int(value) catch {
    _ => {
      println("error: invalid integer: \{value}")
      println(usage())
      @sys.exit(2)
      0
    }
  }
  parsed
}

///|
fn read_text(path : String) -> Result[String, String] {
  let text = @fs.read_file_to_string(path) catch {
    err =>
      match err {
        IOError(message) => return Err(message)
      }
  }
  Ok(text)
}

///|
fn read_text_or_exit(path : String) -> String {
  match read_text(path) {
    Ok(text) => text
    Err(message) => {
      println("error: read failed: \{message}")
      @sys.exit(2)
      ""
    }
  }
}

///|
fn fail_usage(message : String) -> Unit {
  println("error: \{message}")
  println(usage())
  @sys.exit(2)
}

///|
fn fail_input(issues : Array[@record.Issue]) -> Unit {
  println("error: invalid input")
  print_issues(issues)
  @sys.exit(2)
}

///|
fn print_issues(issues : Array[@record.Issue]) -> Unit {
  for issue in issues {
    match issue.line() {
      Some(line) =>
        println("- [\{issue.code()}] line \{line}: \{issue.message()}")
      None => println("- [\{issue.code()}] \{issue.message()}")
    }
  }
}
