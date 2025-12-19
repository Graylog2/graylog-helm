# Setting up a MicroK8s cluster

This Helm chart should ideally work on any Kubernetes cluster.
For local development and iterative testing, we recommend using MicroK8s.
This setup enables a rapid development workflow without the need to manage complex infrastructure.

### Back up your existing Kubernetes configuration

```bash
[ -d $HOME/.kube ] && mv $HOME/.kube $HOME/.kube.old
```

## Install MicroK8s

```bash
microk8s install --cpu 8 --mem 24 --disk 200 --channel latest/stable
```
### Configure access to your new MicroK8s Kubernetes cluster

```bash
mkdir $HOME/.kube && microk8s config -o yaml > $HOME/.kube/config
chmod 400 $HOME/.kube/config
```

## Enable [DNS](https://microk8s.io/docs/addon-dns) and [local storage](https://microk8s.io/docs/addon-hostpath-storage) addons

```bash
microk8s enable dns
microk8s enable hostpath-storage
```

## Enable MetalLB

You will need a valid IP address range on your network that MetalLB can use for LoadBalancer services.

### Getting your CIDR

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

### Enable MetalLB addon

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