set shell := ['bash', '-euo', 'pipefail', '-c']

# Talos
talos schematic-id:
    @echo "Schematic: 434f313f73662fa228468d2f78510cdf5034ee6c93478230089cf27f5e79509e"
    @echo "ISO: https://factory.talos.dev/image/434f313f73662fa228468d2f78510cdf5034ee6c93478230089cf27f5e79509e/v1.13.7/metal-amd64.iso"

generate-secrets:
    talosctl gen secrets -o talos/secrets.yaml

render-node node:
    minijinja-cli talos/machineconfig.yaml.j2 talos/secrets.yaml talos/nodes/{{node}}.yaml > /tmp/talos-{{node}}.yaml
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
sops-secret:
    #!/usr/bin/env bash
    set -euo pipefail

    if [[ ! -f age.key ]]; then
        echo "age.key not found. Generate it with: age-keygen -o age.key"
        exit 1
    fi

    kubectl create namespace flux-system --dry-run=client -o yaml | kubectl apply -f -
    kubectl -n flux-system create secret generic sops-age \
      --from-file=age.agekey=age.key \
      --dry-run=client -o yaml | kubectl apply -f -

    echo "sops-age secret created successfully"
