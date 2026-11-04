# Demos: Automated compliance through control planes

Demos for the talk on 2026-11-24.

| Demo | Directory | Shows |
| --- | --- | --- |
| 1 | `demo-1-managed-resources/` | A Key Vault as a Crossplane managed resource. Opened by hand, it closes again within seconds and leaves a receipt |
| 2 | `demo-2-golden-path/` | One `App` request becomes a repository, an identity and a route. A release puts it live, and a new rule reaches every `App` that exists |

Both run on the same control plane. The demo folders hold only what is shown on stage.
Everything that builds the environment lives in `setup/`:

| Script | Builds | Needed for |
| --- | --- | --- |
| `setup/control-plane.sh` | a local kind cluster with Crossplane, the providers and the Azure credentials. Free, a few minutes | demo 1 and demo 2 |
| `setup/platform.sh` | AKS Automatic, a registry, the Gateway, the GitHub wiring and the platform. Billed, slow | demo 2 |
| `setup/teardown.sh` | removes everything, or with `--platform` only demo 2 | |

See `demo-2-golden-path/README.md` for how demo 2 works, and each demo's
`demo-script.md` for the run of show.

## Run it yourself

Demo 1 costs next to nothing. Demo 2 costs money: AKS Automatic is not on the free tier.
Tear it down when you are done.

**1. Install the tools.** kind, kubectl, kubelogin, helm, jq, gh and az 2.86.0 or later.
Sign in to both CLIs (`az login`, `gh auth login`).

**2. Pick the subscription.** Use one you are allowed to spend on, and make it the
`az` default:

```bash
az account set --subscription <subscription id>
```

**3. Create `setup/azure-creds.json`** (gitignored) for a service principal that is
Owner on the subscription. Contributor cannot create the role assignments demo 2 needs.

```bash
cd setup
(umask 077; az ad sp create-for-rbac --name sp-crossplane-demo --sdk-auth --role Owner \
  --scopes "/subscriptions/$(az account show --query id -o tsv)" > azure-creds.json)
```

**4. Point demo 1 at your tenant.** In `demo-1-managed-resources/02-keyvault.yaml`, set
`tenantId` to yours (`az account show --query tenantId -o tsv`). Change the vault's
name too, since Key Vault names are unique across Azure. Use the same name in
`setup/teardown.sh`, which purges it.

**5. Start the control plane.** Demo 1 is ready to run after this:

```bash
./control-plane.sh
```

### Demo 2 on top

**6. Check the region and quota.** Demo 2 runs in Belgium Central (`LOCATION` in
`setup/platform.sh`). Busy regions such as West Europe block new subscriptions from
the VM sizes AKS Automatic needs. Check that the 4-vCPU D-series sizes show no
restriction:

```bash
az vm list-skus -l belgiumcentral --size Standard_D4 -o table --query \
  "[?contains(['Standard_D4ds_v5','Standard_D4ads_v5','Standard_D4lds_v5','Standard_D4ads_v6','Standard_D4lds_v6'], name)].{size:name, restricted:join(',', restrictions[].reasonCode)}"
```

A new subscription often gets 10 vCPUs per region and 10 or 0 per D-series family.
`platform.sh` runs the AKS system nodes outside the subscription (a managed system
pool), so only the nodes for the apps need quota. 10 in a family is tight for three
apps; check the numbers and request more under **Quotas > Compute** in the portal. A
new subscription may be denied automatically and have to open a support ticket.
`platform.sh` warns when the regional total is low.

```bash
az vm list-usage -l belgiumcentral -o table --query \
  "[?contains(['cores','standardDDSv5Family','standardDADSv5Family','standardDLDSv5Family','standardDadv6Family','StandardDldsv6Family'], name.value)].{quota:localName, limit:limit}"
```

**7. Copy the app template.** Every `App` repository is created from a template in
your own account, and it must keep this name:

```bash
gh repo create demos-tergos-connect-26-app-template --public \
  --template ToonVanDeuren/demos-tergos-connect-26-app-template
gh repo edit "$(gh api user --jq .login)/demos-tergos-connect-26-app-template" --template
```

**8. Create `setup/github-creds.json`** (gitignored) with a classic personal access
token that has the `repo`, `workflow`, `delete_repo` and `read:org` scopes. `read:org`
is needed even on a personal account: the provider reads branch protection rules back
through GitHub's GraphQL API, which requires it. This link fills in the scopes:
[github.com/settings/tokens/new](https://github.com/settings/tokens/new?description=crossplane-demo&scopes=repo,workflow,delete_repo,read:org).
Copy the token, then write the file from the clipboard (`wl-paste` on Wayland,
`pbpaste` on macOS) so it never lands in your shell history:

```bash
(umask 077; jq -n --arg token "$(wl-paste -n)" --arg owner "$(gh api user --jq .login)" \
  '{token: $token, owner: $owner}' > github-creds.json)
```

**9. Build the platform.** This takes a while, most of it creating the AKS cluster:

```bash
./platform.sh
```

Then follow `demo-2-golden-path/demo-script.md`.

### Tear it down

Between rehearsals, remove only demo 2 (the Apps and AKS) and keep the control plane:

```bash
./teardown.sh --platform
```

When you are done for good, remove everything and delete the service principal:

```bash
./teardown.sh
az ad sp delete --id "$(jq -r .clientId azure-creds.json)"
```

## Status

- **Demo 1** ran live on 2026-11-03: create, drift and revert, change log, delete.
  See `demo-1-managed-resources/demo-script.md`.
- **Demo 2** had a full rehearsal on 2026-11-05: all four beats and the reset. See the
  rehearsal checklist in `demo-2-golden-path/demo-script.md`.
