# Infrastructure review policy — platform engineering

This repository provisions the production Azure Kubernetes Service platform.
Review changes against the standards below, not only against general Terraform
or Azure best practice. Where a change is syntactically valid but conflicts with
one of these standards, say so explicitly and give the severity.

## AKS control plane

- The API server MUST restrict `authorized_ip_ranges` to the VPN gateway CIDR
  held in `var.admin_cidr`. A cluster with no `api_server_access_profile` block
  is reachable from `0.0.0.0/0` and is a **P1** finding.
- `local_account_disabled` MUST be `true`, with
  `azure_active_directory_role_based_access_control` configured and
  `azure_rbac_enabled = true`. Local cluster credentials bypass central identity
  governance and the conditional access policies applied to Entra ID sign-in.
  Leaving local accounts enabled is a **P1** finding.
- etcd MUST be encrypted with a customer-managed key via the
  `key_management_service` block, referencing a key in the platform vault. The
  Azure platform key is not acceptable for a cluster at this data
  classification. A missing `key_management_service` block is a **P2** finding.
- `private_cluster_enabled = false` is acceptable only when the API server is
  also constrained by authorized IP ranges. Public endpoint plus unrestricted
  ranges is the combination to flag.

## Identity

- Workload authentication is workload identity federation. Flag any
  introduction of a client secret, certificate credential or connection string
  into this configuration.
- Federated credential `subject` values MUST name one namespace and one service
  account. Wildcards let any pod in the cluster assume the identity.
- Role assignments MUST be least privilege. Flag `Owner`, `Contributor` or
  `User Access Administrator` granted to a workload identity.

## Key material

- The platform vault MUST have `purge_protection_enabled = true` and
  `enable_rbac_authorization = true`. Vault access policies are not used in this
  repository.
- Flag any reduction in `soft_delete_retention_days`.

## Change safety

- Flag any change whose plan would delete or replace a stateful resource — the
  cluster, the vault, a key, or the storage account.
- Node pool `vm_size` changes MUST set `temporary_name_for_rotation`. Without
  it, resizing a pool replaces the cluster.
- Flag changes to `only_critical_addons_enabled`, `private_cluster_enabled`,
  `network_plugin`, `service_cidr` or `pod_cidr`. All force replacement.

## Networking

- Node subnet network security groups MUST NOT contain deny rules that narrow
  the AKS outbound requirements. Additive allow rules for documentation are fine.
- Flag any subnet whose address space overlaps `var.service_cidr` or
  `var.pod_cidr`.

## Tagging and cost

- Every resource that supports tags MUST carry `local.common_tags`.
- Flag removal of the Log Analytics `daily_quota_gb` cap, and any change that
  enables the `kube-audit` diagnostic category, which is high volume and
  expensive.

## Review style

Report findings with a severity, the file and the resource, what the risk is in
concrete terms, and the specific configuration change that resolves it. Do not
repeat findings that a linter would already catch unless they interact with one
of the standards above.
