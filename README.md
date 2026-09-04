# AKS Platform — Production

Terraform configuration for the production Azure Kubernetes Service platform:
network, cluster, key material, workload identities, storage and observability.

Owned by **platform-engineering**. Changes reach production through a reviewed
pull request; there is no out-of-band apply path.

---

## Layout

| File | Contents |
|---|---|
| `versions.tf` | Terraform and provider constraints, remote state backend |
| `main.tf` | Provider configuration, naming, tagging, resource group |
| `variables.tf` | Input variables and validation |
| `network.tf` | Virtual network, subnets, network security groups, private DNS |
| `aks.tf` | Managed cluster and node pools |
| `keyvault.tf` | Key Vault, platform keys, crypto role assignments |
| `identity.tf` | Workload identities and federated credentials |
| `monitoring.tf` | Log Analytics, diagnostic settings, alerts |
| `storage.tf` | Platform storage account, private endpoint, lifecycle policy |
| `outputs.tf` | Values consumed by the GitOps repository and runbooks |
| `prod.auto.tfvars` | Production environment values |

---

## Architecture

**Networking.** Azure CNI in overlay mode. Pods draw addresses from a
non-routable overlay CIDR, so node subnets are sized for nodes and private
endpoints rather than for pod density. Four subnets: system nodes, user nodes,
private endpoints, and a reserved ingress tier.

**Node pools.** A system pool carrying platform add-ons and a user pool for
application workloads, both autoscaled and spread across three availability
zones. Both pools set `temporary_name_for_rotation`, so a VM size change is an
in-place rotation rather than a cluster rebuild.

**Identity.** Pods authenticate to Azure through workload identity federation —
a Kubernetes service account token is exchanged for an Entra ID token. There are
no client secrets in this configuration and none in the cluster. Each federated
credential is pinned to one namespace and one service account.

**Key material.** A single Key Vault with Entra ID RBAC authorization and purge
protection enabled, holding the platform's customer-managed keys. Purge
protection means the vault name is unrecoverable for the soft-delete retention
window after a destroy, which is why generated names carry a random suffix.

**Observability.** Control plane logs, NSG logs and storage write/delete logs
ship to a single Log Analytics workspace with a daily ingestion cap. Capacity
alerts on node CPU and memory; activity log alerts on deletion of the cluster or
the vault, and on Azure service health incidents in the region.

---

## Prerequisites

Everything below is created once, outside this configuration, during tenant
bootstrap:

- A resource group and storage account for remote state, with the deployment
  identity holding **Storage Blob Data Contributor** on it.
- An Entra ID app registration with federated credentials for this repository,
  holding **Contributor**, **Role Based Access Control Administrator** and
  **Key Vault Administrator** at subscription scope. The last two are not
  optional: this configuration creates role assignments and key material.
- An Entra ID group for cluster administrators. Its object ID goes into
  `aks_admin_group_object_ids`.
- Resource providers registered: `Microsoft.ContainerService`,
  `Microsoft.KeyVault`, `Microsoft.Network`, `Microsoft.OperationalInsights`,
  `Microsoft.Storage`, `Microsoft.Insights`, `Microsoft.ManagedIdentity`.

Set `storage_account_name` in the backend block of `versions.tf` and
`repository_url` in `prod.auto.tfvars` before the first init.

---

## Working on this repository

```bash
terraform init
terraform fmt -recursive
terraform validate
terraform plan
```

Authentication is OIDC in CI and Azure CLI locally. `ARM_SUBSCRIPTION_ID` is
required by the AzureRM 4.x provider; either export it or set `subscription_id`
in a local tfvars file that is not committed.

### Versions and the lock file

Terraform is pinned to **1.15.8** in `.github/workflows/terraform.yml`. Use the
same version locally: a newer Terraform writes a state snapshot that the CI job
cannot read.

Providers are pinned exactly in `versions.tf` — `azurerm 4.81.0` and
`random 3.9.0`. The AzureRM 4.x line renames arguments between minor releases,
so an upgrade is a deliberate, reviewed edit rather than something that happens
on the next `init`.

`.terraform.lock.hcl` is committed and carries checksums for both `linux_amd64`
(the CI runner) and `windows_amd64` (workstations). A lock file generated on one
platform alone fails `terraform init` on the other. After changing a provider
version, regenerate it for both:

```bash
terraform init -upgrade
terraform providers lock -platform=linux_amd64 -platform=windows_amd64
```

---

## Change safety

The pull request pipeline runs `fmt`, `validate` and `plan`, then evaluates the
plan JSON in a separate job. That job fails if the plan contains any delete
action, including the delete half of a replacement. It is a required status
check on `main` with administrator enforcement, so no reviewer, automation or
account can merge past it.

If a change legitimately needs to replace a resource, that is a conversation and
a separate, deliberate pull request — not something to force through the gate.

Two changes that force cluster replacement and are easy to make by accident:

- Changing `default_node_pool.vm_size` without `temporary_name_for_rotation`.
- Toggling `only_critical_addons_enabled` on the system pool.

---

## Autoscaler and drift

`node_count` on both pools is ignored via `lifecycle.ignore_changes`. The
cluster autoscaler owns the running count; without this, every plan following a
scaling event shows a change that nobody made.

A plan on an unchanged branch should be empty. If it is not, investigate the
drift before merging anything else — a noisy baseline hides real changes.

---

## About this repository

This is the reference configuration from the talk *"I Let an AI Read My
Terraform So I Don't Have To"* — agentic infrastructure as code, using deep code
review and Agent Merge against a real AKS platform.

The interesting file is [`.github/copilot-instructions.md`](.github/copilot-instructions.md).
It is the organisation policy that turns generic security advice into findings
about *this* platform, and it is read from the head branch of a pull request, so
it can be iterated on inside a feature branch.

Licensed under the MIT License — see [LICENSE](LICENSE). Copy anything you find
useful.
