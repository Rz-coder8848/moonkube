///|
/// Blackbox tests for selectors: the public API, driven through `@core` only.

///|
/// Render a parsed label selector, or `<error>` when parsing fails.
fn render(sel : String) -> String {
  @core.Selector::parse_labels(sel).to_string() catch {
    _ => "<error>"
  }
}

///|
/// `T` when the selector matches, `F` when it does not, `E` when it is invalid.
/// A distinct marker for parse errors keeps a broken parser from looking like a
/// legitimate non-match.
fn m(sel : String, labels : Map[String, String]) -> String {
  try {
    if @core.Selector::parse_labels(sel).matches(labels) {
      "T"
    } else {
      "F"
    }
  } catch {
    _ => "E"
  }
}

///|
fn rejected_label(sel : String) -> Bool {
  try {
    let _ = @core.Selector::parse_labels(sel)
    false
  } catch {
    _ => true
  }
}

///|
fn rejected_field(sel : String) -> Bool {
  try {
    let _ = @core.Selector::parse_fields(sel)
    false
  } catch {
    _ => true
  }
}

///|
/// Every requirement form survives a parse/render round trip, and `==`
/// normalizes to `=`.
test "round-trips every requirement form" {
  assert_eq(render("app=web"), "app=web")
  assert_eq(render("app==web"), "app=web")
  assert_eq(render("app!=web"), "app!=web")
  assert_eq(render("tier in (a,b)"), "tier in (a,b)")
  assert_eq(render("tier notin (a,b)"), "tier notin (a,b)")
  assert_eq(render("app"), "app")
  assert_eq(render("!app"), "!app")
  assert_eq(render("app="), "app=")
}

///|
/// A comma inside `(...)` separates set members, not requirements.
test "commas inside a set do not split requirements" {
  let selector = @core.Selector::parse_labels("tier in (a,b),app=web") catch {
    _ => @core.Selector::empty()
  }
  assert_eq(selector.requirements.length(), 2)
  assert_eq(selector.to_string(), "tier in (a,b),app=web")
}

///|
/// Whitespace around keys, operators and set members is tolerated and does not
/// leak into the rendered form.
test "whitespace is tolerated and normalized away" {
  assert_eq(render(" app = web "), "app=web")
  assert_eq(render("tier  in ( a , b )"), "tier in (a,b)")
}

///|
/// A qualified key keeps its DNS prefix.
test "qualified keys round-trip" {
  assert_eq(
    render("app.kubernetes.io/name in (web,worker)"),
    "app.kubernetes.io/name in (web,worker)",
  )
}

///|
/// Matching follows the API server, including the rule that `!=` and `notin`
/// match objects which do not carry the label at all.
test "matching semantics" {
  let labels : Map[String, String] = { "app": "web", "tier": "frontend" }
  assert_eq(m("app=web", labels), "T")
  assert_eq(m("app=api", labels), "F")
  assert_eq(m("app!=api", labels), "T")
  assert_eq(m("app!=web", labels), "F")
  // The important one: an absent key is "not equal", so it matches.
  assert_eq(m("missing!=api", labels), "T")
  assert_eq(m("missing=api", labels), "F")
  assert_eq(m("tier in (frontend,backend)", labels), "T")
  assert_eq(m("tier in (backend)", labels), "F")
  assert_eq(m("missing in (a)", labels), "F")
  assert_eq(m("missing notin (a)", labels), "T")
  assert_eq(m("tier notin (backend)", labels), "T")
  assert_eq(m("app", labels), "T")
  assert_eq(m("missing", labels), "F")
  assert_eq(m("!missing", labels), "T")
  assert_eq(m("!app", labels), "F")
}

///|
/// Requirements are conjoined.
test "requirements are ANDed" {
  let labels : Map[String, String] = { "app": "web", "tier": "frontend" }
  assert_eq(m("app=web,tier=frontend", labels), "T")
  assert_eq(m("app=web,tier=backend", labels), "F")
  assert_eq(m("app=web,tier in (frontend,backend),!debug", labels), "T")
  assert_eq(m("app=web,!tier", labels), "F")
}

///|
/// An empty selector matches everything.
test "empty selector matches everything" {
  let labels : Map[String, String] = { "app": "web" }
  assert_true(@core.Selector::empty().is_empty())
  assert_eq(@core.Selector::empty().to_string(), "")
  assert_eq(m("", labels), "T")
}

///|
/// Field selectors accept only the equality operators.
test "field selectors reject set and existence forms" {
  let field = @core.Selector::parse_fields(
    "spec.nodeName=node-1,status.phase!=Failed",
  ) catch {
    _ => @core.Selector::empty()
  }
  assert_eq(field.requirements.length(), 2)
  assert_eq(field.to_string(), "spec.nodeName=node-1,status.phase!=Failed")
  assert_true(rejected_field("app in (a,b)"))
  assert_true(rejected_field("app"))
  assert_true(rejected_field("!app"))
}

///|
/// Malformed selectors are rejected rather than silently dropped.
test "malformed selectors are rejected" {
  assert_true(rejected_label("=web"))
  assert_true(rejected_label("app==="))
  assert_true(rejected_label("app in ()"))
  assert_true(rejected_label("app in (a"))
  assert_true(rejected_label("app web"))
  assert_true(rejected_label("app=we b"))
  assert_true(rejected_label("!app="))
  assert_true(rejected_label("app,"))
  assert_true(rejected_label("app.kubernetes.io//name=x"))
  assert_true(rejected_label("app=-bad"))
}
