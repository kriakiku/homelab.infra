set shell := ['bash', '-euo', 'pipefail', '-c']

# Talos
talos schematic-id:
    @echo "Schematic: a79a889f330123eda622fc93eaccb82f13f2c9b688df34422c82310a67cc5bd7"
    @echo "ISO: https://factory.talos.dev/image/a79a889f330123eda622fc93eaccb82f13f2c9b688df34422c82310a67cc5bd7/v1.13.7/metal-amd64.iso"

generate-secrets:
    talosctl gen secrets -o talos/secrets.yaml
    talosctl gen config homelab https://k8s.1337.pet:6443 \
        --with-secrets talos/secrets.yaml \
        --output talos/generated/
    mkdir -p ~/.talos
    cp talos/generated/talosconfig ~/.talos/config

apply-node node ip:
    talosctl apply-config --insecure -n {{ip}} \
        -f talos/machineconfig.yaml \
        -f talos/nodes/{{node}}-machine.yaml \
        -f talos/secrets.yaml \
        -f talos/watchdog.yaml \
        -f talos/nodes/{{node}}-hostname.yaml

# Bootstrap
bootstrap cluster:
    kubectl create namespace external-secrets --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -k bootstrap/kustomize/personal/external-secrets/
    kubectl apply -k kubernetes/flux/cluster/
