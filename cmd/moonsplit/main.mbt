///|
priv enum LoadedCliSpec {
  V1CliSpec(@spec.SplitSpec)
  V2CliSpec(@spec.V2Spec)
}

///|
fn usage() -> String {
  let text =
    #|MoonSplit 0.3.0
    #|
    #|Usage:
    #|  moon run cmd/moonsplit -- plan --data <records> --spec <spec> --out <dir> [--format json|jsonl]
    #|  moon run cmd/moonsplit -- audit --data <records> --spec <spec> (--assignments <manifest> | --roles <roles.jsonl>) [--format json|jsonl] [--report text|json]
    #|  moon run cmd/moonsplit -- normalize-spec --spec <spec>
    #|  moon run cmd/moonsplit -- validate --data <records> --spec <spec> [--format json|jsonl]
    #|  moon run cmd/moonsplit -- demo --out <dir>
    #|  moon run cmd/moonsplit -- bench --mode exact|interval|text --records <count> [--speakers <count>]
    #|  moon run cmd/moonsplit -- smoke --data <file>
    #|  moon run cmd/moonsplit -- --version | version
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
fn version_text() -> String {
  "MoonSplit 0.3.0"
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
    "--version" => {
      println(version_text())
      @sys.exit(0)
    }
    "version" => {
      println(version_text())
      @sys.exit(0)
    }
    "plan" => run_plan_command(args)
    "audit" => run_audit_command(args)
    "normalize-spec" => run_normalize_spec_command(args)
    "validate" => run_validate_command(args)
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
fn run_normalize_spec_command(args : Array[String]) -> Unit {
  match parse_flags(args, 2, ["--spec"]) {
    Err(message) => fail_usage(message)
    Ok(flags) => {
      let spec_path = require_flag(flags, "--spec")
      match load_any_spec(spec_path) {
        V1CliSpec(spec) => println(spec.to_json())
        V2CliSpec(spec) => println(@export.v2_spec_json(spec))
      }
      @sys.exit(0)
    }
  }
}

///|
fn run_validate_command(args : Array[String]) -> Unit {
  match parse_flags(args, 2, ["--data", "--spec", "--format"]) {
    Err(message) => fail_usage(message)
    Ok(flags) => {
      let data_path = require_flag(flags, "--data")
      let spec_path = require_flag(flags, "--spec")
      let format = command_format(flags, data_path)
      match load_any_spec(spec_path) {
        V1CliSpec(spec) => {
          let records = load_records(data_path, format)
          match @plan.plan_split(records, spec) {
            Err(issues) => fail_input(issues)
            Ok(plan) => print_v1_validation(records.length(), plan)
          }
        }
        V2CliSpec(spec) => {
          let records = load_v2_records(data_path, format)
          match spec.kind() {
            GroupedHoldout | GroupedKFold =>
              match @plan.plan_split_with_rules(records, spec) {
                Err(issues) => fail_input(issues)
                Ok(plan) => {
                  println("validate=ok")
                  println("schema_version=2")
                  println("records=\{records.length()}")
                  println("components=\{plan.components().count()}")
                  println("assignments=\{plan.assignments().length()}")
                  println("warnings=\{plan.warnings().length()}")
                  @sys.exit(0)
                }
              }
            TimeForward =>
              match @temporal.plan_temporal(records, spec) {
                Err(issues) => fail_input(issues)
                Ok(plan) => {
                  println("validate=ok")
                  println("schema_version=2")
                  println("records=\{records.length()}")
                  println("components=\{plan.components().count()}")
                  println("roles=\{plan.roles().length()}")
                  @sys.exit(0)
                }
              }
          }
        }
      }
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
      match load_any_spec(spec_path) {
        V1CliSpec(spec) => {
          let records = load_records(data_path, format)
          match @plan.plan_split(records, spec) {
            Err(issues) => fail_input(issues)
            Ok(plan) => finish_v1_plan_output(out_path, records.length(), plan)
          }
        }
        V2CliSpec(spec) => {
          let records = load_v2_records(data_path, format)
          match spec.kind() {
            GroupedHoldout | GroupedKFold =>
              match @plan.plan_split_with_rules(records, spec) {
                Err(issues) => fail_input(issues)
                Ok(plan) =>
                  match
                    @audit.audit_split_with_rules(
                      records,
                      spec,
                      plan.assignments(),
                    ) {
                    Err(issues) => fail_input(issues)
                    Ok(audit) =>
                      match write_rule_plan_output(out_path, plan, audit) {
                        Err(message) => fail_output(message)
                        Ok(file_count) => {
                          println("plan=ok")
                          println("schema_version=2")
                          println("records=\{records.length()}")
                          println("components=\{plan.components().count()}")
                          println("assignments=\{plan.assignments().length()}")
                          println("files=\{file_count}")
                          @sys.exit(0)
                        }
                      }
                  }
              }
            TimeForward =>
              match @temporal.plan_temporal(records, spec) {
                Err(issues) => fail_input(issues)
                Ok(plan) =>
                  match @temporal.audit_temporal(records, spec, plan.roles()) {
                    Err(issues) => fail_input(issues)
                    Ok(audit) =>
                      match
                        write_temporal_plan_output(out_path, plan, spec, audit) {
                        Err(message) => fail_output(message)
                        Ok(file_count) => {
                          println("plan=ok")
                          println("schema_version=2")
                          println("records=\{records.length()}")
                          println("components=\{plan.components().count()}")
                          println("roles=\{plan.roles().length()}")
                          println("files=\{file_count}")
                          @sys.exit(0)
                        }
                      }
                  }
              }
          }
        }
      }
    }
  }
}

///|
fn run_audit_command(args : Array[String]) -> Unit {
  match
    parse_flags(args, 2, [
      "--data", "--spec", "--assignments", "--roles", "--format", "--report",
    ]) {
    Err(message) => fail_usage(message)
    Ok(flags) => {
      let data_path = require_flag(flags, "--data")
      let spec_path = require_flag(flags, "--spec")
      let format = command_format(flags, data_path)
      let report_format = command_report_format(flags)
      match load_any_spec(spec_path) {
        V1CliSpec(spec) => {
          if flags.contains("--roles") {
            fail_usage("--roles is only valid for time_forward")
          }
          let assignments_path = require_flag(flags, "--assignments")
          let records = load_records(data_path, format)
          let assignments = load_assignments(assignments_path)
          match @audit.audit_split(records, spec, assignments) {
            Err(issues) => fail_input(issues)
            Ok(report) =>
              if report_format == "json" {
                println(
                  @export.audit_report_json(
                    report,
                    spec,
                    records.length(),
                    assignments.length(),
                  ),
                )
                exit_after_audit(report.is_valid())
              } else {
                print_v1_audit(
                  report,
                  spec,
                  records.length(),
                  assignments.length(),
                )
              }
          }
        }
        V2CliSpec(spec) => {
          let records = load_v2_records(data_path, format)
          match spec.kind() {
            GroupedHoldout | GroupedKFold => {
              if flags.contains("--roles") {
                fail_usage("--roles is only valid for time_forward")
              }
              let assignments_path = require_flag(flags, "--assignments")
              let assignments = load_assignments(assignments_path)
              match @audit.audit_split_with_rules(records, spec, assignments) {
                Err(issues) => fail_input(issues)
                Ok(report) =>
                  if report_format == "json" {
                    println(
                      @export.rule_audit_report_json(
                        report,
                        records.length(),
                        assignments.length(),
                      ),
                    )
                    exit_after_audit(report.is_valid())
                  } else if report.is_valid() {
                    println("audit=pass")
                    println("schema_version=2")
                    println("records=\{records.length()}")
                    println("assignments=\{assignments.length()}")
                    @sys.exit(0)
                  } else {
                    println("audit=fail")
                    print_issues(report.issues())
                    @sys.exit(3)
                  }
              }
            }
            TimeForward => {
              if flags.contains("--assignments") {
                fail_usage("--assignments is not valid for time_forward")
              }
              let roles_path = require_flag(flags, "--roles")
              let roles = load_temporal_roles(roles_path)
              match @temporal.audit_temporal(records, spec, roles) {
                Err(issues) => fail_input(issues)
                Ok(report) =>
                  if report_format == "json" {
                    println(
                      @export.temporal_audit_report_json(
                        report,
                        records.length(),
                        roles.length(),
                      ),
                    )
                    exit_after_audit(report.is_valid())
                  } else if report.is_valid() {
                    println("audit=pass")
                    println("schema_version=2")
                    println("records=\{records.length()}")
                    println("roles=\{roles.length()}")
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
  match parse_flags(args, 2, ["--records", "--speakers", "--mode"]) {
    Err(message) => fail_usage(message)
    Ok(flags) => {
      let record_count = optional_int(flags, "--records", 100000)
      let speaker_count = optional_int(flags, "--speakers", 20000)
      let mode = flags.get("--mode").unwrap_or("exact")
      if record_count < 100 {
        fail_usage("records must be at least 100")
      }
      match mode {
        "exact" => {
          if speaker_count < 2 {
            fail_usage("speakers must be at least 2 for exact mode")
          }
          let records = bench_records(record_count, speaker_count)
          let spec = balanced_spec()
          match @plan.plan_split(records, spec) {
            Err(issues) => fail_input(issues)
            Ok(plan) => {
              println("bench=ok")
              println("mode=exact")
              println("records=\{records.length()}")
              println("components=\{plan.components().count()}")
              println("assignments=\{plan.assignments().length()}")
              @sys.exit(0)
            }
          }
        }
        "interval" => run_interval_bench(record_count)
        "text" => run_text_bench(record_count)
        _ => fail_usage("bench mode must be exact, interval, or text")
      }
    }
  }
}

///|
fn run_interval_bench(record_count : Int) -> Unit {
  let records = bench_interval_records(record_count)
  let spec = benchmark_v2_spec(
    "{\"schema_version\":2,\"kind\":\"holdout\",\"partitions\":[{\"name\":\"train\",\"weight\":8},{\"name\":\"test\",\"weight\":2}],\"rules\":[{\"id\":\"window\",\"type\":\"interval_overlap\",\"source_key\":\"source_id\",\"interval\":\"segment\"}]}",
  )
  match @plan.plan_split_with_rules(records, spec) {
    Err(issues) => fail_input(issues)
    Ok(plan) => {
      println("bench=ok")
      println("mode=interval")
      println("records=\{records.length()}")
      println("components=\{plan.components().count()}")
      println("assignments=\{plan.assignments().length()}")
      println(
        "text_candidate_count=\{plan.components().text_candidate_count()}",
      )
      println(
        "text_comparison_count=\{plan.components().text_comparison_count()}",
      )
      @sys.exit(0)
    }
  }
}

///|
fn run_text_bench(record_count : Int) -> Unit {
  let records = bench_text_records(record_count)
  let spec = benchmark_v2_spec(
    "{\"schema_version\":2,\"kind\":\"holdout\",\"partitions\":[{\"name\":\"train\",\"weight\":8},{\"name\":\"test\",\"weight\":2}],\"rules\":[{\"id\":\"duplicate\",\"type\":\"text_jaccard\",\"q\":3,\"threshold_bp\":8000}]}",
  )
  match @plan.plan_split_with_rules(records, spec) {
    Err(issues) => fail_input(issues)
    Ok(plan) => {
      println("bench=ok")
      println("mode=text")
      println("records=\{records.length()}")
      println("components=\{plan.components().count()}")
      println("assignments=\{plan.assignments().length()}")
      println(
        "text_candidate_count=\{plan.components().text_candidate_count()}",
      )
      println(
        "text_comparison_count=\{plan.components().text_comparison_count()}",
      )
      @sys.exit(0)
    }
  }
}

///|
fn benchmark_v2_spec(source : String) -> @spec.V2Spec {
  match @spec.parse_v2_spec(source) {
    Ok(spec) => spec
    Err(issues) => {
      fail_input(issues)
      abort("fixed benchmark specification must parse")
    }
  }
}

///|
fn bench_interval_records(count : Int) -> Array[@record.V2Record] {
  let records : Array[@record.V2Record] = []
  for index = 0; index < count; index = index + 1 {
    let pair = index / 2
    let keys : Map[String, String] = Map([])
    keys["source_id"] = "source_\{pair}"
    let intervals : Map[String, @record.Interval] = Map([])
    let start = (pair * 20).to_int64()
    let interval = if index % 2 == 0 {
      @record.Interval::new(start, start + 10L)
    } else {
      @record.Interval::new(start + 5L, start + 15L)
    }
    intervals["segment"] = interval
    records.push(
      @record.V2Record::new(
        "interval_record_\{index}",
        None,
        keys,
        None,
        intervals,
      ),
    )
  }
  records
}

///|
fn bench_text_records(count : Int) -> Array[@record.V2Record] {
  let records : Array[@record.V2Record] = []
  for index = 0; index < count; index = index + 1 {
    let pair = index / 2
    let base = 0xE000 + pair * 3
    let text = String::from_array([
      base.unsafe_to_char(),
      (base + 1).unsafe_to_char(),
      (base + 2).unsafe_to_char(),
    ])
    records.push(
      @record.V2Record::new(
        "text_record_\{index}",
        None,
        Map([]),
        Some(text),
        Map([]),
      ),
    )
  }
  records
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
    if flags.contains(name) {
      return Err("duplicate option: \{name}")
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
fn command_report_format(flags : Map[String, String]) -> String {
  match flags.get("--report") {
    None => "text"
    Some("text") => "text"
    Some("json") => "json"
    Some(_) => {
      println("error: report must be text or json")
      println(usage())
      @sys.exit(2)
      "text"
    }
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
fn load_any_spec(path : String) -> LoadedCliSpec {
  let text = read_text_or_exit(path)
  match @spec.parse_spec(text) {
    Ok(spec) => V1CliSpec(spec)
    Err(_v1_issues) =>
      match @spec.parse_v2_spec(text) {
        Ok(spec) => V2CliSpec(spec)
        Err(issues) => {
          fail_input(issues)
          V1CliSpec(demo_spec())
        }
      }
  }
}

///|
fn load_v2_records(
  path : String,
  format : @record.InputFormat,
) -> Array[@record.V2Record] {
  let text = read_text_or_exit(path)
  match @record.parse_v2_records(text, format) {
    Ok(records) => records
    Err(issues) => {
      fail_input(issues)
      []
    }
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
fn load_temporal_roles(path : String) -> Array[@temporal.TemporalRole] {
  let text = read_text_or_exit(path)
  match @temporal.parse_temporal_roles(text) {
    Ok(roles) => roles
    Err(issues) => {
      fail_input(issues)
      []
    }
  }
}

///|
fn write_plan_output(
  out_path : String,
  plan : @plan.SplitPlan,
) -> Result[Int, String] {
  let mut files = [
    ("plan.json", @export.plan_json(plan)),
    ("assignments.jsonl", @export.assignments_jsonl(plan)),
    ("components.jsonl", @export.components_jsonl(plan)),
    ("report.md", @export.report_markdown(plan)),
    ("summary.json", @export.summary_json(plan)),
  ]
  if plan.kind() == KFold {
    match @export.folds_jsonl(plan) {
      Ok(manifest) => files.push(("folds.jsonl", manifest))
      Err(_) => return Err("cannot export folds manifest")
    }
  }
  write_output_files(out_path, files)
}

///|
fn write_rule_plan_output(
  out_path : String,
  plan : @plan.RuleSplitPlan,
  audit : @audit.RuleAuditReport,
) -> Result[Int, String] {
  let mut files = [
    ("plan.json", @export.rule_plan_json(plan)),
    ("assignments.jsonl", @export.rule_assignments_jsonl(plan)),
    ("components.jsonl", @export.rule_components_jsonl(plan)),
    ("report.md", @export.rule_report_markdown(plan)),
    ("summary.json", @export.rule_summary_json(plan)),
    ("evidence.jsonl", @export.rule_evidence_jsonl(plan)),
    ("audit.json", @export.rule_audit_json(audit, plan)),
  ]
  if plan.kind() == GroupedKFold {
    match @export.rule_folds_jsonl(plan) {
      Ok(manifest) => files.push(("folds.jsonl", manifest))
      Err(_) => return Err("cannot export v2 folds manifest")
    }
  }
  write_output_files(out_path, files)
}

///|
fn write_temporal_plan_output(
  out_path : String,
  plan : @temporal.TemporalPlan,
  spec : @spec.V2Spec,
  audit : @temporal.TemporalAuditReport,
) -> Result[Int, String] {
  let files = [
    ("plan.json", @export.temporal_plan_json(plan, spec)),
    ("roles.jsonl", @export.temporal_roles_jsonl(plan)),
    ("exclusions.jsonl", @export.temporal_exclusions_jsonl(plan)),
    ("components.jsonl", @export.temporal_components_jsonl(plan)),
    ("witnesses.jsonl", @export.temporal_witnesses_jsonl(plan)),
    ("summary.json", @export.temporal_summary_json(plan)),
    ("report.md", @export.temporal_report_markdown(plan)),
    ("audit.json", @export.temporal_audit_json(audit, plan)),
  ]
  write_output_files(out_path, files)
}

///|
fn write_output_files(
  out_path : String,
  files : Array[(String, String)],
) -> Result[Int, String] {
  match prepare_output_dir(out_path) {
    Err(message) => return Err(message)
    Ok(_) => ()
  }
  for file in files {
    let path = "\{out_path}/\{file.0}"
    @fs.write_string_to_file(path, file.1) catch {
      err =>
        match err {
          IOError(message) => return Err("cannot write \{path}: \{message}")
        }
    }
  }
  Ok(files.length())
}

///|
fn prepare_output_dir(out_path : String) -> Result[Unit, String] {
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
  Ok(())
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
fn print_v1_validation(record_count : Int, plan : @plan.SplitPlan) -> Unit {
  let warnings = plan.warnings()
  println("validate=ok")
  println("records=\{record_count}")
  println("components=\{plan.components().count()}")
  println("assignments=\{plan.assignments().length()}")
  println("warnings=\{warnings.length()}")
  for warning in warnings {
    println("warning=\{warning}")
  }
  @sys.exit(0)
}

///|
fn finish_v1_plan_output(
  out_path : String,
  record_count : Int,
  plan : @plan.SplitPlan,
) -> Unit {
  match write_plan_output(out_path, plan) {
    Err(message) => fail_output(message)
    Ok(file_count) => {
      println("plan=ok")
      println("records=\{record_count}")
      println("components=\{plan.components().count()}")
      println("assignments=\{plan.assignments().length()}")
      println("files=\{file_count}")
      @sys.exit(0)
    }
  }
}

///|
fn print_v1_audit(
  report : @audit.AuditReport,
  spec : @spec.SplitSpec,
  record_count : Int,
  assignment_count : Int,
) -> Unit {
  if report.is_valid() {
    println("audit=pass")
    println("records=\{record_count}")
    println("assignments=\{assignment_count}")
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

///|
fn exit_after_audit(valid : Bool) -> Unit {
  if valid {
    @sys.exit(0)
  } else {
    @sys.exit(3)
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
fn fail_output(message : String) -> Unit {
  println("error: \{message}")
  @sys.exit(4)
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
