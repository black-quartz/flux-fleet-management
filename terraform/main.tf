# Create the flux-system namespace
resource "kubernetes_namespace_v1" "flux_system" {
    metadata {
      name = "flux-system"
    }

    lifecycle {
        ignore_changes = [metadata]
    }
}

# Create a Kubernetes secret with the GitHub App credentials
resource "kubernetes_secret_v1" "git_auth" {
    metadata {
      name      = "github_auth"
      namespace = "flux-system"
    }

    data = {
        githubAppID             = var.github_app_id
        githubAppInstallationID = var.github_app_installation_id
        githubAppPrivateKey     = var.github_app_pem
    }

    type = "Opaque"

    depends_on = [kubernetes_namespace_v1.flux_system]
}

# Install the Flux Operator
resource "helm_release" "flux_operator" {
  name       = "flux-operator"
  namespace  = "flux-system"
  repository = "oci://ghcr.io/controlplaneio-fluxcd/charts"
  chart      = "flux-operator"
  wait       = true

  depends_on = [kubernetes_namespace_v1.this]

  values = [
    file("values/operator.yml")
  ]
}

# Deploy the Flux Instance
resource "helm_release" "flux_instance" {
    name       = "flux"
    namespace  = "flux-system"
    repository = "oci://ghcr.io/controlplaneio-fluxcd/charts"
    chart      = "flux-instance"
    wait       = true

    values = [
        file("values/instance.yml")
    ]

    set = [
        {
            name  = "instance.cluster.type"
            value = var.cluster_type
        },
        {
            name  = "instance.cluster.size"
            value = var.cluster_size
        },
        {
            name  = "instance.cluster.domain"
            value = var.cluster_domain 
        },
        {
            name  = "instance.distribution.version"
            value = var.flux_version
        },
        {
            name  = "instance.sync.kind"
            value = "GitRepository"
        },
        {
            name  = "instance.sync.url"
            value = var.git_url
        },
        {
            name  = "instance.sync.path"
            value = var.git_path
        },
        {
            name  = "instance.sync.ref"
            value = var.git_ref
        },
        {
            name  = "instance.sync.pullSecret"
            value = "github_auth"
        },
        {
            name  = "healthcheck.enabled"
            value = "true"
            type  = "auto"
        }
    ]

    depends_on = [helm_release.flux_operator]
}
