set shell := ['bash', '-euo', 'pipefail', '-c']

# Talos
talos schematic-id:
    @echo "Schematic: 434f313f73662fa228468d2f78510cdf5034ee6c93478230089cf27f5e79509e"
    @echo "ISO: https://factory.talos.dev/image/434f313f73662fa228468d2f78510cdf5034ee6c93478230089cf27f5e79509e/v1.13.7/metal-amd64.iso"

generate-secrets:
    talosctl gen secrets -o /tmp/talos-secrets.yaml
    SOPS_AGE_KEY_FILE=age.key sops --encrypt /tmp/talos-secrets.yaml > talos/secrets.sops.yaml
    rm /tmp/talos-secrets.yaml

render-node node:
    SOPS_AGE_KEY_FILE=age.key sops --decrypt talos/secrets.sops.yaml > /tmp/talos-secrets.yaml
    minijinja-cli talos/machineconfig.yaml.j2 /tmp/talos-secrets.yaml talos/nodes/{{node}}.yaml > /tmp/talos-{{node}}.yaml
    rm /tmp/talos-secrets.yaml
    cat talos/nodes/{{node}}-hostname.yaml >> /tmp/talos-{{node}}.yaml
    @echo "Config written to /tmp/talos-{{node}}.yaml"

apply-node node ip:
    just render-node {{node}}
    talosctl apply-config --insecure --mode=reboot -n {{ip}} -e {{ip}} -f /tmp/talos-{{node}}.yaml

# Update running node (TLS already enabled)
update-node node ip:
    just render-node {{node}}
    talosctl --talosconfig talos/generated/talosconfig -n {{ip}} -e {{ip}} apply-config --mode=reboot -f /tmp/talos-{{node}}.yaml

# Bootstrap
bootstrap cluster:
    just sops-secret
    kubectl apply -k kubernetes/flux/cluster/

# Create the SOPS age decryption secret used by Flux (reads ./age.key)
# Flux resolves decryption.secretRef in each Kustomization's own namespace, so
# the sops-age secret is replicated into every app namespace.
sops-secret:
    #!/usr/bin/env bash
    set -euo pipefail

    if [[ ! -f age.key ]]; then
        echo "age.key not found. Generate it with: age-keygen -o age.key"
        exit 1
    fi

    namespaces=(
        actions-runner-system
        backup
        cert-manager
        databases
        default
        flux-system
        kopiur-system
        kube-system
        media
        network
        o11y
        storage
        system-upgrade
    )

    for ns in "${namespaces[@]}"; do
        kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
        kubectl -n "$ns" create secret generic sops-age \
          --from-file=age.agekey=age.key \
          --dry-run=client -o yaml | kubectl apply -f -
    done

    echo "sops-age secret created in all namespaces"
