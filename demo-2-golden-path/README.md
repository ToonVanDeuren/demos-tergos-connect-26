# Demo 2: a golden path

A team asks for an `App`, the platform builds everything around it, and a release puts
it live. When a new requirement lands, one change to the composition reaches every
`App` that already exists. The run of show is in [`demo-script.md`](demo-script.md).

```yaml
apiVersion: platform.toon.consulting/v1alpha1
kind: App
metadata:
  name: payments-api
spec:
  language: go
```

```
                     CONTROL-PLANE CLUSTER (kind)
          (Crossplane + providers, --poll=15s, change logs)

                         App (cluster-scoped)
         ┌───────────────────┬───────────────────────┐
         ▼                   ▼                       ▼
      GitHub              Azure            WORKLOAD CLUSTER (AKS Automatic)
   Repository      UserAssignedIdentity    Namespace (PSA restricted)
   Environment     FederatedIdentityCred   Service
   ActionsVariable RoleAssignment (x3)     HTTPRoute ──► platform Gateway
         │                                                (approuting-istio)
         │  publish a release
         └──► pipeline: sign in with OIDC, build image, push to ACR,
              fill in the tag, apply the repo's Deployment
```

The platform owns everything above; the team owns the code and `deploy/deployment.yaml`
in a repository made from
[the app template](https://github.com/ToonVanDeuren/demos-tergos-connect-26-app-template).
The repository holds no secrets: the pipeline signs in through a federated credential
that trusts only its `production` environment.

## Layout

```
platform/         the XRD and the composition (setup/platform.sh installs them)
apps/             three App requests; orders-api is deployed before the talk
app-rejected.yaml a request the API refuses
rollout/          the composition plus a BranchProtection step, and the diff
demo-script.md    the run of show and the rehearsal checklist
```

Applying `rollout/app.composition.yaml` is the rollout; applying
`platform/app.composition.yaml` again is the rollback. When the platform composition
changes, change the rollout copy too and regenerate the diff, from `demo-2-golden-path/`:

```bash
diff -u --label platform/app.composition.yaml --label rollout/app.composition.yaml \
  platform/app.composition.yaml rollout/app.composition.yaml > rollout/app.composition.diff
```

## Choices for the stage

- **HTTP on `<app>.<gateway ip>.nip.io`**: no DNS zone and no certificate warning.
- **Public repositories**: branch protection on private ones needs a paid GitHub plan.
- **One shared registry**: new `ghcr.io` packages are private, so they would need a
  pull token. `AcrPush` covers the whole registry; a real platform would scope it per app.

AKS Automatic is billed, so run `setup/teardown.sh --platform` between rehearsals. See
[`setup/README.md`](../setup/README.md).
