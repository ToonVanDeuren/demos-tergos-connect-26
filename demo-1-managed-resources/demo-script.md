# Run of show: demo 1

A Key Vault as a Crossplane managed resource. It is created live, someone opens it
to the internet by hand, and the platform closes it again within seconds and leaves
a receipt.

The terminal runs `nvim` and `kubectl`; the portal shows the result. `kubectl` runs
against `kind-control-plane`.

## Before the talk

- [ ] `setup/control-plane.sh` ran; `kubectl get providers` all HEALTHY.
- [ ] the namespace and resource group are applied and READY:
  `kubectl apply -f 00-namespace.yaml -f 01-resourcegroup.yaml`, then
  `kubectl get resourcegroup -n demo-1`.
- [ ] the vault does not exist yet: `kubectl get vault -n demo-1` is empty, and
  `az keyvault list-deleted` does not list `kv-crossplane-demo-1-bec`.
- [ ] `az account show` is on the demo subscription.
- [ ] terminal: big font, `cd` into `demo-1-managed-resources/`, prompt cleared.
- [ ] browser tabs: A, the portal on resource group `rg-crossplane-demo-1-bec`; B, the
  fallback recording.

## 1. The vault, as YAML

```bash
nvim 02-keyvault.yaml
```

Point at `publicNetworkAccessEnabled: false`: this vault is closed to the internet,
and the file says so. `resourceGroupNameSelector` finds the resource group by label
(`nvim 01-resourcegroup.yaml` if there is time); nobody copies IDs around.

## 2. Create it live

```bash
kubectl apply -f 02-keyvault.yaml
kubectl get vault -n demo-1 -w            # ctrl-c when READY, about 40 seconds
```

Tab A: refresh, the vault is there; under **Networking**, public access is disabled.

## 3. Someone opens it by hand

Tab A: the vault, **Networking**, "Allow public access from all networks", Apply.
Count to fifteen, refresh: disabled again. Say "within about 15 seconds", not
"instantly". Nobody was paged and nobody ran a script: the control plane checks
every 15 seconds that Azure still matches the file. The production default is 10
minutes; it is turned up for the room.

## 4. The receipt

```bash
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-azure-keyvault \
  -c changelogs-sidecar --since=10m \
  | jq -c 'select(.kind=="Vault" and .operation=="OPERATION_TYPE_UPDATE")
           | {timestamp, operation,
              observed: .snapshot.status.atProvider.publicNetworkAccessEnabled,
              desired: .snapshot.spec.forProvider.publicNetworkAccessEnabled}'
```

Expected, one line per correction:

```json
{"timestamp":"2026-11-03T23:21:18Z","operation":"OPERATION_TYPE_UPDATE","observed":true,"desired":false}
```

What was found, what it should be, when it was fixed. That is the audit evidence,
written by the thing that did the fixing.

## If something breaks

- Vault not READY within two minutes: `kubectl describe vault -n demo-1 kv-crossplane-demo-1-bec`,
  look at the `LastAsyncOperation` condition.
- "name already in use": a soft-deleted vault from a rehearsal. Purge it
  (`az keyvault purge --name kv-crossplane-demo-1-bec`, takes a minute) and apply again,
  or go to tab B.
- Not reverted after 30 seconds: check the provider is running
  (`kubectl get pods -n crossplane-system`), and talk over it: the next check comes.
- The receipt is empty: the provider pod restarted after the change, and the change
  log only lives in the sidecar's output. Show the line above from the slide instead.
- Anything else: tab B, the recording. Narrate over it.

## Reset between rehearsals

```bash
kubectl delete -f 02-keyvault.yaml        # Crossplane purges it too: the name is free again
az keyvault list-deleted                   # should not list kv-crossplane-demo-1-bec
```

The resource group can stay.

## Rehearsal checklist

Tested on 2026-11-03 with the az CLI (create 38s, revert 6 to 25s, delete 12s):

- [ ] the portal path in beat 3: does "Allow public access from all networks" change
  anything besides `publicNetworkAccess` (the network ACLs), and is that reverted too?
- [ ] the vault and the drift line are readable at the stage font size.
