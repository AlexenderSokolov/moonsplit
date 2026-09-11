///|
test "fs checks reject a missing parent directory" {
  let path = "D:/Study_Works/MoonBit/moonsplit/artifacts/definitely_missing_parent"
  assert_false(@fs.path_exists(path))
  let is_dir_value = @fs.is_dir(path) catch {
    err =>
      match err {
        IOError(_) => false
      }
  }
  assert_false(is_dir_value)
}

///|
test "parent path preserves rooted subpaths" {
  assert_eq(parent_path("/missing_parent/plan"), "/missing_parent")
  assert_eq(parent_path("/newdir"), "/")
}

///|
test "version text matches the package version" {
  assert_eq(version_text(), "MoonSplit 0.2.0")
}
