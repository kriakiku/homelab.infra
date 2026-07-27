set shell := ['bash', '-euo', 'pipefail', '-c']

# Talos
talos schematic-id:
    @echo "Schematic: a79a889f330123eda622fc93eaccb82f13f2c9b688df34422c82310a67cc5bd7"
    @echo "ISO: https://factory.talos.dev/image/a79a889f330123eda622fc93eaccb82f13f2c9b688df34422c82310a67cc5bd7/v1.13.7/metal-amd64.iso"

generate-secrets:
    talosctl gen secrets -o talos/secrets.yaml

generate-configs:
    mkdir -p talos/generated
    talosctl gen config homelab https://k8s.1337.pet:6443 \
        --with-secrets talos/secrets.yaml \
        --config-patch @talos/machineconfig.yaml \
        --config-patch @talos/nodes/k8s-0-machine.yaml \
        --output talos/generated/k8s-0
    mv talos/generated/k8s-0/controlplane.yaml talos/generated/k8s-0/full.yaml
    rm -rf talos/generated/k8s-0/worker.yaml talos/generated/k8s-0/kubeconfig
    talosctl gen config homelab https://k8s.1337.pet:6443 \
        --with-secrets talos/secrets.yaml \
        --config-patch @talos/machineconfig.yaml \
        --config-patch @talos/nodes/k8s-1-machine.yaml \
        --output talos/generated/k8s-1
    mv talos/generated/k8s-1/worker.yaml talos/generated/k8s-1/full.yaml
    rm -rf talos/generated/k8s-1/controlplane.yaml talos/generated/k8s-1/kubeconfig
    mkdir -p ~/.talos
    cp talos/generated/k8s-0/talosconfig ~/.talos/config

apply-node node ip:
    talosctl apply-config --insecure --mode=reboot -n {{ip}} -e {{ip}} \
        -f talos/generated/{{node}}/full.yaml \
        -f talos/watchdog.yaml \
        -f talos/nodes/{{node}}-hostname.yaml

# Bootstrap
bootstrap cluster:
    kubectl create namespace external-secrets --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -k bootstrap/kustomize/personal/external-secrets/
    kubectl apply -k kubernetes/flux/cluster/
