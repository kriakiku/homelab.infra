set shell := ['bash', '-euo', 'pipefail', '-c']

# Talos
talos schematic-id:
    @echo "Schematic: a79a889f330123eda622fc93eaccb82f13f2c9b688df34422c82310a67cc5bd7"
    @echo ""
    @echo "ISO: https://factory.talos.dev/image/a79a889f330123eda622fc93eaccb82f13f2c9b688df34422c82310a67cc5bd7/v1.13.7/metal-amd64.iso"
    @echo ""
    @echo "Extensions: amd-ucode, amdgpu, kata-containers"

apply-node node:
    talosctl apply-config \
        -n {{node}} \
        -f <(cat talos/machineconfig.yaml talos/nodes/{{node}}.yaml)

# Bootstrap
bootstrap cluster:
    kubectl create namespace external-secrets --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -k bootstrap/kustomize/personal/external-secrets/
    kubectl apply -k kubernetes/flux/cluster/
