# Setup

Everything the demos run on. Run the commands from this folder.

Demo 1 costs next to nothing. Demo 2 runs AKS Automatic, which is billed by the hour,
so tear it down when you are done.

## Before the first run

**1. Tools.** kind, kubectl, kubelogin, helm, jq, gh and az 2.86.0 or later. Sign in
to both CLIs: `az login`, `gh auth login`.

**2. A subscription** you are allowed to spend on, as the `az` default:

```bash
az account set --subscription <subscription id>
```

**3. `azure-creds.json`**, for a service principal that is Owner on the subscription
(Contributor cannot create the role assignments demo 2 needs):

```bash
(umask 077; az ad sp create-for-rbac --name sp-crossplane-demo --sdk-auth --role Owner \
  --scopes "/subscriptions/$(az account show --query id -o tsv)" > azure-creds.json)
```

**4. Your tenant in demo 1.** In `../demo-1-managed-resources/02-keyvault.yaml`, set
`tenantId` to yours (`az account show --query tenantId -o tsv`), and give the vault a
name of your own: Key Vault names are unique across Azure. Use the same name in
`teardown.sh`.

## Demo 1

```bash
./control-plane.sh
```

## Demo 2, on top of demo 1

**5. Region and quota.** Demo 2 runs in Belgium Central (`LOCATION` in `lib.sh`). Busy
regions such as West Europe block new subscriptions from the VM sizes AKS Automatic
needs, and new subscriptions get little vCPU quota. `platform.sh` warns when it is low;
request more under **Quotas > Compute** in the portal.

**6. The app template, in your account.** Every app repository is created from it, and
it must keep this name:

```bash
gh repo create demos-tergos-connect-26-app-template --public \
  --template ToonVanDeuren/demos-tergos-connect-26-app-template
gh repo edit "$(gh api user --jq .login)/demos-tergos-connect-26-app-template" --template
```

**7. `github-creds.json`**, with a classic token with the `repo`, `workflow`,
`delete_repo` and `read:org` scopes
([create one](https://github.com/settings/tokens/new?description=crossplane-demo&scopes=repo,workflow,delete_repo,read:org)).
Copy it, then write the file from the clipboard (`pbpaste` on macOS):

```bash
(umask 077; jq -n --arg token "$(wl-paste -n)" --arg owner "$(gh api user --jq .login)" \
  '{token: $token, owner: $owner}' > github-creds.json)
```

**8. Build it.** About 10 minutes, most of it creating the cluster:

```bash
./platform.sh
```

## Tear it down

```bash
./teardown.sh --platform    # demo 2 only, between rehearsals
./teardown.sh               # everything
az ad sp delete --id "$(jq -r .clientId azure-creds.json)"   # when you are done for good
```
