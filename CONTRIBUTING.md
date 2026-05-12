# Contributing to the SPIFFE/SPIRE Standalone Tutorial

Thank you for helping make this tutorial better! Whether you're fixing a typo, adding a new lab, or improving an explanation — contributions are welcome.

---

## What to Contribute

- **Bug fixes** — broken commands, typos, outdated image versions
- **Lab improvements** — clearer explanations, better expected-output examples
- **New scenarios** — e.g., multi-workload patterns, custom attestors, SPIRE health monitoring
- **Platform additions** — Windows-native instructions, arm64 notes
- **Language examples** — Go, Python, Java SPIFFE library examples alongside Node.js

---

## Structure Rules

1. Each track (`docker-compose/`, `kind/`) has its own `README.md` with numbered labs
2. All shell scripts must have a shebang (`#!/usr/bin/env bash`) and be POSIX-compatible
3. Kubernetes manifests go in `k8s/` subdirectories
4. Application code goes in `apps/<service-name>/`
5. Advanced scenarios go in `kind/advanced/<scenario-name>/`

---

## Writing Style Guidelines

- **Explain the why before the how** — don't just show commands, explain what they do
- **Show expected output** — readers must be able to verify success
- **Include troubleshooting** — document common failure modes and fixes
- **Copy-paste ready** — every command block should work as-is, no manual substitution needed
- **Link to the glossary** — when introducing a concept, link to `docs/glossary.md`

---

## Testing Your Contribution

Before submitting, verify locally:

```bash
# Track A — test the full Docker Compose flow
cd docker-compose
docker compose up -d --build
curl http://localhost:3000/demo
docker compose down -v

# Track B — test kind setup (requires kind + kubectl)
cd kind
./setup.sh
kubectl -n spire get pods   # should show all Running
./teardown.sh

# Lint shell scripts (if shellcheck is installed)
find . -name "*.sh" -exec shellcheck {} \;
```

---

## Pull Request Checklist

- [ ] All commands tested manually end-to-end
- [ ] Expected output shown for key commands
- [ ] Troubleshooting section included (if new scenario)
- [ ] Parent README updated if new module added
- [ ] No hardcoded credentials, tokens, or secrets
- [ ] Shell scripts are LF line endings (not CRLF)

---

## Questions?

Open a GitHub Issue or Discussion — happy to help!
