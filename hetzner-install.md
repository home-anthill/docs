# Heztner cloud with Kubernetes

Based on https://docs.k3s.io/quick-start


## Create an SSH key

`ssh-keygen -t ed25519` then choose a name like `hetzner_id_ed25519` and insert a secure password.
You'll get two files: `hetzner_id_ed25519` and `hetzner_id_ed25519.pub`.
Move them in `~/.ssh`.


## Environment

- Ubuntu 24.04 LTS
- Kubernetes v1.29.6+k3s1
- [Flannel 0.25.5](https://github.com/flannel-io/flannel)
- [MetalLB 0.14.18](https://metallb.universe.tf/)
- [ingress-nginx 1.10.1](https://kubernetes.github.io/ingress-nginx/)
- [cert-manager 1.15.1](https://cert-manager.io/)


## Server creation

From Hetzner Cloud UI create a server like this:

- Location: Falkenstein
- Image: Ubuntu 24.04
- Type: Shared vCPU - x86 Intel - CX22 - 2 vCPU - 4 GB RAM - 40 GB disk
- Networking: Public IPv4 (optionally, also Public IPv6)
- SSH Keys: Add your SSH Public key created before
- Volume: none
- Firewalls: none
- Backups: None
- Placement groups: None
- Labels: None
- Cloud config: none
- Name: what you like


## Create Floating IPs

**Floating IPs are required to have static public IPs to expose public Kubernetes services**

From Hetzner Cloud UI create 2 IPs:

- name: gui-floating-ip
  location: Falkenstein
  protocol: IPV4
- name: mosquitto-floating-ip
  location: Falkenstein
  protocol: IPV4

From "Assigned to" column you need to choose the server created above.


## SSH access

Login to your server with

```bash
ssh -i ~/.ssh/<private_key_file> root@<HETZNER_SERVER_PUBLIC_IP>
```
Insert the password used when you created your SSH key.


## Update Ubuntu

```bash
sudo apt-get update -y
sudo apt-get upgrade -y
```


## Disable Linux swap for Kubernetes

Check with `htop` if swap is disabled. If not, run:

```bash
# disable swap right now
sudo swapoff -a
# disable swap also when you'll reboot
cp /etc/fstab /etc/fstab.backup
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

sudo reboot
```


## Prepare K3s

As described [HERE](https://docs.k3s.io/installation/configuration#configuration-file), K3s reads a config file on install located at `/etc/rancher/k3s/config.yaml`.

```bash
sudo mkdir -p /etc/rancher/k3s
sudo mkdir -p /root/.kube
sudo touch /etc/rancher/k3s/config.yaml
```

Add this content to `/etc/rancher/k3s/config.yaml`:

```yaml
disable:
  - traefik
  - servicelb
write-kubeconfig-mode: "0644"
write-kubeconfig: "/root/.kube/config"
cluster-cidr: "10.244.0.0/16"
```

**Attention, this is very important:**
`cluster-cidr: "10.244.0.0/16"` is required to prevent error `Error registering network: failed to acquire lease: subnet 10.244.0.0/16 specified in the flannel net config doesnt contain 10.42.0.0/24 PodCIDR...` when starting `kube-flannel-ds` pod.


## Install K3s

Install K3s via: 

```bash
curl -sfL https://get.k3s.io | sh - 
# Check for Ready node, takes ~30 seconds 
k3s kubectl get node 
```

Save the content of `/root/.kube/config` to you local machine as `~/.kube/config` file.
Replace `127.0.0.1` in `~/.kube/config` with the public IPv4 of your Hetzner server.
Change permission with `chmod 600 ~/.kube/config`.

Now, you should be able to connect to the cluster from your local machine, for example via `kubectl` or a software like [k9s](https://k9scli.io/).


## Install Flannel CNI plugin

MetalLB reports some incompatibilities with different CNI plugins, so I chose Flannel, because it seems supported without issues.

```bash
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/v0.25.5/Documentation/kube-flannel.yml
```


## Install MetalLB

```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.8/config/manifests/metallb-native.yaml
```


## Install cert-manager

```bash
helm repo add jetstack https://charts.jetstack.io --force-update

helm install \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.15.1 \
  --set crds.enabled=true

helm repo update
```


## Apply firewall rules to Hetzner Cloud

Choose "Firewall" from the sidebar of your Hetzner project and configure these rules:
```yaml
Inbound:
  - Name: SSH
    Sources: Any IPv4, Any IPv6
    Protocol: TCP
    Port: 22
  - Name: ICMP
    Sources: Any IPv4, Any IPv6
    Protocol: ICMP
  - Name: HTTP
    Sources: Any IPv4, Any IPv6
    Protocol: TCP
    Port: 80
  - Name: HTTPS
    Sources: Any IPv4, Any IPv6
    Protocol: TCP
    Port: 443
  - Name: MQTT
    Sources: Any IPv4, Any IPv6
    Protocol: TCP
    Port: 1883
  - Name: MQTTS
    Sources: Any IPv4, Any IPv6
    Protocol: TCP
    Port: 8883
  - Name: KUBE
    Sources: Any IPv4, Any IPv6
    Protocol: TCP
    Port: 6443
Outbound: # leave empty to allow all outgoing traffic
```

Then apply this configuration to your server.


## Deploy application

### Production with SSL and domain names

First, you need to buy 2 public web domains, for example [HERE](https://www.godaddy.com/).
Then, you can update DNS records of your domains:

```
A @ <gui-floating-ip_IP_ADDRESS>
A wwww <gui-floating-ip_IP_ADDRESS>
```

```
A @ <mosquitto-floating-ip_IP_ADDRESS>
A wwww <mosquitto-floating-ip_IP_ADDRESS>
```

Wait some time and then check if domains and IPs are matching with:
```bash
dig <YOUR_DOMAIN>
dig <YOUR_MQTT_DOMAIN>
```

**Warning: please, don't procedeed until your domain shows the right IP in `dig` command output**


1. Deploy ingress-controllers

Run the 2 commands below replacing loadBalancerIPs with floating IPs.

```bash
# webapp ingress controller
helm install http-ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.service.loadBalancerIP=<gui-floating-ip_IP_ADDRESS> \
  --set controller.readOnlyRootFilesystem=true \
  --set controller.ingressClass=http-nginx \
  --set controller.ingressClassResource.name=http-nginx \
  --set controller.ingressClassResource.enabled=true \
  --set controller.ingressClassResource.default=false \
  --set controller.ingressClassResource.controllerValue="k8s.io/http-ingress-nginx"

# mqtt ingress controller (with custom config to expose TCP traffic as explained here: https://github.com/kubernetes/ingress-nginx/blob/main/docs/user-guide/exposing-tcp-udp-services.md)
helm install mqtt-ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.service.loadBalancerIP=<mosquitto-floating-ip_IP_ADDRESS> \
  --set controller.readOnlyRootFilesystem=true \
  --set tcp.8883=home-anthill/mosquitto-svc:8883,tcp.1883=home-anthill/mosquitto-svc:1883 \
  --set controller.ingressClass=mqtt-nginx \
  --set controller.ingressClassResource.name=mqtt-nginx \
  --set controller.ingressClassResource.enabled=true \
  --set controller.ingressClassResource.default=false \
  --set controller.ingressClassResource.controllerValue="k8s.io/mqtt-ingress-nginx"
```


2. Define personal config in a private repository

Create a new private repository to store your secrets and private configurations, for instance `private-config`

3. Create a custom values file in `private-config/custom-values.yaml` with a specific configuration like:

```yaml
domains:
  http: 
    name: "YOUR_DOMAIN"
    publicIp: "<gui-floating-ip_IP_ADDRESS>"
    ssl:
      enable: true
  mqtt: 
    name: "YOUR_MQTT_DOMAIN"
    publicIp: "<mosquitto-floating-ip_IP_ADDRESS>"
    ssl:
      enable: true

letsencrypt:
  email: "YOUR_EMAIL_ADDRESS_FOR_LETSENCRYPT"

mosquitto:
  auth:
    enable: true
    username: "<CHOOSE_MOSQUITTO_USERNAME>"
    password: "<CHOOSE_MOSQUITTO_PASSWORD>"

apiServer:
  oauth2ClientID: "<GITHUB_OAUTH_CLIENT>"
  oauth2SecretID: "<GITHUB_OAUTH_SECRET>"
  singleUserLoginEmail: "<GITHUB_ACCOUNT_EMAIL_TO_LOGIN>"
  jwtPassword: "<JWT_PASSWORD>"
  cookieSecret: "<COOKIE_SECRET>"

mongodbUrl: "mongodb+srv://<MONGODB_ATLAS_USERNAME>:<MONGODB_ATLAS_PASSWORD>@cluster0.4wies.mongodb.net"

# debug configuration, not for production environment
debug:
  pods:
    alwaysPullContainers: false
    # if your pods are crashing, you can enable this to prevent restarts
    # and to access them using your terminal.
    # Don't enable this on a production environment!!!
    sleepInfinity: false
```

4. (optional step) If you want to see all manifests processed by Helm without deploying them, you can run:

```bash
cd deployer/home-anthill
helm template -f values.yaml -f ../../private-config/custom-values.yaml . > output-manifests.yaml
```

5. Deploy with Helm

```bash
cd deployer/home-anthill
helm install -f values.yaml -f ../../private-config/custom-values.yaml  home-anthill .
```

6. Check kubernetes services! You should see 2 Ingresses and 2 LoadBalancers with the right Floating IPs assigned as External-IPs.
   After some time, you'll be able to navigate to the website via HTTPS and to the Mosquitto server via MQTTS connection.
   ESP32 device should already be working using secure connections.
<br/>