///|
/// Kubernetes label and field *selectors*.
///
/// A selector is a comma-separated conjunction of requirements. Each
/// requirement has one of six forms:
///
/// | Syntax                | Meaning                                  |
/// | --------------------- | ---------------------------------------- |
/// | `key=value`, `key==v` | equal                                    |
/// | `key!=value`          | not equal                                |
/// | `key in (a,b)`        | one of                                   |
/// | `key notin (a,b)`     | none of                                  |
/// | `key`                 | exists                                   |
/// | `!key`                | does not exist                           |
///
/// Two details that clients routinely get wrong and that this module pins down:
///
/// * A comma inside `(...)` separates set members, not requirements, so
///   `tier in (a,b),app=web` is two requirements rather than three.
/// * `key!=value` and `key notin (…)` also match objects that do not carry the
///   label at all. Kubernetes treats "absent" as "not equal", and a client that
///   requires the key to be present silently drops objects the API server would
///   have returned.

///|
/// The operator of a single selector requirement.
pub(all) enum SelectorOperator {
  // `key=value` / `key==value`
  Equal
  // `key!=value`
  NotEqual
  // `key in (a,b)`
  InSet
  // `key notin (a,b)`
  NotInSet
  // `key`
  Exists
  // `!key`
  NotExists
} derive(Eq, @debug.Debug)

///|
/// One requirement of a selector.
pub(all) struct Requirement {
  key : String
  op : SelectorOperator
  values : Array[String]
} derive(@debug.Debug)

///|
/// A parsed selector: all requirements must hold for an object to match.
pub(all) struct Selector {
  requirements : Array[Requirement]
} derive(@debug.Debug)

///|
/// A selector that matches everything.
pub fn Selector::empty() -> Selector {
  { requirements: [], }
}

///|
/// True when the selector has no requirements, i.e. it matches everything.
pub fn Selector::is_empty(self : Selector) -> Bool {
  self.requirements.length() == 0
}

///|
/// Parse a label selector such as `app=web,tier in (frontend,backend),!debug`.
pub fn Selector::parse_labels(text : String) -> Selector raise KubeError {
  parse_selector(text, true)
}

///|
/// Parse a field selector such as `spec.nodeName=node-1,status.phase!=Failed`.
///
/// Field selectors support only `=`, `==` and `!=`; the set and existence forms
/// are rejected because the API server does not accept them.
pub fn Selector::parse_fields(text : String) -> Selector raise KubeError {
  parse_selector(text, false)
}

///|
/// True when every requirement holds for `labels`.
pub fn Selector::matches(self : Selector, labels : Map[String, String]) -> Bool {
  for requirement in self.requirements {
    if !requirement.matches(labels) {
      return false
    }
  }
  true
}

///|
/// Render the selector back to its canonical query-string form.
pub fn Selector::to_string(self : Selector) -> String {
  let sb = StringBuilder()
  let mut first = true
  for requirement in self.requirements {
    if !first {
      sb.write_char(',')
    }
    first = false
    sb.write_string(requirement.to_string())
  }
  sb.to_string()
}

///|
/// True when one requirement holds for `labels`.
pub fn Requirement::matches(
  self : Requirement,
  labels : Map[String, String],
) -> Bool {
  match self.op {
    Equal =>
      match labels.get(self.key) {
        Some(value) => value == self.values[0]
        None => false
      }
    NotEqual =>
      match labels.get(self.key) {
        Some(value) => value != self.values[0]
        None => true
      }
    InSet =>
      match labels.get(self.key) {
        Some(value) => contains_string(self.values, value)
        None => false
      }
    NotInSet =>
      match labels.get(self.key) {
        Some(value) => !contains_string(self.values, value)
        None => true
      }
    Exists =>
      match labels.get(self.key) {
        Some(_) => true
        None => false
      }
    NotExists =>
      match labels.get(self.key) {
        Some(_) => false
        None => true
      }
  }
}

///|
/// Render one requirement.
pub fn Requirement::to_string(self : Requirement) -> String {
  match self.op {
    Equal => self.key + "=" + self.values[0]
    NotEqual => self.key + "!=" + self.values[0]
    InSet => self.key + " in (" + join_strings(self.values) + ")"
    NotInSet => self.key + " notin (" + join_strings(self.values) + ")"
    Exists => self.key
    NotExists => "!" + self.key
  }
}

///|
fn join_strings(values : Array[String]) -> String {
  let sb = StringBuilder()
  let mut first = true
  for value in values {
    if !first {
      sb.write_char(',')
    }
    first = false
    sb.write_string(value)
  }
  sb.to_string()
}

///|
fn contains_string(values : Array[String], needle : String) -> Bool {
  for value in values {
    if value == needle {
      return true
    }
  }
  false
}

