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
| Secrets | SOPS + age (encrypted in Git, decrypted by Flux) |
| Storage | local-path-provisioner (NVMe) + direct NFS mounts (HDD) |
| Backups | Kopiur → expanse S3 | Restic → Google Drive |
| Monitoring | kube-prometheus-stack + Grafana + Gatus |
| Notifications | Gotify |
| DNS | Cloudflare (public) + UniFi (private) |
| CI | Self-hosted ARC runners on Kata Containers |

## Prerequisites

- Proxmox host with 2 VMs provisioned (1 controlplane, 1 worker)
- Talos CLI (`talosctl`), `just`, `sops` and `age` installed locally
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

### 4. Provide the SOPS age key

Place the age private key at `age.key` in the repo root (git-ignored). The
matching public key is configured in `.sops.yaml` and used to encrypt all
`kubernetes/**/*.sops.yaml` secret manifests.

To generate a fresh key (only for a brand-new setup — existing encrypted
secrets require the original key):

```bash
age-keygen -o age.key
```

The `just bootstrap` step below creates the `sops-age` Secret in the
`flux-system` namespace from this file so Flux can decrypt manifests.

### 5. Bootstrap cluster

```bash
just bootstrap cluster
```

This applies bootstrap manifests, syncs helmfile, and deploys Flux. Flux then reconciles all apps from `kubernetes/apps/`.

## Secrets

Secrets are stored as SOPS-encrypted Kubernetes `Secret` manifests
(`kubernetes/**/*.sops.yaml`) committed directly to Git. Only the `data`/
`stringData` values are encrypted with [age](https://github.com/FiloSottile/age);
metadata and keys stay in plaintext for readability and diffs.

- Encryption rules live in `.sops.yaml` (age recipient public key).
- The age private key is stored at `age.key` (git-ignored) and injected into
  the cluster as the `sops-age` Secret in `flux-system`.
- Flux's `kustomize-controller` decrypts them at apply time
  (`spec.decryption.provider: sops` on the root Kustomization).

Edit a secret with:

```bash
export SOPS_AGE_KEY_FILE=$PWD/age.key
sops kubernetes/apps/<ns>/<app>/app/secret.sops.yaml
```

Secrets currently managed (by app): cloudflare (dns/tunnel/issuer), unifi-dns,
grafana admin, gatus/alertmanager (buddy + gotify), qui, smtp-relay, pocket-id,
qbittorrent (wireguard), flux webhook + GitHub token, GitHub App (ARC runners),
konflate, seaweedfs S3, restic, and kopiur repository credentials.

## Network architecture

| VLAN | Subnet | Purpose |
|---|---|---|
| VLAN 3 | `10.10.3.0/24` | IoT |
| VLAN 4 | `10.10.4.0/24` | Infrastructure — nodes, BGP, LB IP pool (10.10.4.224/27) |
| VLAN 5 | `10.10.5.0/24` | Storage — NFS, isolated by CiliumNetworkPolicy |
| VLAN 6 | `10.10.6.0/24` | Egress — internet access, client isolation |
| VLAN 7 | `10.10.7.0/24` | VPN |
| — | `10.10.98.0/23` | Pod CIDR (internal to Cilium) |
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
