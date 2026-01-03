# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AnshulG Clusters is a multi-cluster Kubernetes infrastructure managing 40+ applications across:
- **GKE Cluster (k8s/)**: Cloud-based apps on Google Kubernetes Engine
- **Raspberry Pi 5 Cluster (rpi5/)**: Edge computing with k3s (media management, DNS, storage, monitoring)
- **Auth Server (auth-server/)**: KanIDM authentication service on dedicated GCP instance
- **Database Server (db-server/)**: PostgreSQL 17 database with SSL/TLS, backups, and mail setup
- **Infrastructure (terraform/)**: GCP resource management via Terraform Cloud

All clusters use **GitOps** (ArgoCD) with the **app-of-apps pattern**.

## Common Commands

### Cluster Management (x.pl)

The `x.pl` Perl script is the primary tool for cluster operations:

```bash
# Create new application
./x.pl new --cluster rpi5 --name myapp --port 8080
./x.pl new --cluster k8s --name myapp --stateful  # For stateful apps

# Create new Helm chart application
./x.pl helm --cluster rpi5 --name myapp

# Create secrets
./x.pl secret mysecret --cluster rpi5 --app myapp -- --from-literal=key=value

# Seal unencrypted secrets (requires correct kubectl context)
./x.pl seal rpi5/myapp
./x.pl seal --namespace-wide rpi5/myapp

# Deploy auth server
./x.pl deploy auth
```

### Code Quality & Testing

```bash
# Run all pre-commit hooks
pre-commit run --all-files

# Shellcheck (shell scripts)
shellcheck **/*.sh

# Perl code quality
perlcritic --profile .perlcriticrc ./x.pl

# Perl code formatting
perltidy -b -bext='/' x.pl
```

### Cluster Setup

```bash
# Initial k3s cluster setup on Raspberry Pi (runs locally on rpi5)
cd rpi5
./setup-k3s.sh

# Deploy k3s cluster applications (runs locally on rpi5)
./setup.sh

# Auth server deployment (runs locally, SSHs to server)
cd auth-server
./deploy.sh    # Uploads files and runs setup.sh remotely

# Database server deployment (runs locally, SSHs to server)
cd db-server
./deploy.sh    # Uploads files and runs setup.sh remotely

# Or use x.pl for server deployments
./x.pl deploy auth
./x.pl deploy db
```

### Kubernetes Operations

```bash
# Check ArgoCD application status
kubectl get applications -n argocd

# View application logs
kubectl logs -n <app-name> deployment/<app-name>

# Port-forward to service
kubectl port-forward -n <app-name> svc/<app-name> <local-port>:<service-port>
```

## Architecture

### GitOps: App-of-Apps Pattern

Each cluster has an `apps/` Helm chart that generates ArgoCD Application manifests:

```
k8s/
├── apps/                    # Parent chart (app-of-apps)
│   ├── values.yaml         # Cluster config (tld: anshulg.com)
│   └── templates/          # ArgoCD Application manifests
│       ├── miniflux.yaml
│       └── ...
├── miniflux/               # Child app manifests
│   ├── deployment.yaml
│   ├── service.yaml
│   └── ingress.yaml
└── ...

rpi5/
├── apps/                    # Parent chart (app-of-apps)
│   ├── values.yaml         # Cluster config
│   └── templates/
│       ├── internal/       # System components
│       └── media/          # Media apps
├── jellyfin/               # Child app (Helm chart)
├── sonarr/
└── ...
```

**Key Points:**
- Changes to `apps/templates/*.yaml` add/remove ArgoCD applications
- Each app gets its own namespace (same as app name)
- ArgoCD watches GitHub main branch and auto-syncs
- TLD is defined in `<cluster>/apps/values.yaml` (legacy - newer apps use Kustomize with direct domain config)
- Simple apps should use Kustomize with shared bases from `kustomize/` directory

### Secret Management

Three approaches used:
1. **1Password Connect**: Operator injects secrets from 1Password vault
2. **Sealed Secrets**: Encrypted YAML files (use `x.pl seal` to encrypt)
3. **Workload Identity**: For GKE to GCP service account binding

Unencrypted secrets follow pattern: `*.unencrypted.yaml` (gitignored).

### Ingress & Networking