///|
/// Split on top-level commas only: a comma inside `(...)` belongs to a set.
fn split_requirements(chars : Array[Char]) -> Array[(Int, Int)] {
  let ranges : Array[(Int, Int)] = []
  let mut depth = 0
  let mut start = 0
  let mut i = 0
  let n = chars.length()
  while i < n {
    let c = chars[i]
    if c == '(' {
      depth = depth + 1
    } else if c == ')' {
      if depth > 0 {
        depth = depth - 1
      }
    } else if c == ',' && depth == 0 {
      ranges.push((start, i))
      start = i + 1
    }
    i = i + 1
  }
  ranges.push((start, n))
  ranges
}

///|
fn parse_selector(
  text : String,
  allow_set_forms : Bool,
) -> Selector raise KubeError {
  let chars : Array[Char] = []
  for c in text {
    chars.push(c)
  }
  let selector : Selector = { requirements: [], }
  if chars.length() == 0 {
    return selector
  }
  for range in split_requirements(chars) {
    let (start, end) = trim_range(chars, range.0, range.1)
    if start == end {
      raise KubeError::Parse("empty selector requirement in '" + text + "'")
    }
    let requirement = parse_requirement(chars, start, end, allow_set_forms)
    selector.requirements.push(requirement)
  }
  selector
}

///|
fn parse_requirement(
  chars : Array[Char],
  start : Int,
  end : Int,
  allow_set_forms : Bool,
) -> Requirement raise KubeError {
  let text = slice(chars, start, end)
  if chars[start] == '!' {
    if !allow_set_forms {
      raise KubeError::Parse(
        "field selectors do not support existence tests: '" + text + "'",
      )
    }
    let (k_start, k_end) = trim_range(chars, start + 1, end)
    if k_start == k_end {
      raise KubeError::Parse(
        "existence requirement without a key: '" + text + "'",
      )
    }
    let key = slice(chars, k_start, k_end)
    validate_key(key)
    return { key, op: NotExists, values: [], }
  }
  let found = find_operator(chars, start, end)
  match found {
    Some(found_op) => {
      let (index, op) = found_op
      let (k_start, k_end) = trim_range(chars, start, index)
      if k_start == k_end {
        raise KubeError::Parse("requirement without a key: '" + text + "'")
      }
      let key = slice(chars, k_start, k_end)
      validate_key(key)
      let (v_start, v_end) = trim_range(
        chars,
        index + op_width(chars, index, end),
        end,
      )
      if v_start == v_end {
        // `key=` means "equal to the empty value", which is legal.
        return { key, op, values: [""], }
      }
      let value = slice(chars, v_start, v_end)
      if value.contains(",") || value.contains(")") || value.contains("(") {
        raise KubeError::Parse(
          "selector value contains a reserved character: '" + value + "'",
        )
      }
      validate_value(value)
      { key, op, values: [value], }
    }
    None => {
      if !allow_set_forms {
        raise KubeError::Parse(
          "field selector must use =, == or !=: '" + text + "'",
        )
      }
      parse_set_requirement(chars, start, end, text)
    }
  }
}

///|
/// Locate the first equality operator, if any, returning its index and kind.
fn find_operator(
  chars : Array[Char],
  start : Int,
  end : Int,
) -> (Int, SelectorOperator)? {
  let mut i = start
  while i < end {
    if chars[i] == '!' && i + 1 < end && chars[i + 1] == '=' {
      return Some((i, NotEqual))
    }
    if chars[i] == '=' {
      return Some((i, Equal))
    }
    i = i + 1
  }
  None
}

///|
/// How many characters the operator spelling occupies starting at `index`;
/// `==` occupies two, a single `=` occupies one.
fn op_width(chars : Array[Char], index : Int, end : Int) -> Int {
  if index + 1 < end && chars[index + 1] == '=' {
    2
  } else {
    1
  }
}

///|
/// Parse `key in (a,b)` / `key notin (a,b)`.
fn parse_set_requirement(
  chars : Array[Char],
  start : Int,
  end : Int,
  text : String,
) -> Requirement raise KubeError {
  let mut key_end = start
  while key_end < end && chars[key_end] != ' ' && chars[key_end] != '\t' {
    key_end = key_end + 1
  }
  let key = slice(chars, start, key_end)
  validate_key(key)
  let mut cursor = key_end
  while cursor < end && (chars[cursor] == ' ' || chars[cursor] == '\t') {
    cursor = cursor + 1
  }
  if cursor >= end {
    // A bare key is the existence form.
    return { key, op: Exists, values: [], }
  }
  let op_start = cursor
  while cursor < end &&
        chars[cursor] != ' ' &&
        chars[cursor] != '\t' &&
        chars[cursor] != '(' {
    cursor = cursor + 1
  }
  let word = slice(chars, op_start, cursor)
  let mut op = InSet
  if word == "in" {
    op = InSet
  } else if word == "notin" {
    op = NotInSet
  } else {
    raise KubeError::Parse("unsupported selector form: '" + text + "'")
  }
  while cursor < end && (chars[cursor] == ' ' || chars[cursor] == '\t') {
    cursor = cursor + 1
  }
  let parens = find_set_parens(chars, cursor, end, text)
  let (open, close) = parens
  let values = parse_set_values(chars, open + 1, close, text)
  { key, op, values, }
}

