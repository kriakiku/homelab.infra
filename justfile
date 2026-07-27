# Talos
talos schematic-id:
    talosctl image schematic --config talos/schematic.yaml.j2

apply-node node:
    talosctl apply-config \
        -n {{node}} \
        -f <(talosctl machineconfig template \
            -f talos/machineconfig.yaml.j2 \
            -f talos/nodes/{{node}}.yaml.j2)

# Bootstrap
bootstrap cluster:
    kubectl create namespace external-secrets --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -k bootstrap/kustomize/personal/external-secrets/
    kubectl apply -k kubernetes/flux/cluster/
