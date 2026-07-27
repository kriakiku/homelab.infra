set shell := ['bash', '-euo', 'pipefail', '-c']

# Talos
talos schematic-id:
    @echo "Schematic: 68b868b0866549765b2931e7694ca760b8a4bc0200dde6d35c8952dfd7bf02cb"
    @echo ""
    @echo "ISO: https://factory.talos.dev/image/68b868b0866549765b2931e7694ca760b8a4bc0200dde6d35c8952dfd7bf02cb/v1.13.7/metal-amd64.iso"
    @echo ""
    @echo "Extensions: amd-ucode, amdgpu, kata-containers"

apply-node node:
    talosctl apply-config \
        -n {{node}} \
        -f <(minijinja-cli talos/machineconfig.yaml.j2 talos/nodes/{{node}}.yaml.j2)

# Bootstrap
bootstrap cluster:
    kubectl create namespace external-secrets --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -k bootstrap/kustomize/personal/external-secrets/
    kubectl apply -k kubernetes/flux/cluster/
