# Redis OCI fixture

This fixture packages the official Redis server from a pinned Docker Hub image:

```text
docker://docker.io/library/redis@sha256:76961cd2a0f40ef6fdd334b6b1b3a76a2bad1848d89f3030ca30a7521d4a9493
```

The digest is the `linux/amd64` image manifest selected from the supplied
Docker Hub layer URL. It is deliberately pinned instead of using the mutable
`latest` tag.

`test-snap-packager.sh` recognizes `image-ref.txt` as an OCI fixture and passes
the reference to `/snap-builder`. The generated OCI extraction, Snapcraft
project, and `.snap` artifact are ignored; only this reproducible fixture
metadata is tracked.

The resulting application is a Redis daemon. Its test installs the snap, waits
for the listener, and verifies basic Redis operations (set/get/ping) through
the confined network stack.
