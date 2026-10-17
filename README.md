# moonkube

[![CI](https://github.com/Rz-coder8848/moonkube/actions/workflows/ci.yml/badge.svg)](https://github.com/Rz-coder8848/moonkube/actions)
[![mooncakes.io](https://img.shields.io/badge/mooncakes.io-Rz--coder8848%2Fmoonkube-8A2BE2)](https://mooncakes.io/packages/Rz-coder8848/moonkube)

A pure-MoonBit [Kubernetes](https://kubernetes.io) client and controller
framework: kubeconfig parsing, typed resource models, exact quantities,
label/field selectors, JSON / JSON-Merge / Strategic-Merge patches, list-watch
informers and a reconcile loop — written from scratch in MoonBit with **zero
runtime dependencies**.

## Why this exists

MoonBit's core library ships no network, HTTP or cluster tooling, and the
ecosystem had no Kubernetes client at all. That leaves every MoonBit service
that wants to run *on* Kubernetes — or drive it — without any way to speak the
API. moonkube fills that gap with the layer that is hardest to get right and
easiest to test: the protocol and object semantics.

Kubernetes is unforgiving about the details, and those details are exactly what
this library encodes:

* **Quantities are not strings.** The API server compares `1000m` and `1` as the
  same amount. A client that compares the raw text is wrong.
* **Patches have three incompatible semantics.** `application/json-patch+json`,
  `application/merge-patch+json` and `application/strategic-merge-patch+json`
  do different things to lists and absent keys.
* **Watch streams are resumable.** Dropped connections must resume from a
  `resourceVersion`, and a `410 Gone` must trigger a full re-list, not a retry.
* **List-watch caches must stay coherent.** An informer that applies updates out
  of order silently corrupts the cache a controller makes decisions from.

## Layout

| Package | Responsibility | Status |
| --- | --- | --- |
| `core` | quantities, selectors, patch documents, watch decoding, HTTP/1.1 codecs, error taxonomy | in progress |
| `resource` | typed resources (`Pod`, `Deployment`, `Service`, ...) + `DynamicObject` | planned |
| `client` | kubeconfig, `Transport` abstraction, typed `Api[T]` client | planned |
| `controller` | list-watch informer, work queue, reconcile loop | planned |

## The transport boundary

MoonBit's core library does not ship a socket or TLS client, so moonkube keeps
IO behind a small trait:

```moonbit
pub trait Transport {
  fn send(Self, HttpRequest) -> HttpResponse raise KubeError
}
```

Everything above that line — request construction, response parsing, error
classification, watch resumption, the informer cache — is pure and runs in
tests without a cluster. `MockTransport` replays canned responses, and can
assert on the requests it receives. Wiring a real TCP/TLS backend is a matter of
implementing `Transport` once, and is deliberately left as the boundary of this
library rather than hidden behind FFI.

## Install

```sh
moon add Rz-coder8848/moonkube
```

Then import the package you need (the alias is the last path segment):

```moonbit
import { "Rz-coder8848/moonkube/core" @kube }
```

## Quantities

```moonbit
let cpu = @kube.Quantity::parse("1000m")
let whole = @kube.Quantity::parse("1")
assert_true(cpu.equals(whole))          // same amount, different spelling
assert_eq(cpu.to_string(), "1000m")     // canonical spelling, exactly as kubectl prints
assert_eq(cpu.add(@kube.Quantity::parse("500m")).to_string(), "1500m")
```

Quantities are stored as `coefficient * 10^exponent` with an arbitrary-precision
coefficient, so `2Ei`, `1e100` and `0.1` are all represented losslessly, and
comparison never goes through a float.

## Development

```sh
moon check --target all
moon test --target wasm-gc
moon fmt --check
```

## License

Apache-2.0. The Kubernetes API conventions this library implements are
documented by the Kubernetes project (Apache-2.0); no Kubernetes source code is
copied. See `LICENSE`.
## References

moonkube is an original implementation, not a port, and contains no third-party
code, FFI bindings or vendored sources. Its behaviour is aligned with these
public specifications and reference clients — none of their source is copied or
translated:

| Reference | Used for | License |
| --- | --- | --- |
| [Kubernetes API reference](https://kubernetes.io/docs/reference/kubernetes-api/) and [API conventions](https://github.com/kubernetes/community/blob/master/contributors/devel/sig-architecture/api-conventions.md) | resource fields, selector grammar, patch semantics | Apache-2.0 |
| `apimachinery` quantity rules | quantity parsing, canonical form, comparison | Apache-2.0 |
| [client-go](https://github.com/kubernetes/client-go) (documented behaviour) | list-watch, `resourceVersion` resumption, 410 re-list, backoff | Apache-2.0 |
| [kube-rs](https://github.com/kube-rs/kube) (documented behaviour) | shape of the transport abstraction | Apache-2.0 |
| RFC 6902 / RFC 7386 / RFC 9112 | JSON Patch, JSON Merge Patch, HTTP/1.1 messages | IETF |

The goal of the comparison is behavioural fidelity: `1000m` and `1` must compare
equal, and `key!=value` must match objects that do not carry the label at all.