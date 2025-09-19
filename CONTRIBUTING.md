## Git Workflow Guidelines

- Do **not** commit directly to `main`. Always use a feature branch:
```sh
git checkout -b feat/my-feature
```
- Before opening a PR, **rebase or squash** your commits to keep history clean:
```sh
git rebase origin/main
```
- Use clear and concise commit messages. We recommend following [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/):
```sh
git commit -m "docs: add CONTRIBUTING.md"
```
- Ensure your branch is up to date with `main` before creating a PR:
```sh
git fetch origin
git rebase origin/main
```
- All PRs must be reviewed by at least one maintainer before merging.

# Testing

- [Setting up a MicroK8s cluster](#setting-up-a-microk8s-cluster)
- [Validating chart](#validating-chart)
- [Installing Graylog](#installing-chart)
- [Upgrading chart](#upgrading-chart)

## Setting up a MicroK8s cluster

This Helm chart should ideally work on any Kubernetes cluster.
For local development and iterative testing, we recommend using MicroK8s.
This setup enables a rapid development workflow without the need to manage complex infrastructure.

#### Back up your existing Kubernetes configuration

```bash
[ -d $HOME/.kube ] && mv $HOME/.kube $HOME/.kube.old
```

### Install MicroK8s

```bash
microk8s install --cpu 8 --mem 24 --disk 200 --channel latest/stable
```
#### Configure access to your new MicroK8s Kubernetes cluster

```bash
mkdir $HOME/.kube && microk8s config -o yaml > $HOME/.kube/config
chmod 400 $HOME/.kube/config
```

### Enable [DNS](https://microk8s.io/docs/addon-dns) and [local storage](https://microk8s.io/docs/addon-hostpath-storage) addons

```bash
microk8s enable dns
microk8s enable hostpath-storage
```

### Enable MetalLB

You will need a valid IP address range on your network that MetalLB can use for LoadBalancer services.

#### Getting your CIDR

Depending on your OS, you might be running MicroK8s directly on Linux or inside a virtual machine on macOS.
Below are example commands for each setup:


  <details>
    <summary>Get CIDR on Linux using the <code>eth0</code> interface</summary>
    <pre><code>CIDR=$(ip -4 -o addr show scope global | grep 'eth0' | awk '{print $4}' | sed 's|[0-9]\+/|0/|')</code></pre>
  </details>
  
  <details>
    <summary>Get CIDR on macOS using the MicroK8s VM address</summary>
    <pre><code>CIDR=$(multipass info microk8s-vm --format json | jq -r '.info["microk8s-vm"].ipv4[0] + "/32"')</code></pre>
  </details>

You can verify that the CIDR was captured correctly with:

```bash
echo $CIDR
```

#### Enable MetalLB addon

Once you have your CIDR, you can enable metallb

```bash
microk8s enable metallb:$CIDR
```

> [!IMPORTANT]
> If you are running **MicroK8s on macOS**, you will need to increase the memory map areas per VM process

```bash
# only if running microk8s on macOS
multipass exec microk8s-vm -- sudo sysctl -w vm.max_map_count=262144
```

### Validating chart

```bash
# check template rendering
helm template graylog . --debug | less

# do a dry run with a small configuration
helm install graylog . --dry-run --debug --create-namespace -n graylog --set size="xs"

# do a dry run with the default configuration
helm install graylog . --dry-run --debug --create-namespace -n graylog

```

### Installing chart

```bash
helm install graylog . -n graylog --create-namespace -n graylog --set size="xs" --set graylog.service.type="LoadBalancer"
```

### Upgrading chart

> [!NOTE]
> Values can be passed into the chart from multiple sources, including
> - The `values.yaml` file in the chart, with all default values
> - A values file passed with the `--values` or `-f` flag (e.g. `helm upgrade graylog . -f mynewvals.yaml`)
> - Individual parameters passed with `--set` (e.g. `helm upgrade graylog . --set foo=bar`)
> 
> The default values in `values.yaml` can be overridden by a parent chart's `values.yaml` (in the event this chart is used as a subchart), which can in turn be overridden by a user-supplied values file with `-f`, which can in turn be overridden by `--set` parameters.

> [!NOTE]
> The `reset-values` and `reuse-values` flags can be used to control how values are handled during an upgrade:
> - `--reset-values`: Discards the previously set values and uses only the values provided in the current upgrade command (via `--values` or `--set`).
> - `--reuse-values`: Reuses the values from the last release and merges them with any new values provided in the upgrade command.
> 
> These two flags are mutually exclusive.
> 
> In addition, if no `-f` (or `--values`), or `--set` (or `--set-string`, or `--set-file`) flags are applied,
> `--reuse-values` will be used by default. Otherwise, `--reset-values` will be used by default.
```bash
# keeps previously set values and overrides current "version"
helm upgrade graylog . -n graylog --reuse-values --set version="6.3"
```