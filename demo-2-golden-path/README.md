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

## Who owns what

| Owner | Object | Why |
|---|---|---|
| Platform (composition) | repository settings, identity, roles, namespace, Service, route | decided once, the same for every app |
| Team (repository) | the code and `deploy/deployment.yaml` | the image changes with every release |
| Platform (static, `setup/platform.sh`) | AKS, the container registry and the `Gateway` | the shared layer, like the cluster itself |

There is no Deployment in the composition, so no pod runs until the first release.
The namespace enforces Pod Security `restricted`, so the team's manifest stays inside
the platform's limits. The repository comes from
[demos-tergos-connect-26-app-template](https://github.com/ToonVanDeuren/demos-tergos-connect-26-app-template).

The repository holds no secret. The pipeline gets a token through a federated
credential that trusts only this repository's `production` environment. Its roles
reach this app's namespace and the shared registry, and the cluster pulls images with
its own identity, so there is no image pull secret either.

## The rollout (beat 4)

`rollout/rollout.sh` applies the composition plus one step, a `BranchProtection`
for `main`. Every `App` picks it up, so every repository requires a reviewed pull
request without anyone touching one. `rollback.sh` applies the original composition
and the protection goes with it. Each change is a `CompositionRevision`.

## Layout

```
platform/       the XRD and the composition (setup/platform.sh installs them)
examples/       the requests: rejected, live, and two pre-staged
rollout/        the new requirement, as a patch on the composition
demo-script.md  the run of show and the rehearsal checklist
```

The control plane, AKS and the credentials live in [`setup/`](../setup). See
"Run it yourself" in the [root README](../README.md). AKS Automatic is not on the
free tier, so run `setup/teardown.sh --platform` between rehearsals.

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

Ran live on 2026-11-05 with one App, from request to a release serving traffic. Beat 4
has not run yet: see the rehearsal checklist in `demo-script.md`.
