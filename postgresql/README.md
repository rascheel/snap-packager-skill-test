# PostgreSQL OCI fixture

This fixture packages PostgreSQL from the pinned Docker Hub image:

```text
docker://postgres@sha256:c27c01f74af25bde5f4f0f69d01944c4fc7f0376ea53c72aa1180dd593ce1d52
```

The digest is the `linux/amd64` image manifest selected from the supplied
Docker Hub layer URL. It is deliberately pinned instead of using the mutable
`latest` tag.

`test-snap-packager.sh` recognizes `image-ref.txt` as an OCI fixture and passes
the reference to `/snap-orchestrator`. The generated OCI extraction, Snapcraft
project, and `.snap` artifact are ignored; only this reproducible fixture
metadata is tracked.

The resulting application is a PostgreSQL daemon. Its test configures a
temporary database password, waits for the listener, and verifies a SQL query
through the confined network stack.
