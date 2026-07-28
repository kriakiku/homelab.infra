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
    kubectl create namespace external-secrets --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -k bootstrap/kustomize/personal/external-secrets/
    kubectl apply -k kubernetes/flux/cluster/

# Create Vaultwarden bootstrap secret
vaultwarden-secret client_secret:
    #!/usr/bin/env bash
    set -euo pipefail
    
    VAULTWARDEN_TOKEN=$(curl -sX POST https://vault.1337.pet/identity/connect/token \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -d "grant_type=client_credentials&scope=api&device_type=14&device_identifier=homelab-kubernetes&device_name=Kubernetes&client_id=user.8fc3a70e-ffaa-4afc-891f-c01ebfc9e43c&client_secret={{client_secret}}" \
      | jq -r '.access_token')
    
    if [[ -z "$VAULTWARDEN_TOKEN" || "$VAULTWARDEN_TOKEN" == "null" ]]; then
        echo "Failed to get Vaultwarden token"
        exit 1
    fi
    
    kubectl create ns external-secrets --dry-run=client -o yaml | kubectl apply -f -
    kubectl -n external-secrets create secret generic vaultwarden-secret \
      --from-literal=token="$VAULTWARDEN_TOKEN" \
      --from-literal=client_id=user.8fc3a70e-ffaa-4afc-891f-c01ebfc9e43c \
      --from-literal=client_secret={{client_secret}} \
      --from-literal=organization_id=76cb6e80-15c7-4fb8-8a11-e7489a28c045
    
    echo "Vaultwarden secret created successfully"
