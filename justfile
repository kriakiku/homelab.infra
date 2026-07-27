set shell := ['bash', '-euo', 'pipefail', '-c']

# Talos
talos schematic-id:
    @echo "Schematic: a79a889f330123eda622fc93eaccb82f13f2c9b688df34422c82310a67cc5bd7"
    @echo ""
    @echo "ISO: https://factory.talos.dev/image/a79a889f330123eda622fc93eaccb82f13f2c9b688df34422c82310a67cc5bd7/v1.13.7/metal-amd64.iso"
    @echo ""
    @echo "Extensions: amd-ucode, amdgpu, kata-containers"

apply-node node ip:
    yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' talos/machineconfig.yaml talos/nodes/{{node}}-machine.yaml > /tmp/talos-{{node}}.yaml
    talosctl apply-config --insecure -n {{ip}} -f <(cat /tmp/talos-{{node}}.yaml talos/watchdog.yaml talos/nodes/{{node}}-hostname.yaml)

# Bootstrap
bootstrap cluster:
    kubectl create namespace external-secrets --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -k bootstrap/kustomize/personal/external-secrets/
    kubectl apply -k kubernetes/flux/cluster/