- **Traefik** is the ingress controller in both clusters
- Use `IngressRoute` (Traefik CRD) instead of standard Kubernetes Ingress
- TLS certificates managed by cert-manager
- **GKE cluster domains**: `anshulg.com`
- **rpi5 cluster domains**:
  - `.internal` - Internal CA certificates (private)
  - `.anshulg.direct` - LetsEncrypt certificates (public)

Example IngressRoute:
```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: myapp
spec:
  routes:
    - match: Host(`myapp.{{ .Values.tld }}`)
      kind: Rule
      services:
        - name: myapp
          port: 80
```

### Application Structure

When creating new apps with `x.pl new`:
- Creates app directory: `<cluster>/<app-name>/`
- Generates Kubernetes manifests: deployment, service, ingress
- Adds ArgoCD Application to `<cluster>/apps/templates/`
- App namespace matches app name

For Helm charts (`x.pl helm`):
- Creates full Helm chart structure
- Must have `values.yaml` even if empty
- ArgoCD source points to chart directory

### Kustomize-Based Apps

The repository provides shared Kustomize bases and components for simple apps:

**Structure:**
```
kustomize/
├── base/                           # Base service manifest
│   └── service.yaml
├── workloads/
│   ├── deployment/                # Deployment workload
│   │   └── deployment.yaml
│   └── statefulset/               # StatefulSet workload
│       └── statefulset.yaml
└── components/
    ├── ingress/                   # Internal ingress (.internal)
    │   ├── certificate.yaml
    │   ├── ingress.yaml
    │   └── secret.yaml
    ├── direct-ingress/            # Public ingress (.anshulg.direct)
    │   ├── certificate.yaml
    │   ├── ingress.yaml
    │   └── secret.yaml
    ├── security-context/          # Security settings
    ├── tailscale/                 # Tailscale integration
    └── ...
```

**Creating a Kustomize app:**

Create `rpi5/myapp/kustomization.yaml`:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../kustomize/base
  - ../../kustomize/workloads/deployment

components:
  - ../../kustomize/components/ingress        # .internal domain
  - ../../kustomize/components/security-context

namePrefix: myapp-
labels:
  - pairs:
      app.kubernetes.io/name: myapp
    includeSelectors: true

images:
  - name: busybox
    newName: my-image
    newTag: v1.0.0

configMapGenerator:
  - name: domain-config
    literals:
      - DOMAIN=myapp.internal
```

**Benefits:**
- Eliminates duplicate YAML across apps
- Consistent security, networking, and resource configuration
- Easy to switch between deployment/statefulset workloads
- Simple to add/remove ingress, tailscale, etc.
- See `rpi5/whoami/`, `rpi5/glance/`, `rpi5/jellyseerr/` for examples

### Resource Specifications

Standard resource patterns:
- **rpi5 apps**: `requests: {cpu: 100m, memory: 128Mi}`, `limits: {memory: 512Mi}`
- **k8s apps**: Higher limits, typically 3 replicas for HA
- **Stateful apps**: Use PersistentVolumeClaims with `hostpath-storage` (rpi5) or GKE storage classes

### Deployment Flow

1. Push changes to GitHub (main branch)
2. GitHub Actions runs checks (shellcheck, perlcritic, perltidy, pre-commit)
3. Renovate auto-updates dependencies (Docker images, Helm charts)
4. ArgoCD detects changes via polling
5. ArgoCD syncs applications to clusters
6. Traefik routes traffic with automatic TLS

Auth server deployment is separate:
- Triggered by changes to `auth-server/` directory
- GitHub Actions validates configs (shellcheck, Caddy config)
- Whitelists runner IP in GCP firewall
- Runs `./x.pl deploy auth` which calls `deploy.sh`
- `deploy.sh` SSHs to server, uploads files, runs `setup.sh` remotely
- Cleans up firewall rule

## Important Patterns

### Creating New Applications

1. **Standard app (deployment + service + ingress):**
   ```bash
   ./x.pl new --cluster rpi5 --name myapp --port 8080
   ```
   - Edit generated manifests in `rpi5/myapp/`
   - Commit and push; ArgoCD will deploy

2. **Simple app with Kustomize (recommended for basic apps):**
   - Create `rpi5/myapp/kustomization.yaml` using shared base manifests
   - Compose from shared components: base, workloads, ingress, security
   - See `rpi5/whoami/` as reference example
   - Benefits: DRY (Don't Repeat Yourself), consistent configuration

3. **Helm chart app:**
   ```bash
   ./x.pl helm --cluster rpi5 --name myapp
   ```
   - Customize chart in `rpi5/myapp/`
   - Must have `values.yaml`

4. **Stateful app (with PVC):**
   ```bash
   ./x.pl new --cluster rpi5 --name myapp --stateful
   ```
   - Adds PersistentVolumeClaim to manifests

### Working with Secrets

Sealed Secrets workflow:
1. Create `myapp/secret.unencrypted.yaml` with plain secrets
2. Ensure kubectl context matches target cluster
3. Run `./x.pl seal rpi5/myapp`
4. Commit encrypted `secret.yaml`

1Password Connect (preferred for new apps):
1. Store secret in 1Password vault
2. Reference in deployment using OnePasswordItem CRD
3. Operator injects at runtime

### Modifying Existing Apps

- **Don't edit ArgoCD Application manifests directly** in `apps/templates/` unless changing ArgoCD-specific settings
- Edit actual app manifests in `<cluster>/<app-name>/`
- For Helm apps, edit `values.yaml` or chart templates
- Commit changes; ArgoCD will detect and sync automatically

### Cluster Context

Critical for `x.pl seal`:
```bash
# Check current context
kubectl config current-context

