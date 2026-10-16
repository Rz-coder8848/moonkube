///|
/// moonkube — a Kubernetes API client and controller framework for MoonBit.
///
/// The library is split into four packages so that each layer can be tested on
/// its own, and so that the protocol layer never needs a network to run:
///
/// * `Rz-coder8848/moonkube/core` — quantities, label/field selectors, patch
///   documents, watch event streams and HTTP/1.1 message codecs. Pure
///   functions, no IO.
/// * `Rz-coder8848/moonkube/resource` — typed Kubernetes resources
///   (Pod, Deployment, Service, ...) with JSON round-tripping, plus an
///   untyped `DynamicObject` that preserves unknown fields.
/// * `Rz-coder8848/moonkube/client` — kubeconfig parsing, the `Transport`
///   abstraction, and a typed `Api[T]` client.
/// * `Rz-coder8848/moonkube/controller` — list-watch informers, a work queue
///   and the reconcile loop.
///
/// Start with `core` if you only need the protocol pieces; start with
/// `client` if you want to talk to a cluster.
