variable "cluster_type" {
    description = "Cluster type (e.g., kubernetes, openshift, azure, aws, gcp)."
    type        = string
    default     = "kubernetes"
}

variable "cluster_size" {
    description = "Cluster size (e.g., small, medium, large)."
    type        = string
    default     = "medium"
}

variable "cluster_domain" {
    description = "Domain used by the cluster (e.g., cluster.local)"
    type        = string
    nullable    = false
}

variable "flux_version" {
    description = "Flux version semver range."
    type        = string
    default     = "2.x"
}

variable "git_url" {
    description = "Git repository URL (e.g., 'https://github.com/example-org/example-repo.git')."
    type        = string
    nullable    = false
}

variable "git_path" {
    description = "Path to the cluster manifests in the Git repository."
    type        = string
    nullable    = false
}

variable "git_ref" {
    description = "Git branch or tag (e.g., 'ref/heads/main')."
    type        = string
    default     = "refs/heads/main"
}

variable "github_app_id" {
    description = "GitHub App ID for GitHub auth."
    type        = string
    nullable    = false
    sensitive   = true
}

variable "github_app_installation_id" {
    description = "GitHub App Installation ID for GitHub auth."
    type        = string
    nullable    = false
    sensitive   = true
}

variable "github_app_pem" {
    description = "GitHub App PEM-encoded private key for GitHub auth."
    type        = string
    nullable    = false
    sensitive   = true
}

variable "slack_webhook_url" {
    description = "Slack Webhook URL to use for platform deployment notifications."
    type        = string
    default     = ""
}