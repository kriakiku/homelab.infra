set shell := ['bash', '-euo', 'pipefail', '-c']

# Talos
talos schematic-id:
    @echo "Schematic: a79a889f330123eda622fc93eaccb82f13f2c9b688df34422c82310a67cc5bd7"
    @echo "ISO: https://factory.talos.dev/image/a79a889f330123eda622fc93eaccb82f13f2c9b688df34422c82310a67cc5bd7/v1.13.7/metal-amd64.iso"

generate-secrets:
    talosctl gen secrets -o talos/secrets.yaml

apply-node node ip:
    minijinja-cli talos/machineconfig.yaml.j2 talos/secrets.yaml talos/nodes/{{node}}.yaml > /tmp/talos-{{node}}.yaml
    cat talos/watchdog.yaml talos/nodes/{{node}}-hostname.yaml >> /tmp/talos-{{node}}.yaml
    talosctl apply-config --insecure --mode=reboot -n {{ip}} -e {{ip}} -f /tmp/talos-{{node}}.yaml

# Bootstrap
bootstrap cluster:
    kubectl create namespace external-secrets --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -k bootstrap/kustomize/personal/external-secrets/
    kubectl apply -k kubernetes/flux/cluster/
