set shell := ['bash', '-euo', 'pipefail', '-c']

# Talos
talos schematic-id:
    @echo "Schematic: a79a889f330123eda622fc93eaccb82f13f2c9b688df34422c82310a67cc5bd7"
    @echo ""
    @echo "ISO: https://factory.talos.dev/image/a79a889f330123eda622fc93eaccb82f13f2c9b688df34422c82310a67cc5bd7/v1.13.7/metal-amd64.iso"
    @echo ""
    @echo "Extensions: amd-ucode, amdgpu, kata-containers"

generate-configs:
    talosctl gen secrets -o talos/secrets.yaml
    talosctl gen config homelab https://k8s.1337.pet \
        --with-secrets talos/secrets.yaml \
        --config-patch @talos/patch.yaml \
        --output talos/generated/
    mv talos/generated/controlplane.yaml talos/generated/k8s-0.yaml
    mv talos/generated/worker.yaml talos/generated/k8s-1.yaml

apply-node node ip:
    talosctl apply-config --insecure -n {{ip}} -f talos/generated/{{node}}.yaml
    talosctl apply-config --insecure -n {{ip}} -f talos/watchdog.yaml
    talosctl apply-config --insecure -n {{ip}} -f talos/nodes/{{node}}-hostname.yaml

# Bootstrap
bootstrap cluster:
    kubectl create namespace external-secrets --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -k bootstrap/kustomize/personal/external-secrets/
    kubectl apply -k kubernetes/flux/cluster/
