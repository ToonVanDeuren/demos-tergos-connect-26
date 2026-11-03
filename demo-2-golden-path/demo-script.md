# Run of show: demo 2 (21:00 to 28:00)

All `kubectl` commands run against `kind-control-plane` unless a `--context` says
otherwise. Set it once: `kubectl config use-context kind-control-plane`. The left
terminal runs bash and has these set:

```bash
OWNER=$(kubectl get environmentconfig platform -o jsonpath='{.data.platform.github.owner}')
DOMAIN=$(kubectl get environmentconfig platform -o jsonpath='{.data.platform.appsDomain}')
```

## Screen layout

- **Left terminal (commands):** big font, `cd` into `demo-2-golden-path/`, prompt cleared.
- **Right terminal (watch):** `kubectl get managed -A -w`.
- **Browser tab A:** `github.com/<owner>?tab=repositories`.
- **Browser tab B:** the fallback recording of the whole demo.

## Before the talk (T-60 min)

- [ ] `setup/control-plane.sh` and `setup/platform.sh` ran the day before; `kubectl get providers,functions` all HEALTHY.
- [ ] pre-staged and READY: `kubectl get apps` shows `orders-api` and `invoices-api`.
- [ ] both have a release: `curl http://orders-api.$DOMAIN/` and `invoices-api` answer.
- [ ] rehearsal leftovers gone: `kubectl get app payments-api` says "not found", and the repo `payments-api` does not exist.
- [ ] rollout not yet applied: `kubectl get branchprotections -A` is empty.
- [ ] `gh auth status` is logged in; `az account show` is on the demo subscription.
- [ ] right terminal running `kubectl get managed -A -w`; tab A open; tab B loaded.

## Beat 1: the edge, at the API (1 min)

```bash
cat examples/app-rejected.yaml
kubectl apply -f examples/app-rejected.yaml
```

Expected: `spec.language: Unsupported value: "cobol": supported values: "go"`.

Nothing was called. Point out what is not in the file: no visibility, no identity,
no Pod Security settings. Not forbidden. Not expressible.

## Beat 2: request an app (1.5 min)

```bash
cat examples/app-payments-api.yaml
kubectl apply -f examples/app-payments-api.yaml
kubectl get app payments-api -w                       # ctrl-c when READY
```

Right terminal: the repository, identity, role assignments and Objects appear.
Tab A: refresh, the `payments-api` repo is there, with its pipeline and manifest.

```bash
kubectl --context aks-tergos-demo get namespace,service,httproute -n payments-api
curl -si http://payments-api.$DOMAIN/ | head -1
```

The route exists with nothing behind it yet. There is no Deployment in the
composition: the image changes with every release, so the team owns that part.

## Beat 3: first release (2 min)

Wait for READY first: `DEPLOY_CONFIG` only exists once the identity does.

```bash
gh release create v0.1.0 -R $OWNER/payments-api --generate-notes
gh run watch -R $OWNER/payments-api $(gh run list -R $OWNER/payments-api -L 1 --json databaseId --jq '.[0].databaseId')
curl -s http://payments-api.$DOMAIN/
```

Expected: `payments-api v0.1.0`. Open the URL in a browser for the room.

Tab A: the repo has no secrets. The pipeline got a token because the run is in this
repo's `production` environment, and it can only write to this app's namespace.

## Beat 4: the rules change (2.5 min, the climax, never cut)

New requirement from security: a change to `main` needs a reviewed pull request, in
every repo, including the ones that already exist.

```bash
cat rollout/branch-protection.yaml
./rollout/rollout.sh
```

Right terminal: one `BranchProtection` per app appears. Then, in GitHub:

```bash
for app in orders-api invoices-api payments-api; do
  echo "$app: $(gh api repos/$OWNER/$app/branches/main/protection --jq .required_pull_request_reviews.required_approving_review_count) review required"
done
```

Run it again if the first one is early. Say "within the reconcile interval", not
"instantly". Call back to the opening: no version bumps, no pipelines, nobody
pinged. One definition changed; every repo followed.

```bash
kubectl get compositionrevisions
```

The flip side, if it fits: a bad change reaches everything, which is why it goes
through stages first. The old revision is still there to go back to.

## If something breaks

- `App` not READY within two minutes: `crossplane resource trace app payments-api`.
- Pipeline fails on `azure/login`: the role or credential is still propagating. Re-run
  it with `gh run rerun --failed -R $OWNER/payments-api`, talk over it.
- Pod stuck in `Pending`: AKS Automatic is adding a node. Show `orders-api`, which has
  the same shape and is already live, and come back.
- `ImagePullBackOff`: the cluster cannot pull from the registry. Check it with `az aks check-acr` on the demo resource group, and show `orders-api` meanwhile.
- Anything else: tab B, the recording. Narrate over it.

## Reset between rehearsals

```bash
./rollout/rollback.sh                 # the BranchProtection objects go with it
kubectl delete app payments-api          # removes the repo and everything else
kubectl get managed -A                   # orders-api and invoices-api only, all READY
```

## Rehearsal checklist (things not yet proven)

Rendered and schema-validated locally only. None of this has run live:

- [ ] `az aks create --sku automatic --attach-acr --enable-gateway-api --enable-app-routing-istio` works on the subscription in one go, and the `approuting-istio` GatewayClass shows up.
- [ ] the `approuting-istio` GatewayClass is Accepted and the `Gateway` gets a public IP on managed Cilium; an `HTTPRoute` serves traffic through `<app>.<ip>.nip.io`.
- [ ] provider-kubernetes reaches AKS from kind, signed in as the service principal.
- [ ] all three replicas on fresh nodes: how long do they stay Pending? It decides whether beat 3 fits.
- [ ] Deployment Safeguards accept `deploy/deployment.yaml` from the template.
- [ ] the provider creates the repo from the template, and the `production` environment and `DEPLOY_CONFIG` land on it.
- [ ] the pipeline gets a token through the federated credential, and the namespace-scoped role is enough for `kubectl apply` and `rollout status`. Measure how long a new role assignment takes to work: `az role assignment` can lag.
- [ ] pods pull from the registry without a pull secret.
- [ ] `az acr login` and the push work with only `AcrPush` on the registry. It has no read role on the resource itself.
- [ ] what the empty route answers in beat 2 (expect a 503).
- [ ] beat 4 convergence time from `rollout.sh` to the last repo protected.
- [ ] `kubectl delete app` removes the repo (the token needs `delete_repo`).