# Switch context
kubectl config use-context <cluster-name>

# rpi5 cluster uses k3s context
# k8s cluster uses GKE context
```

Wrong context = secrets sealed with wrong key = decryption failure.

## Code Quality Standards

### Pre-commit Hooks
- Trailing whitespace removal
- File ending fixes
- Shebang validation
- Merge conflict detection
- Large file prevention

### Perl (x.pl)
- Must pass `perlcritic --profile .perlcriticrc`
- Must pass `perltidy -b -bext='/'`
- Perl 5.38 compatibility required

### Shell Scripts
- Must pass `shellcheck` with no errors
- Use `#!/usr/bin/env bash` shebang

All checks run in CI on every PR.

## Technology Stack

### Core Infrastructure
- **Kubernetes**: k3s (rpi5), GKE (k8s)
- **GitOps**: ArgoCD (app-of-apps pattern)
- **Ingress**: Traefik
- **Secrets**: 1Password Connect, Sealed Secrets
- **Certificates**: cert-manager, GCP Private CA
- **Monitoring**: Datadog
- **Manifest Management**: Kustomize (shared bases and components)

### Cloud & IaC
- **GCP**: GKE, Compute Engine, Cloud Storage, Cloud DNS, Private CA
- **Terraform**: Infrastructure management (Terraform Cloud backend)
- **Renovate**: Automated dependency updates

### Authentication
- **KanIDM**: Identity and auth management
- **Caddy**: Reverse proxy for auth server
- **OAuth Proxy**: Application-level auth

## Project-Specific Notes

### Cluster Differences

**k8s (GKE):**
- TLD: `anshulg.com`
- Managed Kubernetes
- Higher resource limits
- Typically 3 replicas for HA
- Workload Identity for GCP access

**rpi5 (k3s):**
- TLDs: `.internal` (Internal CA), `.anshulg.direct` (LetsEncrypt)
- Self-hosted on Raspberry Pi 5
- Resource-constrained (128Mi-512Mi memory)
- 40+ applications (media, DNS, storage, monitoring)
- hostpath-storage for persistence
- Kustomize-based apps for simple deployments
- Network gateway: `gateway.anshulg.direct` (192.168.1.100) - see Gateway Router section

### Auth Server Architecture

Runs on dedicated GCP VM (n1-standard-1, OpenSUSE Leap 15.6):
```
Internet → Caddy (TLS termination) → KanIDM Docker container
                ↓
         LetsEncrypt (public certs)
                ↓
         GCP Private CA (internal certs)
```

**Notable implementation details:**
- KanIDM runs as a dedicated `kanidm` system user under `/srv/kanidm` (data, certs, backups)
- TLS certificate issuance/renewal is handled by a systemd timer (`kanidm-cert-renew.timer`)
- Docker image cleanup runs weekly via `docker-image-prune.timer`
- HAProxy binds LDAPS on both IPv4 and IPv6
- `auth.anshulg.com` and `ldap.auth.anshulg.com` publish IPv6 (AAAA) records
- SSH hardening applied (no root login, no password auth)

