# Demos: Automated compliance through control planes

Demos for the talk at Tergos Connect, 2026-11-24. Crossplane keeps cloud resources
the way they are declared, and turns a platform's rules into code every team gets.

| Demo | Shows |
| --- | --- |
| [1. Managed resources](demo-1-managed-resources/) | A Key Vault opened by hand closes again within seconds, and leaves a receipt |
| [2. A golden path](demo-2-golden-path/) | One request becomes a repository, an identity and a route; one change reaches every app |

## Run it yourself

```bash
setup/control-plane.sh    # kind and Crossplane: enough for demo 1, free
setup/platform.sh         # AKS Automatic and GitHub: demo 2, billed
setup/teardown.sh         # everything back to nothing
```

You need an Azure subscription and a GitHub token first: see
[`setup/README.md`](setup/README.md). Each demo's `demo-script.md` is the run of show.
