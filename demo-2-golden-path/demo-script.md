# Run of show: demo 2

Deploy apps through the platform, see what it builds in GitHub, Azure and Kubernetes,
release one, then change the composition and watch every app follow.

The terminal only runs `nvim` and `kubectl apply`; the results are shown in the
browser. `kubectl` runs against `kind-control-plane` unless a `--context` says
otherwise.

## Before the talk

- [ ] `setup/control-plane.sh` and `setup/platform.sh` ran; `kubectl get providers` all HEALTHY.
- [ ] `orders-api` deployed and released, so a node is up and the release on stage is
  quick: `kubectl apply -f apps/orders-api.yaml`, wait for READY, publish release
  `v0.1.0` in its GitHub repo, and check that the `production` link on the run page
  shows `orders-api v0.1.0`.
- [ ] the other two do not exist: `kubectl get apps` shows only `orders-api`, and GitHub
  has no `invoices-api` or `payments-api` repo.
- [ ] the platform composition is the original: `kubectl get branchprotections -A` is empty.
- [ ] terminal: big font, `cd` into `demo-2-golden-path/`, prompt cleared.
- [ ] browser tabs:
  1. your GitHub repositories (`github.com/<owner>?tab=repositories`)
  2. the Azure portal, resource group `rg-tergos-demo`, filtered on Managed Identity
  3. the fallback recording

## 1. Rejected at the API

```bash
nvim app-rejected.yaml
kubectl apply -f app-rejected.yaml
```

Expected: `spec.language: Unsupported value: "cobol": supported values: "go"`.
Nothing was created. What is not in the file is the point: no visibility, no identity,
no Pod Security settings. Not forbidden, not expressible.

## 2. Deploy the apps

```bash
nvim apps/payments-api.yaml
kubectl apply -f apps/
crossplane resource trace app payments-api --watch      # ctrl-c when all READY
```

`orders-api` is `unchanged`: it was deployed before the talk. The other two are
created. The trace is one request as a tree: the repository, environment and variable in
GitHub, the identity and its roles in Azure, the namespace, service and route in the
cluster. READY after about 90 seconds.

Then show where it landed:

- **GitHub** (tab 1): refresh, two new repositories next to `orders-api`. Open `payments-api`: the
  pipeline and `deploy/` came from the template; under **Settings > Environments**
  there is `production`, under **Settings > Secrets and variables > Actions** there is
  `DEPLOY_CONFIG` and no secret.
- **Azure** (tab 2): refresh, an identity per app.
- **Kubernetes**:
  `kubectl --context aks-tergos-demo get namespace,service,httproute -n payments-api`.
  The route is there with nothing behind it yet: there is no Deployment in the
  composition. The image changes with every release, so the team owns that part.

## 3. Release

In GitHub, `payments-api`: **Releases > Draft a new release**, tag `v0.1.0`,
**Publish release**. Then the **Actions** tab: the run "Deploy v0.1.0" signs in to
Azure without a secret, builds, pushes and deploys. When it is green, click the
`production` link on the run page: the app, `payments-api v0.1.0`.

## 4. Change the composition

New requirement from security: a change to `main` needs a reviewed pull request, in
every repo, including the ones that already exist.

```bash
nvim -d platform/app.composition.yaml rollout/app.composition.yaml
kubectl apply -f rollout/app.composition.yaml
```

The diff is the whole change: one new step, 30 lines.

In GitHub, any of the three repos: **Settings > Branches** shows a rule for `main`,
within about 20 seconds. Then edit a file on `main` in the browser: GitHub no longer
lets you commit; it offers a pull request. No repo was touched, no team was asked. One
definition changed; every repo followed.

The flip side, if it fits: a bad change reaches everything just as fast, which is why
it goes through stages first. `kubectl get compositionrevisions` shows the old revision
is still there to go back to.

## If something breaks

- An app not READY after two minutes: `crossplane resource trace app <name>` shows which
  resource is stuck and why.
- The release run fails on `azure/login`: the identity's credential is still
  propagating. **Re-run failed jobs** in the Actions tab and talk over it.
- The app does not answer after a green run: AKS Automatic may still be adding a node
  (`kubectl --context aks-tergos-demo get pods -n payments-api`).
- Anything else: the recording, tab 3. Narrate over it.

## Reset between rehearsals

```bash
kubectl apply -f platform/app.composition.yaml   # removes the branch protection
kubectl delete -f apps/invoices-api.yaml -f apps/payments-api.yaml
kubectl get apps                                 # only orders-api, READY
```

`orders-api` stays, with its release, for the next run.

## Rehearsal checklist

Measured on 2026-11-05:

- [x] an App is READY in about 80 to 90 seconds: repository from the template,
  `production` environment, `DEPLOY_CONFIG`, no secrets, identity, roles, namespace with
  Pod Security `restricted`, service and route. The empty route answers 503.
- [x] a release takes about 1 minute when a node is free, and about 3 minutes when AKS
  Automatic has to add one first. That is why `orders-api` is released before the talk.
- [x] the composition change reaches three repos in 13 to 17 seconds; the rollback removes
  it again in about 13 seconds.
- [x] `kubectl delete app` removes the repo, the identity and the namespace.
- [x] GitHub API usage with three apps: about 300 of 5000 calls per hour.
- [x] two apps applied at once: how long until both are READY?
- [x] `crossplane resource trace --watch` at stage font size.
- [x] the GitHub click paths (release, Settings > Branches, editing on `main`).