**Deployment:**
```bash
cd auth-server
./deploy.sh    # Runs locally: SSHs to server, uploads files, runs setup.sh remotely
```

Or via `x.pl`:
```bash
./x.pl deploy auth    # Internally runs ./auth-server/deploy.sh
```

Also deployed via GitHub Actions (on push to auth-server/ directory).
Note: `setup.sh` runs ON the server, not locally.

### Database Server Architecture

Dedicated PostgreSQL 17 server running on Raspberry Pi 4 (4GB RAM, 4 CPUs):

**Features:**
- **PostgreSQL 17** - Tuned for web workloads (pgtune.leopard.in.ua settings)
- **SSL/TLS** - GCP Private CA certificates for encrypted connections
- **Network Access** - Listens on all interfaces, allows 192.168.0.0/16
- **Authentication** - SCRAM-SHA-256 for secure password auth
- **Backups** - Restic to GCS bucket with resticprofile scheduling
- **Mail** - Postfix MTA with Fastmail relay + Zeyple GPG encryption
- **Firewall** - nftables for network security
- **Monitoring** - Mail notifications for backup status

**Connection:**
- Host: `rpi4.anshulg.direct` (192.168.1.9)
- Port: 5432 (PostgreSQL default)
- SSL: Required (with Internal CA certificate)
- Max connections: 100
- Apps use this for persistent storage (e.g., Audiomuse)

**Deployment:**
```bash
cd db-server
./deploy.sh    # Runs locally: SSHs to server, uploads files, runs setup.sh remotely
```

Or via `x.pl`:
```bash
./x.pl deploy db    # Internally runs ./db-server/deploy.sh
```

Note: `setup.sh` runs ON the server, not locally.

### Gateway Router

Network gateway for rpi5 cluster at `gateway.anshulg.direct` (192.168.1.100):

**Services:**
- **HAProxy** - Load balancer and reverse proxy for:
  - HTTPS traffic
  - Kubernetes API (k8s)
  - IRC
- **WireGuard** - VPN for secure remote access to the network (192.168.3.0/24)
- **FRR** (Free Range Routing) - OSPF/BGP daemon for dynamic routing with LAN
- **Dynamic DNS** - Runs `scripts/ddns.sh` to update DNS records for dynamic public IP

**Network Topology:**
- **LAN Interface** (`end0`): 192.168.1.100/24
  - Main network interface
  - Default route via 192.168.1.1 (upstream router)
  - IPv6: fd30:e1bf:9b4f::/64 (ULA)
  - Public IPv6 (dynamic)
- **WireGuard Interface** (`wg0`): 192.168.3.1/24
  - VPN network for remote access clients
  - IPv6: fd30:e1bf:9b4f:100::/64
- **Routed Networks** (via OSPF):
  - 192.168.1.0/24 - Local LAN (rpi5 cluster, database server)
  - 192.168.3.0/24 - WireGuard VPN clients
  - 192.168.9.0/24 - Additional routed subnet
  - 192.168.2.0/24 - Reserved (unreachable)

**Network Role:**
- Entry point for external traffic to rpi5 cluster
- Routes traffic to appropriate k3s services
- Provides remote access via WireGuard VPN
- OSPF peering allows dynamic routing within LAN
- Bridges VPN clients (192.168.3.0/24) with LAN resources

**Management:**
- **Not currently managed by this git repository**
- May be added to IaC management in the future
- Manual configuration and deployment

### Media Stack (rpi5)

Large media management ecosystem:
- **Content**: Jellyfin, Audiobooks, Calibre
- **Automation**: Sonarr (TV), Radarr (Movies), Bazarr (Subtitles), Prowlarr (Indexers)
- **Downloads**: LazyLibrarian, nzbhydra2
- **Management**: Overseerr, Kometa
- **Backup**: Restic (to GCS)

All use Traefik ingress with `.internal` (Internal CA) or `.anshulg.direct` (LetsEncrypt) domains.

### Terraform & GCP Notes

- Terraform now manages a dedicated `rpi5-cas-issuer` service account for cert-manager (Private CA)
- Module outputs are exposed for IPs, buckets, and service accounts (see `terraform/outputs.tf`)

### Renovate Configuration

Automated updates for:
- Docker images
- Helm charts
- GitHub Actions
- Terraform modules
- Perl dependencies

Auto-merge enabled for patch/digest updates. Check `.github/renovate.json` for custom rules.
