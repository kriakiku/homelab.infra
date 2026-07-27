# home-ops

Kubernetes home lab cluster deployed with [Talos](https://www.talos.dev) on [Proxmox](https://www.proxmox.com), managed via [Flux](https://fluxcd.io) GitOps.

## Architecture

| Component | Technology |
|---|---|
| OS | Talos Linux (custom schematic via factory.talos.dev) |
| Hypervisor | Proxmox (2 VMs: 1 controlplane + 1 worker) |
| GitOps | Flux CD |
| Ingress | Cloudflare Tunnel + Envoy Gateway |
| Certificates | cert-manager (Let's Encrypt DNS-01 via Cloudflare) |
| Secrets | External Secrets Operator + Vaultwarden (Bitwarden Secrets Manager) |
| Storage | local-path-provisioner (NVMe) + direct NFS mounts (HDD) |
| Backups | Kopiur → expanse S3 | Restic → Google Drive |
| Monitoring | kube-prometheus-stack + Grafana + Gatus |
| Notifications | Gotify |
| DNS | Cloudflare (public) + UniFi (private) |
| CI | Self-hosted ARC runners on Kata Containers |

## Prerequisites

- Proxmox host with 2 VMs provisioned (1 controlplane, 1 worker)
- Talos CLI (`talosctl`) and `just` installed locally
- [Vaultwarden](https://github.com/dani-garcia/vaultwarden) instance with Bitwarden Secrets Manager enabled
- `1337.pet` domain in Cloudflare
- GitHub App for CI runners

## Setup

### 1. Generate Talos secrets

```bash
talosctl gen secrets -o talos/secrets.yaml
```

Fill in `talos/machineconfig.yaml.j2` with generated keys, or adjust the config to load from `secrets.yaml`.

### 2. Create cluster schematic

The schematic is defined in `talos/schematic.yaml.j2`. Build it:

```bash
just talos schematic-id
```

### 3. Bootstrap Talos nodes

Apply machine config to both VMs:

```bash
just apply-node k8s-0
just apply-node k8s-1
```

Wait for health checks, then:

```bash
talosctl -n <controlplane-ip> bootstrap
talosctl kubeconfig -n <controlplane-ip> -f
```

### 4. Create Vaultwarden bootstrap secret

```bash
VAULTWARDEN_TOKEN=$(curl -sX POST https://vault.1337.pet/identity/connect/token \
  -d "grant_type=client_credentials&scope=api" \
  -u "user.8fc3a70e-ffaa-4afc-891f-c01ebfc9e43c:<client_secret>" \
  | jq -r '.access_token')

kubectl create ns external-secrets --dry-run=client -o yaml | kubectl apply -f -
kubectl -n external-secrets create secret generic vaultwarden-secret \
  --from-literal=token="$VAULTWARDEN_TOKEN" \
  --from-literal=client_id=user.8fc3a70e-ffaa-4afc-891f-c01ebfc9e43c \
  --from-literal=client_secret=<client_secret> \
  --from-literal=organization_id=76cb6e80-15c7-4fb8-8a11-e7489a28c045
```

### 5. Bootstrap cluster

```bash
just bootstrap cluster
```

This applies bootstrap manifests, syncs helmfile, and deploys Flux. Flux then reconciles all apps from `kubernetes/apps/`.

## Secrets

Secrets live in Vaultwarden (Bitwarden Secrets Manager), organized by project:

| Project | Purpose |
|---|---|
| `infra/cloudflare` | Cloudflare API tokens, tunnel credentials |
| `network/unifi` | UniFi API key |
| `monitoring/buddy` | Heartbeat token for status page |
| `monitoring/gotify` | Gotify notification tokens |
| `monitoring/grafana` | Grafana admin password |
| `apps/qui` | Session secret + OIDC client secret |
| `apps/smtp-relay` | SMTP relay credentials |
| `apps/backups` | Kopiur password + Google Drive OAuth |
| `apps/pocket-id` | Encryption key |
| `shared/maxmind` | MaxMind GeoLite2 license key |
| `shared/nordvpn` | NordVPN WireGuard private key |
| `github/flux` | Flux webhook token + GitHub PAT |
| `github/app` | GitHub App credentials for ARC runners |
| `github/konflate` | Konflate webhook secret |
| `databases/seaweedfs` | S3 secret key |
| `backups/restic` | Restic password + rclone config |

ESO's `vaultwarden` ClusterSecretStore syncs them into Kubernetes Secrets via `dataFrom.find`.

## Network architecture

| VLAN | Subnet | Purpose |
|---|---|---|
| VLAN 3 | `10.10.3.0/24` | IoT |
| VLAN 4 | `10.10.4.0/24` | Infrastructure — nodes, BGP, LB IP pool (10.10.4.224/27) |
| VLAN 5 | `10.10.5.0/24` | Storage — NFS, isolated by CiliumNetworkPolicy |
| VLAN 6 | `10.10.6.0/24` | Egress — internet access, client isolation |
| VLAN 7 | `10.10.7.0/24` | VPN |
| — | `10.10.99.0/24` | Pod CIDR (internal to Cilium) |
| — | `10.43.0.0/16` | Service CIDR (internal) |

### Node networking

| Node | NICs |
|---|---|
| `k8s-0` (controlplane) | VLAN 4 only |
| `k8s-1` (worker) | VLAN 4 + VLAN 5 + VLAN 6 |
| `media` (LXC) | VLAN 5 only (NFS server) |

### Egress isolation

CiliumNetworkPolicy restricts pod internet access:
- Pods with `egress: "true"` label → internet via VLAN 6
- All other pods → internal subnets only (VLAN 4, cluster CIDRs)
- Pods with `nfs-access: "true"` label → can reach `10.10.5.0/24:2049`
- All other pods → blocked from storage VLAN

```
Controlplane VM              Worker VM                     NFS LXC
┌──────────────┐         ┌───────────────────┐         ┌──────────┐
│              │         │                   │         │          │
│  k8s-0       │  VLAN4  │  k8s-1            │  VLAN5  │  media   │
│  CP only     │─────────│  Cilium + pods    │─────────│  NFS     │
│              │         │                   │         │          │
│  eth4 ───────┼──10.10.4.10  eth4 ─────────┼────10.10.5.20      │
│              │         │  eth5 ────────────┼─10.10.5.11         │
│              │         │  eth6 ── internet │         │          │
│              │         │                   │         │          │
└──────────────┘         └───────────────────┘         └──────────┘
```

## Storage

| Type | Location | Use |
|---|---|---|
| `local-path` (default) | NVMe on worker | Databases, configs, PVC defaults |
| Direct NFS mount | `nfs.1337.pet:/export/hdd/media` | Media (qbittorrent, qui) |
| Direct NFS mount | `nfs.1337.pet:/export/hdd/s3/eu-vno-1` | SeaweedFS S3 gateway |



## Directory structure

```
kubernetes/
  apps/           # applications (per namespace)
  components/     # reusable kustomize components
  flux/           # flux system configuration
talos/            # Talos machine configs and schematic
bootstrap/        # bootstrap manifests and helmfile
```
