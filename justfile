set shell := ['bash', '-euo', 'pipefail', '-c']

# Talos
talos schematic-id:
    @echo "Go to https://factory.talos.dev and configure extensions:"
    @cat talos/schematic.yaml.j2
    @echo ""
    @echo "Copy the Schematic ID from URL, then download ISO:"
    @echo "  https://factory.talos.dev/image/<SCHEMATIC_ID>/v1.14.0/metal-amd64.iso"

apply-node node:
    talosctl apply-config \
        -n {{node}} \
        -f <(minijinja-cli talos/machineconfig.yaml.j2 talos/nodes/{{node}}.yaml.j2)

# Bootstrap
bootstrap cluster:
    kubectl create namespace external-secrets --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -k bootstrap/kustomize/personal/external-secrets/
    kubectl apply -k kubernetes/flux/cluster/
