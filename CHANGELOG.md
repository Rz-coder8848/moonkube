# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-10-17

Initial development. Only the `core` package exists so far; the transport,
resource-model, client and controller layers described in the README are not
implemented yet.

### Added

- `core/quantity`: exact Kubernetes resource quantities.
  - Values are stored as `coefficient * 10^exponent` over an arbitrary-precision
    integer, so `2Ei`, `1e100` and `0.1` are lossless and nothing overflows.
  - Accepts binary SI (`Ki` .. `Ei`), decimal SI (`n`, `u`, `m`, `k`, `M`, `G`,
    `T`, `P`, `E`) and `e`/`E` exponent suffixes.
  - Canonical rendering matches Kubernetes' own quantity code: `1.5` becomes
    `1500m`, `1000` becomes `1k`, `1Gi` stays `1Gi`, `1.5Gi` becomes `1536Mi`.
  - Value-based comparison, so `1000m` and `1` are equal; exact addition; JSON
    codec that always emits a string, as the API server does.
- `core/error`: `KubeError` taxonomy (`Parse` / `Decode` / `Config` /
  `Transport` / `Status`) plus `KubeStatusError` with classification for
  404, 409, 401, 403, 429 and 5xx responses.
- Project scaffolding: Apache-2.0 license, README, `AGENTS.md`, a CI workflow
  running `moon check --target all` and `moon test --target wasm-gc`, and a
  portable pre-commit hook.

### Fixed

- `Quantity::compare` dropped the sign when it swapped its operands, so
  `1 < 1e100` was reported as greater-than.
- `BigInt::compare` is not a normalized tri-state on every target: on wasm-gc
  it returns the magnitude gap (`10^100` vs `1` yields `10`) where native
  returns `1`. Comparison results are now normalized to `-1` / `0` / `1`, with
  a regression test pinning the contract.
- Newer toolchains warn that derived and hand-written trait methods are
  implicitly promoted to regular methods (`implicit_impl_as_method`); explicit
  `pub extend` declarations now keep the build warning-free on both old and new
  compilers.

### Changed

- `moon fmt --check` is not a CI gate. Formatter output depends on the
  toolchain release (newer releases spell the default `Int` as its concrete
  width for the wasm-gc target) and old toolchain builds are removed from the
  download server, so gating CI on it would tie the build to a version that
  expires. Formatting is enforced locally by `.githooks/pre-commit`.

### Testing

- 12 tests: 7 whitebox (normalization, precision, the large-exponent compare
  guard, the binary-step table, comparison-result normalization) and 5 blackbox
  (canonical spellings, rejection of malformed input, value comparison,
  addition, JSON round-trip). Green on both native and wasm-gc.