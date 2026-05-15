# Eclipse JKube Images - AI Agents Instructions

Always reference these instructions first and fallback to search or bash commands only when you encounter unexpected information that does not match the info here.

This file provides guidance to AI coding agents (GitHub Copilot, Claude Code, etc.) when working with code in this repository. **Read the "Ecosystem context" section before touching anything** — this repo is one piece of a four-repo pipeline and changes here ripple outward.

## Project Overview

`eclipse-jkube/jkube-images` hosts the [CEKit](https://cekit.io) descriptors that produce the base container images consumed by [Eclipse JKube](https://github.com/eclipse-jkube/jkube). Each image is defined as a top-level `<image-name>.yaml` descriptor backed by reusable CEKit modules under `modules/`. Built images are published to [`quay.io/jkube`](https://quay.io/organization/jkube).

The repository is **not** a Java/Node/Python codebase — there is no `pom.xml`, `package.json`, or equivalent. The "source code" is YAML descriptors, Bash `configure` scripts, and shell-based smoke tests.

## Ecosystem context

Four repositories collaborate to deliver JKube's container support. Understanding this chain is mandatory before changing anything that affects image behavior.

```
┌──────────────────────────┐    pinned ref: 0.45.5    ┌────────────────────────────┐
│ jboss-openshift/         │ ◄──────────────────────  │ THIS REPO                  │
│  cct_module              │    (dead upstream,       │ eclipse-jkube/jkube-images │
│ (last commit 2023-09,    │     being phased out)    │  → quay.io/jkube/*         │
│  PR #414 OpenJDK 17      │                          │                            │
│  never merged)           │                          │                            │
└──────────────────────────┘                          └─────────────┬──────────────┘
                                                                    │ tag release
                                                                    ▼
                                                     ┌──────────────────────────────┐
                                                     │ eclipse-jkube/jkube          │
                                                     │  bumps version.image         │
                                                     │  .jkube-images in            │
                                                     │  jkube-kit/parent/pom.xml    │
                                                     └─────────────┬────────────────┘
                                                                   │ release
                                                                   ▼
                                                     ┌──────────────────────────────┐
                                                     │ eclipse-jkube/                │
                                                     │  jkube-integration-tests     │
                                                     │  runs e2e on K8s/OpenShift   │
                                                     └──────────────────────────────┘
```

For cross-repo work you will want local clones of the two sibling repositories alongside this one:
- [`eclipse-jkube/jkube`](https://github.com/eclipse-jkube/jkube) — the JKube Maven/Gradle plugin source; pins image versions and contains the generators/handlers that select each image.
- [`eclipse-jkube/jkube-integration-tests`](https://github.com/eclipse-jkube/jkube-integration-tests) — end-to-end test suite that runs after a JKube release adopts a new image tag.

### `cct_module` is dying — the migration is in progress

`github.com/jboss-openshift/cct_module` (pinned at `ref: 0.45.5` in the Java descriptors) is a shared CEKit-module repo from the broader JBoss/OpenShift container ecosystem. It is **effectively dead**: last `master` commit September 2023, community PRs for newer JDKs (e.g. PR #414 OpenJDK 17) were never merged, and the project has not adopted RHEL 9 compatibility. We are **fully eliminating** the dependency over time by porting modules into this repo's `modules/` directory.

Migration status:

| Module | Status | Local location |
|---|---|---|
| `jboss.container.java.run.bash` | Rewritten under jkube namespace | `modules/org.eclipse.jkube.run.bash/` |
| `jboss.container.java.jvm.bash` | Rewritten under jkube namespace | `modules/org.eclipse.jkube.jvm.bash/` + `…/singleton-jdk/` |
| `jboss.container.java.jvm.bash` `debug-options` | Shadow-fork override (kept under cct_module name to override at install time) | `modules/jboss.container.java.jvm.bash.debug-options-override/` |
| `jboss.container.openjdk.jdk` (17, 21) | Shadow-fork (cct_module only ships 8/11) | `modules/jboss.container.openjdk.jdk/{17,21}/` |
| `jboss.container.jolokia` | Shadow-fork (RPM → Maven Central; cct_module's RPM doesn't exist on RHEL 9) | `modules/jboss.container.jolokia/{jkube-1.7.2,jkube-2.0.0,jkube-2.1.2,jkube-2.6.0}/` — also rewritten under `modules/org.eclipse.jkube.jolokia/{2.0.0,2.1.2,2.6.0}/` |
| `jboss.container.prometheus` | Shadow-fork + jkube rewrite, same RPM→MavenCentral reason | `modules/jboss.container.prometheus/jkube-0.20.0/` + `modules/org.eclipse.jkube.prometheus/0.20.0/` |
| `jboss.container.maven` | Shadow-fork + jkube rewrite | `modules/jboss.container.maven/8.2.3.8/` + `modules/org.eclipse.jkube.maven/…/` |
| `jboss.container.s2i.core.bash` / `jboss.container.java.s2i.bash` | Rewritten | `modules/org.eclipse.jkube.s2i/{core,bash}/` |
| `jboss.container.user` | Rewritten | `modules/org.eclipse.jkube.user/` |
| **`jboss.container.dnf`** | **Pending — still pulled live from cct_module@0.45.5** | (none) |
| **`jboss.container.microdnf-bz-workaround`** | **Pending — still pulled live from cct_module@0.45.5** | (none) |
| **`jboss.container.util.logging.bash`** | **Pending — still pulled live from cct_module@0.45.5** | (none) |

**Migration policy for AI agents:**
1. **Never introduce a new dependency on a `cct_module` module that isn't already referenced.** If you need behavior from a cct_module module that's not already in use, port it into `modules/` first.
2. **When porting a cct_module module into this repo, use the `org.eclipse.jkube.<name>` namespace** unless the *only* purpose is to override an existing cct_module install entry at its original name (the shadow-fork pattern — see below).
3. The three pending modules (`dnf`, `microdnf-bz-workaround`, `util.logging.bash`) are open work; porting them out is welcomed but coordinate with the maintainer first since they touch every Java descriptor.

### Image → JKube consumer contract

Every image in this repo is consumed by a specific JKube class. Knowing *who* consumes it tells you what env vars and runtime conventions are load-bearing.

| Image | JKube consumer | Stable interface JKube relies on |
|---|---|---|
| `jkube-java`, `jkube-java-11` | `JavaExecGenerator` (`jkube-kit/generator/java-exec/.../JavaExecGenerator.java`) | Honors `JAVA_APP_DIR`, `JAVA_MAIN_CLASS`, `JAVA_OPTIONS`, `AB_JOLOKIA_OFF`, `AB_PROMETHEUS_OFF`. Entrypoint `/usr/local/s2i/run` sources `run-java.sh`. |
| `jkube-tomcat` (Tomcat 10) | `WebAppGenerator` + `TomcatAppSeverHandler` (`jkube-kit/generator/webapp/.../handler/TomcatAppSeverHandler.java`) | Honors `DEPLOY_DIR`. **Defaults `TOMCAT_WEBAPPS_DIR=webapps-javaee`** so Servlet 3.0 WARs still work on Tomcat 10 via its built-in `javax→jakarta` translation. Entrypoint `/usr/local/s2i/run`. |
| `jkube-tomcat9` (Tomcat 9) | Same handler, when user pins Tomcat 9 | Honors `DEPLOY_DIR`. Webapps dir defaults to `webapps`. Entrypoint `/usr/local/s2i/run`. |
| `jkube-jetty9` | `WebAppGenerator` + `JettyAppSeverHandler` | Honors `DEPLOY_DIR`. Entrypoint `/usr/local/s2i/run`. |
| `jkube-karaf` | `KarafGenerator` (`jkube-kit/generator/karaf/.../KarafGenerator.java`) | Honors `DEPLOYMENTS_DIR` and `KARAF_HOME=/deployments/karaf`. Karaf assembly is unpacked at that path. |
| `jkube-remote-dev` | `RemoteDevelopmentService` + `KubernetesSshServiceForwarder` (`jkube-kit/remote-dev/...`) | Accepts `PUBLIC_KEY` env (JKube generates an RSA 2048-bit key pair on the fly). SSH listens on **port 2222**. **`init.sh` emits the exact log line `Current container user is: <username>` — JKube parses it.** |

JKube pins image versions centrally in `jkube-kit/parent/pom.xml`:
```xml
<version.image.jkube-images>0.0.26</version.image.jkube-images>
```
This property is filtered into `META-INF/jkube/default-images.properties` resources in each generator module (`java.upstream.docker`, `tomcat.upstream.docker`, `jetty.upstream.docker`, `karaf.upstream.docker`, `image.remote-dev`). A new image tag is not adopted until that property bumps.

## Working Effectively

### Bootstrap and Setup

Required tooling:
- **CEKit** — the image builder (`pip install cekit` or use the [`cekit/actions-setup-cekit`](https://github.com/cekit/actions-setup-cekit) action in CI). CI pins `cekit/actions-setup-cekit@v1.1.7`.
- **Docker** (or Podman) — CEKit shells out to a container builder. CI uses `docker`.
- **Bash** — for running the `scripts/test-*.sh` test harness.

No language runtime install step is needed beyond the above.

### Build Commands

Build a single image locally (matching how CI builds it):

```bash
# Generic form
cekit --descriptor <image-name>.yaml build docker --tag="quay.io/jkube/<image-name>:latest"

# Examples
cekit --descriptor jkube-java.yaml         build docker --tag="quay.io/jkube/jkube-java:latest"
cekit --descriptor jkube-tomcat.yaml       build docker --no-squash --tag="quay.io/jkube/jkube-tomcat:latest"
cekit --descriptor jkube-tomcat9.yaml      build docker --no-squash --tag="quay.io/jkube/jkube-tomcat9:latest"
cekit --descriptor jkube-remote-dev.yaml   build docker --tag="quay.io/jkube/jkube-remote-dev:latest"
```

Notes:
- The two Tomcat images **require `--no-squash`** (see `.github/workflows/build-images.yml`). Squashing breaks the Tomcat base image layout.
- CEKit writes its intermediate `Dockerfile`, scripts, and tarballs into `target/` (gitignored). Safe to delete between builds.
- A clean build (no Docker layer cache) typically takes **3–8 minutes** per image depending on base image pulls and module compilation. **NEVER CANCEL**: let it finish.

### Testing

Each image has a paired `scripts/test-<image-name>.sh` smoke test that runs the image via Docker and asserts on output. Run them only **after** the image has been built locally with the `:latest` tag.

```bash
# Default tag is "latest"; override via TAG=<tag> if you tagged differently.
./scripts/test-jkube-java.sh
./scripts/test-jkube-java-11.sh
./scripts/test-jkube-java-17.sh
./scripts/test-jkube-jetty9.sh
./scripts/test-jkube-karaf.sh
./scripts/test-jkube-remote-dev.sh
./scripts/test-jkube-tomcat.sh
./scripts/test-jkube-tomcat9.sh
```

Each test:
1. Sources `scripts/common.sh` (defines `dockerRun`, `dockerRunE`, `assertContains`, `assertMatches`, `reportError`).
2. Pulls `IMAGE=quay.io/jkube/<image-name>:$TAG_OR_LATEST` with `--pull never` — so the image **must already be built locally**, the test will not fetch it.
3. Runs `docker run --rm` with various commands and pattern-matches the output.

Tests run in **seconds to ~1 minute** each.

### Running the Application

These are base images, not applications. To "run" one for inspection:

```bash
docker run --rm -it quay.io/jkube/jkube-java:latest /bin/bash
```

For full runtime behavior, push an app into `/deployments` (or wire it up via the JKube Maven/Gradle plugin in a downstream project) — the entrypoint is `/usr/local/s2i/run` for most images.

## Architecture

### Technical Structure

```
.
├── jkube-java.yaml            # CEKit image descriptors (one per published image)
├── jkube-java-11.yaml
├── jkube-java-17.yaml
├── jkube-jetty9.yaml
├── jkube-karaf.yaml
├── jkube-remote-dev.yaml
├── jkube-tomcat.yaml
├── jkube-tomcat9.yaml
├── modules/                   # Reusable CEKit modules (referenced from descriptors)
│   ├── org.eclipse.jkube.*/   # JKube-native modules — TARGET END STATE for new work
│   ├── jboss.container.*/     # Local shadow-forks of cct_module modules (transitional)
│   └── {run-java,s2i-tomcat,s2i-jetty,s2i-karaf}/  # Legacy short-named project modules
├── scripts/
│   ├── common.sh              # Shared assertion helpers (dockerRun, assertContains, …)
│   └── test-<image>.sh        # One smoke test per image
├── .github/workflows/
│   ├── build-images.yml       # PR + main: build & test all images
│   └── push-images.yml        # On tag push: build & push to quay.io
└── target/                    # CEKit scratch dir (gitignored)
```

### Module namespaces

Three patterns coexist in `modules/`. New code should always use **`org.eclipse.jkube.*`**.

1. **`org.eclipse.jkube.<name>/`** — JKube-native, the target end state. Use this for every new module and every rewrite. Header comments may reference the original `cct_module` blob (`References: https://github.com/jboss-openshift/cct_module/blob/<sha>/…`) for traceability.
2. **`jboss.container.<name>/`** — Local shadow-forks of cct_module modules. These exist *only* because CEKit resolves modules by name and we need to override what the live `cct_module@0.45.5` dependency would otherwise install. As soon as a descriptor stops referencing the cct_module repository, the corresponding shadow-forks should be renamed to `org.eclipse.jkube.<name>`. Don't create new modules under this namespace.
3. **Bare-name (`run-java/`, `s2i-tomcat/`, `s2i-jetty/`, `s2i-karaf/`)** — Project-local modules predating the namespace convention. Don't add new ones. Existing ones can be renamed under `org.eclipse.jkube.*` opportunistically (coordinate with the maintainer since descriptors reference them by name).

There is a known **transitional inconsistency**: `jkube-java.yaml` (JDK 21) installs `org.eclipse.jkube.jolokia:2.6.0` and `jkube-java-25.yaml` installs `org.eclipse.jkube.jolokia:2.1.2`, while `jkube-java-17.yaml` installs `jboss.container.jolokia:jkube-2.6.0` and `jkube-java-11.yaml` installs `jboss.container.jolokia:jkube-2.1.2`; java-11 and java-17 also install `jboss.container.prometheus:jkube-0.20.0` directly, whereas java-21 and java-25 ship Prometheus transitively via `org.eclipse.jkube.s2i.bash` → `org.eclipse.jkube.prometheus:0.20.0`. The shadow-fork vs jkube-native split is an artifact of the in-progress migration. Note that `jkube-java-11` is pinned to Jolokia **2.1.2** by JDK-bytecode necessity — Jolokia 2.4+ is compiled to JDK 17 bytecode and will not load on JDK 11 — not by migration accident.

### Design Patterns

- **Descriptor-per-image.** Each top-level `*.yaml` defines one published image: `name`, `from`, `labels`, `envs`, `packages`, the `modules` to install, and the `run` command/user.
- **Module composition.** Most logic lives in CEKit modules under `modules/`. Modules are referenced by `name` (and optionally `version`) under the descriptor's `modules.install:` list. The `modules` repository is declared with `repositories: - path: modules`. External modules from `jboss-openshift/cct_module` are pinned by git ref (`ref: 0.45.5`).
- **Versioned modules live in subdirectories.** When a module has versions (e.g. `modules/org.eclipse.jkube.jolokia/2.0.0/`, `…/2.1.2/`, `…/2.6.0/`), the directory name **is** the version, and descriptors select it via `version: 2.6.0`.
- **Singleton-JDK pattern.** `org.eclipse.jkube.jvm.singleton-jdk` is installed **last** in Java image descriptors to remove any other JDK that earlier modules pulled in. Preserve this ordering.
- **Non-root by default.** All images run as `user: 1000` and use `/deployments` as the canonical drop directory (`DEPLOYMENTS_DIR=/deployments`).
- **CEKit later-wins by name.** When the same module name appears both in `modules/` (local) and in the `cct_module` repository, CEKit uses whichever is listed later in the `modules.repositories:` block. Local `modules/` is listed first, then `cct_module`, so **a local module with the cct_module's name takes precedence** — this is exactly how the `jboss.container.*` shadow-forks override upstream.

## Code Style

- **YAML descriptors:** 2-space indent, double-quoted string values, follow the field order used in existing descriptors (`schema_version`, `name`, `description`, `version`, `from`, `labels`, `envs`, `packages`, `modules`, `ports`, `run`). Keep `maintainer` as `Eclipse JKube Team <jkube-dev@eclipse.org>`.
- **Shell scripts:** `#!/bin/bash` or `#!/bin/sh`, `set -Eeuo pipefail` for test scripts (`set -e` for module `configure` scripts — see existing files for the convention used in that location). Indent with 2 spaces. Use `assertContains` / `assertMatches` / `reportError` from `scripts/common.sh` rather than inlining new helpers.
- **Conventional commits.** Recent history uses prefixes like `feat:`, `fix:`, `deps(<image>):` (e.g. `deps(jkube-tomcat9): bump tomcat9 from 9.0.89 to 9.0.98`). Match this style.
- **No emojis** in descriptors, scripts, commits, or PR descriptions.
- **Module headers** when porting from cct_module: include a comment with the source URL and SHA so future readers can diff.

## Testing Guidelines

The tests in this repo are shell-driven black-box smoke tests against the built Docker image. They are intentionally lightweight — but when you add or modify them, follow these principles:

1. **Black-box testing.** Assert on observable container behavior — environment variables, file paths under `/opt`, command output, exposed ports, process user. Do not crack open module internals or test `configure` script branches in isolation. `docker run` is the public API.
2. **Avoid mocks.** Always run against the **real built image** (`--pull never` enforces "use the locally-built tag"). Never substitute a mocked binary or stubbed filesystem.
3. **Nested scenario grouping.** Bash has no `describe`/`@Nested`, so group related assertions with a leading comment header (the existing tests do this — see `# Java (xxx.openjdk.jdk)`, `# Jolokia module`, etc.). New checks for an existing concern go under that concern's block; new concerns get a new commented section.
4. **Scenario-based setup.** Capture shared state once at the top (`env_variables="$(dockerRun 'env')"`), then assert against it. Use scoped overrides via `dockerRunE /bin/bash -c '<VAR>=<val> …'` for the "with X env" scenarios.
5. **Single assertion per check.** Each `assertContains` / `assertMatches` call should verify one thing and provide a specific `reportError` message naming what failed. Don't chain unrelated checks behind a single failure message.

When you add a new image, also add a `scripts/test-<image-name>.sh` and register it in **both** `.github/workflows/build-images.yml` and `.github/workflows/push-images.yml` matrix lists.

## Release coupling & cross-repo workflow

Changes to this repo follow a **batched-release** model — they do not reach JKube users until an image tag is cut and a follow-up PR lands in `eclipse-jkube/jkube`.

```
1. PR(s) merged to main here          (image content changes accumulate)
2. Git tag pushed in this repo        (.github/workflows/push-images.yml fires)
3. quay.io/jkube/<image>:<tag> built and pushed
4. PR opened in eclipse-jkube/jkube   (bumps version.image.jkube-images in
                                       jkube-kit/parent/pom.xml)
5. eclipse-jkube/jkube-integration-tests runs against the new image
6. JKube release ships the new image to end-users
```

**Implications for an AI agent making changes here:**
- A merged PR in this repo is **not** yet visible to JKube users; do not promise that. State that "the change will reach users on the next jkube-images release + JKube image-version bump."
- Don't open a JKube PR speculatively. The image-version bump happens after the tag is pushed and the image is available on quay.io.
- For breaking changes (env var rename, removed default, changed exit code, repathed binary), call this out explicitly in the PR description so the eventual JKube-side bump PR can ship matching adjustments.

## Cross-repo check before merging

When you change behavior that any JKube class relies on (env var name/default, run-java.sh contract, S2I entrypoint location, port number, log-line format, module install path), run this checklist before declaring the work done:

1. **Grep `eclipse-jkube/jkube`** for the symbol you changed (run inside your local jkube checkout).
   ```bash
   rg '<ENV_VAR_OR_PATH>'
   ```
   If JKube sets or reads it, list every call site in the PR description.

2. **Run the consuming generator's unit tests** in the local JKube checkout.
   - `jkube-java*`: `mvn -pl jkube-kit/generator/java-exec test`
   - `jkube-tomcat*` / `jkube-jetty9`: `mvn -pl jkube-kit/generator/webapp test`
   - `jkube-karaf`: `mvn -pl jkube-kit/generator/karaf test`
   - `jkube-remote-dev`: `mvn -pl jkube-kit/remote-dev test`

3. **Build the image locally and run `scripts/test-<image>.sh`** here. The shell test is the canonical contract for image-side behavior; if you changed a default, update the assertion.

4. **Smoke-test against a sample project** (optional but recommended for non-trivial changes). Use `mvn k8s:build` or `mvn oc:build` in a Spring Boot or Quarkus project with the locally-built `quay.io/jkube/<image>:latest`. Make sure JKube's generator picks up the image and the resulting container actually runs.

5. **Note for `jkube-integration-tests`.** Full e2e coverage lives in [`eclipse-jkube/jkube-integration-tests`](https://github.com/eclipse-jkube/jkube-integration-tests) and runs *after* the JKube-side image-version bump merges. It is not gated on this repo's PR but you should flag risky changes (those affecting startup, classpath assembly, S2I scripts, or SSH wiring) so the integration suite gets attention during the next JKube release.

### Cross-repo contracts (stable interfaces — change with care)

These are the load-bearing surface JKube depends on. Treat them as public API:

- **Entrypoint**: `/usr/local/s2i/run` for every image except `jkube-remote-dev`. Renaming or moving it breaks every JKube generator that produces an `ImageConfig`.
- **`run-java.sh`** at `/opt/jboss/container/java/run/run-java.sh` is the actual Java launcher; `/usr/local/s2i/run` shells into it. JKube relies on it honoring `JAVA_APP_DIR`, `JAVA_MAIN_CLASS`, `JAVA_OPTIONS`, `JAVA_APP_JAR`, `JAVA_LIB_DIR`, `JAVA_CLASSPATH`, `AB_JOLOKIA_OFF`, `AB_PROMETHEUS_OFF`.
- **Tomcat**: `DEPLOY_DIR` directs where WARs land. `TOMCAT_WEBAPPS_DIR` selects between `webapps` and `webapps-javaee` (Tomcat 10 default is `webapps-javaee` for Servlet 3.0 back-compat via Jakarta translation).
- **Karaf**: `DEPLOYMENTS_DIR` (default `/deployments`) and `KARAF_HOME` (default `/deployments/karaf`). KarafGenerator unpacks the assembly into `${KARAF_HOME}` and expects `bin/` scripts to be executable.
- **Remote-dev** (`jkube-remote-dev`):
  - SSH listens on **port 2222** (hardcoded in `jkube-kit/remote-dev/.../remote-dev.properties`).
  - **`PUBLIC_KEY` env var** is required — JKube generates an RSA 2048-bit keypair on the fly and injects the public key.
  - **`init.sh` emits `Current container user is: <username>` on startup** — `KubernetesSshServiceForwarder` parses this exact prefix from container logs. Do not reword it.
  - `init.sh` also exits 1 if `PUBLIC_KEY` is unset.

## Common Tasks

### Bumping a base image or dependency version

1. Edit the relevant top-level `*.yaml` (e.g. `from: "tomcat:10.1.34-jdk21-temurin"`) **or** the module's `module.yaml` under `modules/…/`.
2. If the dependency surfaces in tests (Java version, Maven version, Tomcat version), update the regex in the matching `scripts/test-<image>.sh`.
3. Rebuild locally and run the test script.
4. Commit with `deps(<image>): bump <dep> from <old> to <new>`.

### Adding or updating a module

1. Create or edit `modules/<module-name>/module.yaml` (and a sibling `configure` script if the module needs install-time logic).
2. For versioned modules, place files under `modules/<module-name>/<version>/`.
3. Reference it from a descriptor: `- name: <module-name>` (add `version: <x.y.z>` for versioned modules).
4. **New modules go under `org.eclipse.jkube.<name>`.** Use `jboss.container.<name>` only when the explicit intent is to shadow an existing cct_module install entry without touching the descriptor.
5. Rebuild and test the image(s) that consume the module.

### Porting a module out of cct_module

When a behavior currently sourced from `cct_module@0.45.5` needs to change (or just to remove the dep):

1. Copy the module from `https://github.com/jboss-openshift/cct_module/tree/<sha>/jboss/container/<path>` into `modules/org.eclipse.jkube.<name>/` (or under the matching version subdir).
2. Add a header comment to `module.yaml` referencing the source URL and SHA.
3. If you must keep the original install name (because changing the descriptor is out of scope for this PR), use the `jboss.container.<name>` shadow-fork pattern instead — but plan a follow-up to rename to `org.eclipse.jkube.<name>` and update descriptors.
4. Update any descriptor that referenced the cct_module version to install the local module.
5. **If the descriptor no longer references *any* cct_module module**, remove the `- name: cct_module / git: …` entry from `modules.repositories:`.
6. Rebuild and run the test script. Many env-var paths (`JBOSS_CONTAINER_*_MODULE`) change with the namespace switch — update tests accordingly.

### Adding a new image

1. Create `<new-image>.yaml` at the repo root (copy an existing descriptor of the same family as a starting point).
2. Add or reuse modules under `modules/` as needed (prefer `org.eclipse.jkube.*`).
3. Add `scripts/test-<new-image>.sh` (source `scripts/common.sh`, set `IMAGE="quay.io/jkube/<new-image>:$TAG_OR_LATEST"`).
4. Append a matrix entry to both `.github/workflows/build-images.yml` and `.github/workflows/push-images.yml`.
5. Document the image in `README.md`.
6. **Plan the JKube-side work**: a new image without a generator/handler in JKube to select it is unreachable from user projects. Coordinate the generator addition before the image ships.

## Troubleshooting

- **`docker run --rm --pull never … Unable to find image`** — the test ran before the image was built locally. Run `cekit --descriptor <image>.yaml build docker --tag="quay.io/jkube/<image>:latest"` first.
- **Tomcat image build produces an unbootable image** — you likely omitted `--no-squash`. Both `jkube-tomcat` and `jkube-tomcat9` require it.
- **CEKit fails to fetch `cct_module`** — check the `ref:` pin (currently `0.45.5` in the Java descriptors) and your network access to `github.com/jboss-openshift/cct_module`. The repo is dead but the tag remains available.
- **A second JDK appears in the final image** — ensure `org.eclipse.jkube.jvm.singleton-jdk` remains the **last** entry in the descriptor's `modules.install:` list; it prunes other JDKs and must run after everything else.
- **Local module change has no effect** — check the install order in `modules.repositories:`: `path: modules` must come *before* the `cct_module` git repo if you're shadow-forking a cct_module module under its original name.
- **`target/` is dirty between builds** — safe to delete; it is gitignored CEKit scratch space.
- **Quay push fails locally** — the `push-images.yml` workflow is the only supported publish path. It triggers on tag push and uses `QUAY_USER`/`QUAY_TOKEN` repository secrets; do not push manually unless you are coordinating a release.
- **JKube doesn't pick up my new image** — JKube pins image versions centrally at `version.image.jkube-images` in `jkube-kit/parent/pom.xml`. After a tag push here, a JKube PR must bump that property. Until then, users keep getting the old image.
