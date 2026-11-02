# Demo 2: a golden path

One request, from a repository to a route. A team asks for an `App`, the platform
builds everything around it, and a release puts it live. When a new requirement
lands, one change to the composition reaches every `App` that already exists.

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
          (Crossplane + providers, --poll=30s, change logs)

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

## Who owns what

| Owner | Object | Why |
|---|---|---|
| Platform (composition) | repository settings, identity, roles, namespace, Service, route | decided once, the same for every app |
| Team (repository) | the code and `deploy/deployment.yaml` | the image changes with every release |
| Platform (static, `setup.sh`) | AKS, the container registry and the `Gateway` | the shared layer, like the cluster itself |

There is no Deployment in the composition, so no pod runs until the first release.
The namespace enforces Pod Security `restricted`, so the team's manifest stays inside
the platform's limits. The repository comes from
[demos-tergos-connect-26-app-template](https://github.com/ToonVanDeuren/demos-tergos-connect-26-app-template).

The repository holds no secret. The pipeline gets a token through a federated
credential that trusts only this repository's `production` environment. Its roles
reach this app's namespace and the shared registry, and the cluster pulls images with
its own identity, so there is no image pull secret either.

## The rollout (beat 4)

`05-rollout/rollout.sh` applies the composition plus one step, a `BranchProtection`
for `main`. Every `App` picks it up, so every repository requires a reviewed pull
request without anyone touching one. `rollback.sh` applies the original composition
and the protection goes with it. Each change is a `CompositionRevision`.

## Layout

```
01-setup/       providers.yaml, functions.yaml, runtimeconfigs.yaml (poll + change logs + watches)
02-config/      ClusterProviderConfigs (Azure, GitHub, the workload cluster) and the Gateway
03-platform/    app/: the XRD and the composition
04-examples/    the requests: rejected, live, and two pre-staged
05-rollout/     the new requirement, as a patch on the composition
setup.sh        everything, from nothing
teardown.sh     everything, back to nothing
demo-script.md  the run of show and the rehearsal checklist
```

## Running it

Prereqs: kind, kubectl, kubelogin, helm, jq, gh, and az 2.86.0 or later (logged in).

```bash
az ad sp create-for-rbac --sdk-auth --role Owner \
  --scopes "/subscriptions/$(az account show --query id -o tsv)" > azure-creds.json
```

Create `github-creds.json` with a personal access token with the `repo`, `workflow`
and `delete_repo` scopes, for the account that owns `demos-tergos-connect-26-app-template`:

```json
{"token": "<token>", "owner": "<user>"}
```

Both files are gitignored. Then:

```bash
./setup.sh
```

AKS Automatic is not on the free tier, so run `./teardown.sh` between rehearsals.

## Decisions for the demo

- **HTTP only.** Hostnames are `<app>.<gateway ip>.nip.io`, so there is no DNS zone to
  own and no self-signed certificate warning on stage.
- **Public repositories.** Branch protection on private repositories needs a paid
  GitHub plan.
- **No rate limit on the route.** App Routing's Gateway API mode does not support it.
- **One shared registry.** New GitHub packages default to private, so a new app's image
  would not pull from `ghcr.io` without a token. `AcrPush` covers the whole registry, so
  an app's pipeline can push to another app's repository; a real platform would scope
  this per repository.

## Status

Rendered and validated against the provider schemas, and the API and the template's
Deployment tested on a local cluster. Nothing has run on AKS or against GitHub yet:
see the rehearsal checklist in `demo-script.md`.
