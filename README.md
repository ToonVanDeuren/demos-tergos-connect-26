# Demos: Automated compliance through control planes

Demos for the talk on 2026-11-24.

| Demo | Directory | Shows |
| --- | --- | --- |
| 1 | `demo-1-managed-resources/` | A resource group and Key Vault as Crossplane managed resources |
| 2 | `demo-2-golden-path/` | One `App` request becomes a repository, an identity and a route. A release puts it live, and a new rule reaches every `App` that exists |

Both run on the same control plane, so set it up once:

```bash
cd demo-2-golden-path
./setup.sh
```

`setup.sh` expects `azure-creds.json` and `github-creds.json` in
`demo-2-golden-path/` (both gitignored). See `demo-2-golden-path/README.md` for the
prerequisites and `demo-2-golden-path/demo-script.md` for the run of show.

## Demo 1 is not runnable yet

- `keyvault.yaml` has no `tenantId`, which the provider requires.
- The by-hand change beat is not scripted.

## Status

Nothing here has run against a live subscription yet.