///|
/// Find the `(` … `)` pair that closes a set requirement.
fn find_set_parens(
  chars : Array[Char],
  start : Int,
  end : Int,
  text : String,
) -> (Int, Int) raise KubeError {
  if start >= end || chars[start] != '(' {
    raise KubeError::Parse(
      "unterminated set in selector requirement: '" + text + "'",
    )
  }
  let open = start
  let mut depth = 1
  let mut j = open + 1
  while j < end {
    if chars[j] == '(' {
      depth = depth + 1
    } else if chars[j] == ')' {
      depth = depth - 1
      if depth == 0 {
        return (open, j)
      }
    }
    j = j + 1
  }
  raise KubeError::Parse(
    "unterminated set in selector requirement: '" + text + "'",
  )
}

///|
/// Split a set's contents on commas and validate each member.
fn parse_set_values(
  chars : Array[Char],
  start : Int,
  end : Int,
  text : String,
) -> Array[String] raise KubeError {
  let values : Array[String] = []
  let mut i = start
  let mut item_start = start
  while i <= end {
    if i == end || chars[i] == ',' {
      let (s, e) = trim_range(chars, item_start, i)
      if s == e {
        raise KubeError::Parse("empty value in selector set: '" + text + "'")
      }
      let value = slice(chars, s, e)
      validate_value(value)
      values.push(value)
      item_start = i + 1
    }
    i = i + 1
  }
  values
}

///|
fn trim_range(chars : Array[Char], start : Int, end : Int) -> (Int, Int) {
  let mut s = start
  let mut e = end
  while s < e && (chars[s] == ' ' || chars[s] == '\t') {
    s = s + 1
  }
  while e > s && (chars[e - 1] == ' ' || chars[e - 1] == '\t') {
    e = e - 1
  }
  (s, e)
}

///|
fn slice(chars : Array[Char], start : Int, end : Int) -> String {
  let sb = StringBuilder()
  let mut i = start
  while i < end {
    sb.write_char(chars[i])
    i = i + 1
  }
  sb.to_string()
}

///|
/// Validate a label or field key: an optional DNS-subdomain prefix, a slash, and
/// a name of at most 63 characters drawn from `[A-Za-z0-9_.-]`.
fn validate_key(key : String) -> Unit raise KubeError {
  let chars : Array[Char] = []
  for c in key {
    chars.push(c)
  }
  if chars.length() == 0 {
    raise KubeError::Parse("empty selector key")
  }
  let mut slash = -1
  let mut i = 0
  while i < chars.length() {
    if chars[i] == '/' {
      if slash >= 0 {
        raise KubeError::Parse(
          "selector key contains more than one '/': '" + key + "'",
        )
      }
      slash = i
    }
    i = i + 1
  }
  if slash >= 0 {
    let prefix = slice(chars, 0, slash)
    if prefix.length() == 0 || prefix.length() > 253 {
      raise KubeError::Parse("invalid selector key prefix: '" + key + "'")
    }
    validate_name_chars(prefix, key)
    validate_name_chars(slice(chars, slash + 1, chars.length()), key)
  } else {
    validate_name_chars(key, key)
  }
}

///|
/// `[A-Za-z0-9]([-A-Za-z0-9_.]*[A-Za-z0-9])?`
fn validate_name_chars(text : String, key : String) -> Unit raise KubeError {
  let chars : Array[Char] = []
  for c in text {
    chars.push(c)
  }
  if chars.length() == 0 || chars.length() > 63 {
    raise KubeError::Parse(
      "selector key segment has an invalid length: '" + key + "'",
    )
  }
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    if !(is_alnum(c) || c == '-' || c == '_' || c == '.') {
      raise KubeError::Parse(
        "selector key has an invalid character: '" + key + "'",
      )
    }
    i = i + 1
  }
  if !is_alnum(chars[0]) || !is_alnum(chars[chars.length() - 1]) {
    raise KubeError::Parse(
      "selector key segment must start and end with alphanumerics: '" +
      key +
      "'",
    )
  }
}

///|
fn validate_value(value : String) -> Unit raise KubeError {
  if value.length() > 63 {
    raise KubeError::Parse(
      "selector value longer than 63 characters: '" + value + "'",
    )
  }
  if value.length() == 0 {
    return
  }
  let chars : Array[Char] = []
  for c in value {
    chars.push(c)
  }
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    if !(is_alnum(c) || c == '-' || c == '_' || c == '.') {
      raise KubeError::Parse(
        "selector value has an invalid character: '" + value + "'",
      )
    }
    i = i + 1
  }
  if !is_alnum(chars[0]) || !is_alnum(chars[chars.length() - 1]) {
    raise KubeError::Parse(
      "selector value must start and end with alphanumerics: '" + value + "'",
    )
  }
}

///|
fn is_alnum(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
}
