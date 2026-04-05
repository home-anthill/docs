# Hetzner cloud with Kubernetes

Based on https://docs.k3s.io/quick-start


## Create an SSH key

`ssh-keygen -t ed25519` then choose a name like `hetzner_id_ed25519` and insert a secure password.
You'll get two files: `hetzner_id_ed25519` and `hetzner_id_ed25519.pub`.
Move them in `~/.ssh`.


## Server creation

### Environment

- Ubuntu 24.04 LTS
- Kubernetes v1.35.1+k3s1
- [gateway-api 1.5.1](https://github.com/kubernetes-sigs/gateway-api)
- [Flannel 0.28.1](https://github.com/flannel-io/flannel)
- [MetalLB 0.15.3](https://metallb.universe.tf/)
- [cert-manager 1.20.0](https://cert-manager.io/docs/installation/)
- [rabbitmq/cluster-operator 'latest'](https://github.com/rabbitmq/cluster-operator)
- [rabbitmq/messaging-topology-operator 'latest'](https://github.com/rabbitmq/messaging-topology-operator)


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


## SSH access

Login to your server with

```bash
ssh -i ~/.ssh/<private_key_file> root@<HETZNER_SERVER_PUBLIC_IP>
```
Insert the password used when you created your SSH key.

Please note that if you are using IPV6 as `HETZNER_SERVER_PUBLIC_IP`, it must end with `::1`.


## Update Ubuntu

```bash
sudo apt-get update -y
sudo apt-get upgrade -y
```


## Disable Linux swap for Kubernetes

Check with `htop` if swap is disabled. If not, run:

```bash
# disable swap right now
# and disable swap also when you'll reboot
sudo swapoff -a
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
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.35.1+k3s1" sh -
# Check for Ready node, takes ~30 seconds 
k3s kubectl get node
```

Save the content of `/root/.kube/config` to your local machine as `~/.kube/config` file.
Replace `127.0.0.1` in `~/.kube/config` with the public IPv4 of your Hetzner server.
Change permission with `chmod 600 ~/.kube/config`.

Now, you should be able to connect to the cluster from your local machine via `kubectl` or a software like [k9s](https://k9scli.io/) via `k9s -n all`.


## Install Flannel CNI plugin

MetalLB reports some incompatibilities with different CNI plugins, so I chose Flannel, because it seems supported without issues.

```bash
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/v0.28.1/Documentation/kube-flannel.yml
```


## Install MetalLB

```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.15.3/config/manifests/metallb-native.yaml
```


## Install cert-manager

From your local machine run:

```bash
helm repo add jetstack https://charts.jetstack.io --force-update

helm repo update

helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.20.0 \
  --set crds.enabled=true \
  --set config.enableGatewayAPI=true
```

and wait until the install command completes.


## Install RabbitMQ

Install RabbitMQ operators:

```bash

kubectl apply -f "https://github.com/rabbitmq/cluster-operator/releases/latest/download/cluster-operator.yml"
kubectl apply -f https://github.com/rabbitmq/messaging-topology-operator/releases/latest/download/messaging-topology-operator-with-certmanager.yaml

```



## Install Gateway APIs and NGINX Gateway Fabric

1. Deploy Gateway API CRDs

Installs standard CRDs (Gateway, HTTPRoute, GRPCRoute, ...) and experimental ones (TCPRoute, TLSRoute, UDPRoute) to support MQTT (TCP) traffic.

```bash
kubectl apply --server-side=true -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/experimental-install.yaml

# wait for CRDs to be established
kubectl wait --for=condition=Established crd/httproutes.gateway.networking.k8s.io --timeout=60s
```

2. Install NGINX Gateway Fabric with experimental + SnippetsFilter features

Only when CRDs are ready run:

```bash
helm install ngf oci://ghcr.io/nginx/charts/nginx-gateway-fabric \
  --namespace nginx-gateway \
  --create-namespace \
  --set nginxGateway.gwAPIExperimentalFeatures.enable=true \
  --set nginxGateway.snippetsFilters.enable=true
```

Some observations:
- gwAPIExperimentalFeatures.enable=true — tells NGF to watch for TCPRoute and TLSRoute resources
- snippetsFilters.enable=true — activates the alpha SnippetsFilter CRD used for rate limiting



## Install Loki + Promtail + Grafana (OPTIONAL)

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```

Create file `loki-values.yaml` with this content:
```
loki:
  auth_enabled: false
  commonConfig:
    replication_factor: 1
  storage:
    type: filesystem
  schemaConfig:
    configs:
      - from: "2024-01-01"
        store: tsdb
        object_store: filesystem
        schema: v13
        index:
          prefix: index_
          period: 24h
  chunksCache:
    enabled: false
  resultsCache:
    enabled: false
deploymentMode: SingleBinary
singleBinary:
  replicas: 1
read:
  replicas: 0
write:
  replicas: 0
backend:
  replicas: 0
chunksCache:
  enabled: false
resultsCache:
  enabled: false
```

Then install Loki using `loki-values.yaml` file:
```bash
helm install loki grafana/loki \
    --namespace monitoring --create-namespace \
    -f loki-values.yaml
```

1. Install Promtail

```bash
helm install promtail grafana/promtail \
    --namespace monitoring \
    --set "config.clients[0].url=http://loki:3100/loki/api/v1/push"
```

2. Install Grafana

```bash
helm install grafana grafana/grafana \
    --namespace monitoring \
    --set adminPassword=changeme
```


### Reading Logs in Grafana

  1. Get Grafana URL

  ```bash
  kubectl port-forward --namespace monitoring svc/grafana 3000:80
  ```

  Then open http://localhost:3000 and login with admin / changeme.

  2. Add Loki as a Data Source

  1. Go to Connections → Data sources → Add data source
  2. Search and select Loki
  3. Set URL to: http://loki-gateway.monitoring.svc.cluster.local/
  4. Click Save & test — should show "Data source connected"



## Deploy application

### Production with SSL and domain names

First, you need to buy 2 public web domains, for example [HERE](https://www.godaddy.com/).
Then, you can update DNS records of your domains:

```
A @ <gui-floating-ip_IP_ADDRESS>
A www <gui-floating-ip_IP_ADDRESS>
```

```
A @ <mosquitto-floating-ip_IP_ADDRESS>
A www <mosquitto-floating-ip_IP_ADDRESS>
```

Wait some time and then check if the domains and IPs match with:
```bash
dig <YOUR_DOMAIN>
dig <YOUR_MQTT_DOMAIN>
```

**Warning: please don't proceed until your domain shows the correct IP in the `dig` command output.**

1. Define personal config in a private repository

Create a new private repository to store your secrets and private configurations, for instance `private-config`.

2. Create a custom values file in `private-config/custom-values.yaml` with a specific configuration like:

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
  oauth2AppClientID: "<GITHUB_OAUTH_APP_CLIENT>"
  oauth2AppSecretID: "<GITHUB_OAUTH_APP_SECRET>"
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

3. (optional step) If you want to see all manifests processed by Helm without deploying them, you can run:

```bash
cd deployer/home-anthill
helm template -f values.yaml -f ../../private-config/custom-values.yaml . > output-manifests.yaml
```

4. Deploy with Helm

```bash
cd deployer/home-anthill
helm install -f values.yaml -f ../../private-config/custom-values.yaml  home-anthill .
```

5. Check the Kubernetes services. You should see 2 Gateways (class `nginx`) and 2 LoadBalancers with the correct Floating IPs assigned as External-IPs.
   After some time, you will be able to navigate to the website via HTTPS and connect to the Mosquitto server via MQTTS.
   ESP32 devices should already be working using secure connections.
<br/>


## Useful things

If you want to force renew Let's Encrypt certificates in `cert-manager`, you can install `cmctl` via `brew install cmctl` on your local machine and run this:

```bash
cmctl renew webapp-tls -n home-anthill
cmctl renew mqtt-tls -n home-anthill
```