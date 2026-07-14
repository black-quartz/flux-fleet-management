# FluxCD Fleet Management

Central GitOps repository for multi-cluster Kubernetes fleet orchestration, tenant provisioning, and platform automation driven by the Flux Operator.

## Table of Contents

- [Overview](#overview)
- [Repository Structure](#repository-structure)
- [Platform Governance & Design Patterns](#platform-governance--design-patterns)
  - [Contextual Configuration (Flux Runtime Info)](#contextual-configuration-flux-runtime-info)
  - [Multi-Tenant Provisioning](#multi-tenant-provisioning)
- [Operational Runbooks](#operational-runbooks)
  - [Cluster Bootstrap Procedure](#cluster-bootstrap-procedure)
  - [Onboarding Platform Components](#onboarding-platform-components)
  - [Onboarding Tenants](#onboarding-tenants)

## Overview

> [!NOTE]
> This repository follows the [ControlPlane Enterprise for Flux CD]("https://fluxcd.control-plane.io/") reference architecture.
> The `d2` reference architecture comprised of [d2-fleet](https://github.com/controlplaneio-fluxcd/d2-fleet), [d2-infra](https://github.com/controlplaneio-fluxcd/d2-infra) and [d2-apps](https://github.com/controlplaneio-fluxcd/d2-apps) is a set of best practices and production-ready examples for using Flux Operator and OCI Artifacts to manage the continuous delivery of Kubernetes infrastructure and applications on multi-cluster multi-tenant environments.

This repository serves as the definitive GitOps declaration engine for an entire Kubernetes infrastructure fleet. By decoupling cluster-specific state from core infrastructure blueprints, the platform utilizes the Flux Operator to target distinct clusters (e.g., `prod-us-1`, `staging-1`) while applying conditional overrides. This design allows the platform to scale horizontally across regions and clouds with zero configuration drift.

## Repository Structure

```shell
flux-fleet-management/
├── clusters/                      # Cluster-specific topology entrypoints
│   ├── prod-us-1/
│   │   ├── flux-system/           # Flux Operator boostrapped state
│   │   │   ├── flux-instance.yml
│   │   │   ├── flux-operator.yml
│   │   │   └── runtime-info.yml   # Cluster metadata & runtime info context
│   │   ├── kustomization.yml
│   │   ├── policies.yml
│   │   └── tenants.yml
│   └── staging/
├── lib/                           # Cluster RBAC & policy objects
│   ├── kustomization.yml/
│   ├── network_policies/
│   ├── policy_bindings/
│   ├── policy_definitions/
│   ├── role_bindings/
│   └── role_definitions/
├── scripts/
├── tenants/                       # Tenant definitions & ResourceSet schemas
│   ├── apps.yml
│   └── infra.yml
└── terraform/                     # Terraform cluster bootstrap automation
```

## Platform Governance & Design Patterns

### Contextual Configuration (Flux Runtime Info)

Each cluster manages is identity locally via a `runtime-info.yml` ConfigMap. Upstream definitions ingest this ConfigMap to tmeplate values dynamically via post-rendering, removing the need to hardcode specific subdomains or environment boundaries into base application charts.

| Key              | Description                                                                     |
| ---------------- | ------------------------------------------------------------------------------- |
| `CLUSTER_NAME`   | The name of the cluster (`prod-us-1`, `staging-1`).                             |
| `CLUSTER_DOMAIN` | The cluster's internal domain (`prod-us-1.ilysium.io`, `staging-1.ilysium.io`). |
| `CLUSTER_TYPE`   | The type of cluster (`kubernetes`, `eks`, `aks`, or `gks`).                     |
| `ENVIRONMENT`    | The environment of the cluster (`production`, `staging`).                       |

## Multi-Tenant Provisioning

Namespaces and RBAC boundaries are programmatically vended to consumers using **Flux ResourceSets.** Because all tenants share a base namespace template, new components & features can be added to the template and propagated to every single live tenant namespace with just one PR & reconcile run. Namespace features can also be dynamically provisioned using conditional logic.

```yaml
apiVersion: fluxcd.controlplane.io/v1
kind: ResourceSet
metadata:
  name: apps
  namespace: flux-system
spec:
  inputs:
    - name: "analytics-service"
      quota:
        compute: "gold"
        storage: "silver"
      repository:
        url: "https://github.com/ilysiumdotdev/analytics-service-infra"
        path: "./deploy/${ENVIRONMENT}"
      features:
        slack_notifications:
          enabled: true
          channel: "#team-payments-alerts"
          secret_ref:
            name: slack-webhook-secret

  resourcesTemplate: |
    ---
    apiVersion: v1
    kind: Namespace
    metadata:
      name: << inputs.name >>
      labels:
        toolkit.fluxcd.io/role: "tenant"
    ---
    apiVersion: v1
    kind: ServiceAccount
    metadata:
      name: flux
      namespace: << inputs.name >>
    ---
    apiVersion: rbac.authorization.k8s.io/v1
    kind: RoleBinding
    metadata:
      name: flux
      namespace: << inputs.name >>
    roleRef:
      apiGroup: rbac.authorization.k8s.io
      kind: ClusterRole
      name: admin
    subjects:
      - kind: ServiceAccount
        name: flux
        namespace: << inputs.name >>
    <<- if inputs.features.slack_notifications.enabled >
    ---
    apiVersion: notification.toolkit.fluxcd.io/v1beta3
    kind: Provider
    metadata:
      name: slack-provider
      namespace: << inputs.name >>
    spec:
      type: slack
      channel: << inputs.features.slack_notifications.channel >>
      secretRef:
        name: << inputs.features.slack_notifications.secret_ref.name >>
    ---
    apiVersion: notification.toolkit.fluxcd.io/v1beta3
    kind: Alert
    metadata:
      name: namespace-alerts
      namespace: << inputs.name >>
    spec:
      providerRef:
        name: slack-provider
      eventSeverity: info
      eventSources:
        - kind: Kustomization
          name: '*'
        - kind: HelmRelease
          name: '*'
    <<- end>
```

## Operational Runbooks

### Bootstrapping a Cluster

The bootstrap procedure is a one-time operation that installs the Flux Operator and configures Flux controllers and the delivery of platform components/applications.

After bootstrap, changes to the Flux configuration and version upgrades are done by modifying the `flux-instance.yml` manifest and letting Flux reconcile the changes; there is no need to run the bootstrap again or connect to the cluster.

#### GitHub App Configuration

It is recommended to create a dedicated GitHub App for FluxCD. The FluxCD application should have read access to this repository, the infra management repository, and any downstream application repositories it must reconcile.

#### Bootstrap a Kubernetes Cluster

Using Terraform allows for an automated and repeatable installation of the Flux Operator:

```shell
export GITHUB_APP_ID="<GitHub App ID>"
export GITHUB_APP_INSTALLATION_ID="<GitHub App Installation ID>"
export GITHUB_APP_PEM="<GitHub App Private Key>"
```

```shell
cd terraform
terraform init
terraform apply \
  -var cluster_domain="staging-1.ilysium.io" \
  -var git_url="https://github.com/ilysiumdotdev/flux-fleet-management" \
  -var git_path="./clusters/staging-1" \
  -var github_app_id="${GITHUB_APP_ID}" \
  -var github_app_installation_id="${GITHUB_APP_INSTALLATION_ID}" \
  -var github_app_pem="${GITHUB_APP_PEM}"
```

The boostrap performs the following steps:

- Creates the `flux-system` namespace.
- Installs the Flux Operator using Helm.
- Creates a `FluxInstance` pointing at the specified GitHub repository.
- Creates a Kubernetes secret to allow Flux to authenticate to GitHub.

### Onboarding Platform Components

Platform components are cluster add-ons, such as CRDs and their respective controllers, and are reconciled by Flux with **cluster admin** privileges.

To onboard a component from the `flux-infra-management` repository, add a new set of inputs in the `infra` `ResourceSet`:

```yaml
inputs:
  - name: "cert-manager"
    namespace: "cert-manager"
    environment: "${ENVIRONMENT}"

  # Adding external-secrets operator to the cluster
  - name: "external-secrets"
    namespace: "external-secrets"
    environment: "${ENVIRONMENT}"
```

Commit and push the changes to a new branch for onboarding:

```shell
git checkout -b feat/onboard-external-secrets
git add tenants/infra.yml
git commit -m "feat(component): add external-secrets operator"
git push -u origin feat/onboard-external-secrets
```
With this input, the infra `ResourceSet` will create a namespace and the necessary resources to sync the component's configurations from the infra management repository to the cluster (`GitRepository` and `Kustomization` resources).

### Onboarding Tenants

To onboard an application tenant, add a new set of inputs in the `apps` `ResourceSet`:

```yaml
inputs:
  - name: "analytics-service"
    quota:
      compute: "gold"
      storage: "silver"
    repository:
      url: "https://github.com/ilysiumdotdev/analytics-service-infra"
      path: "./deploy/${ENVIRONMENT}"

  # Adding a new application to the cluster
  - name: "payments-service"
    quota:
      compute: "silver"
      storage: "bronze"
    repository:
      url: "https://github.com/ilysiumdotdev/payments-service-infra"
      path: "./deploy/${ENVIRONMENT}
```

Commit and push the changes to a new branch for onboarding:

```shell
git checkout -b feat/onboard-payments-service
git add tenants/apps.yml
git commit -m "feat(tenant): vend namespace for payments-service"
git push -u origin feat/onboard-payments-service
```

Once merged to main after CI validation and platform team approval, the tenant namespace will be provisioned on the next reconcile run by Flux.
