# Hetzner Cloud with Kubernetes

Based on https://docs.k3s.io/quick-start


## Create an SSH Key

Run `ssh-keygen -t ed25519`, then choose a name such as `hetzner_id_ed25519` and set a strong passphrase.
You will get two files: `hetzner_id_ed25519` and `hetzner_id_ed25519.pub`.
Move them to `~/.ssh`.


## Server creation

### Environment

- Ubuntu 24.04 LTS
- Kubernetes v1.35.3+k3s1
- [gateway-api 1.5.1](https://github.com/kubernetes-sigs/gateway-api)
- [Cilium 'latest stable'](https://github.com/cilium/cilium) — CNI, NetworkPolicy enforcement, kube-proxy replacement, and L2 LoadBalancer IP announcements (replaces MetalLB)
- [rabbitmq/cluster-operator 'latest stable'](https://github.com/rabbitmq/cluster-operator)
- [rabbitmq/messaging-topology-operator 'latest stable'](https://github.com/rabbitmq/messaging-topology-operator)


From the Hetzner Cloud UI, create a server with these settings:

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

**Floating IPs are required to expose Kubernetes services through static public IPs.**

From Hetzner Cloud UI create 2 IPs:

- name: gui-floating-ip
  location: Falkenstein
  protocol: IPV4
- name: mosquitto-floating-ip
  location: Falkenstein
  protocol: IPV4

In the "Assigned to" column, select the server you created above.


## Apply Firewall Rules to Hetzner Cloud

Open "Firewall" in the sidebar of your Hetzner project and configure these rules:
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


## SSH Access

Log in to your server with:

```bash
ssh -i ~/.ssh/<private_key_file> root@<HETZNER_SERVER_PUBLIC_IP>
```
Enter the passphrase you used when you created the SSH key.

If you use IPv6 as `HETZNER_SERVER_PUBLIC_IP`, it must end with `::1`.


## Update Ubuntu

```bash
sudo apt-get update -y
sudo apt-get upgrade -y
```


## Disable Linux Swap for Kubernetes

Check with `htop` whether swap is disabled. If not, run:

```bash
# Disable swap immediately
# and disable it again after reboot
sudo swapoff -a
cp /etc/fstab /etc/fstab.backup
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

sudo reboot
```


## Prepare K3s

As described [here](https://docs.k3s.io/installation/configuration#configuration-file), K3s reads its install-time config from `/etc/rancher/k3s/config.yaml`.

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
flannel-backend: "none"
disable-network-policy: true
disable-kube-proxy: true
```

**Attention, this is very important:**
`cluster-cidr: "10.244.0.0/16"` must match the CIDR Cilium will use, set via `ipam.mode=kubernetes`.
`flannel-backend: "none"` and `disable-network-policy: true` disable K3s's built-in Flannel and
its network policy controller so that Cilium can take over both responsibilities.
`disable-kube-proxy: true` disables K3s's embedded kube-proxy, which is required when Cilium runs with
`kubeProxyReplacement=true` because Cilium handles service routing via eBPF.


## Install K3s

Install K3s with:

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.35.3+k3s1" sh -
# It should be `NotReady`, because Cilium is installed in the next step
k3s kubectl get node
```

> **Note:** The node will remain `NotReady` until Cilium is installed in the next step. This is expected.

Save the content of `/root/.kube/config` to your local machine as `~/.kube/config`.
Replace `127.0.0.1` in `~/.kube/config` with the public IPv4 of your Hetzner server.
Change permission with `chmod 600 ~/.kube/config`.

You should now be able to connect to the cluster from your local machine via `kubectl` or a tool like [k9s](https://k9scli.io/) with `k9s -n all`.

## Verify Local Storage

k3s usually ships with the `local-path` storage provisioner enabled by default. That is the simplest way to replace the chart's `hostPath` volumes on a single remote server.

Check that the storage class exists:

```bash
kubectl get storageclass
```

You should see `local-path`. If it is not present, install the k3s local-path provisioner before deploying the chart. For this setup, the Helm chart uses `local-path` for Redis and Mosquitto persistent volumes.


## Install Cilium CNI

Cilium replaces Flannel as the CNI. It provides pod networking, `NetworkPolicy` enforcement,
kube-proxy replacement via eBPF, **and L2 LoadBalancer IP announcements**, replacing MetalLB
entirely. Because Cilium owns both the eBPF datapath and the IP announcement, in-cluster pods
can reach LoadBalancer IPs without hairpin NAT issues, which fixes cert-manager ACME self-checks.

Install the Cilium CLI on the server, then deploy Cilium before installing any other components:

```bash
# Install Cilium CLI
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
curl -Lo /tmp/cilium.tar.gz \
  https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-amd64.tar.gz
sudo tar xzvfC /tmp/cilium.tar.gz /usr/local/bin
rm /tmp/cilium.tar.gz

# Deploy Cilium with:
#   kubeProxyReplacement=true  - Cilium handles all service routing via eBPF (no kube-proxy)
#   l2announcements.enabled    - Cilium announces LoadBalancer IPs via ARP (replaces MetalLB)
#   externalIPs.enabled        - required for L2 announcements to work
cilium install \
  --set ipam.mode=kubernetes \
  --set operator.replicas=1 \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=127.0.0.1 \
  --set k8sServicePort=6443 \
  --set l2announcements.enabled=true \
  --set externalIPs.enabled=true

# Wait until all Cilium components are running (~60-90 seconds)
cilium status --wait

# Node should now be Ready
kubectl get nodes
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

and wait for the installation to complete.


## Install RabbitMQ

Install the RabbitMQ operators:

```bash

kubectl apply -f "https://github.com/rabbitmq/cluster-operator/releases/latest/download/cluster-operator.yml"
kubectl apply -f https://github.com/rabbitmq/messaging-topology-operator/releases/latest/download/messaging-topology-operator-with-certmanager.yaml

```



## Install Gateway APIs and NGINX Gateway Fabric

1. Deploy Gateway API CRDs

This installs the standard CRDs (Gateway, HTTPRoute, GRPCRoute, ...) and the experimental ones (TCPRoute, TLSRoute, UDPRoute) needed for MQTT (TCP) traffic.

```bash
kubectl apply --server-side=true -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/experimental-install.yaml

# wait for CRDs to be established
kubectl wait --for=condition=Established crd/httproutes.gateway.networking.k8s.io --timeout=60s
```

2. Install NGINX Gateway Fabric with experimental + SnippetsFilter features

Run this only after the CRDs are ready:

```bash
helm install ngf oci://ghcr.io/nginx/charts/nginx-gateway-fabric \
  --namespace nginx-gateway \
  --create-namespace \
  --set nginxGateway.gwAPIExperimentalFeatures.enable=true \
  --set nginxGateway.snippetsFilters.enable=true
```

Some notes:
- `gwAPIExperimentalFeatures.enable=true` tells NGF to watch for `TCPRoute` and `TLSRoute` resources.
- `snippetsFilters.enable=true` activates the alpha `SnippetsFilter` CRD used for rate limiting.



## Install Loki + Promtail + Grafana (OPTIONAL)

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```

Create a file named `loki-values.yaml` with this content:
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

Then install Loki using the `loki-values.yaml` file:
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

  1. Get the Grafana URL

  ```bash
  kubectl port-forward --namespace monitoring svc/grafana 3000:80
  ```

  Then open http://localhost:3000 and log in with `admin` / `<password_from_previous_step>`.

  2. Add Loki as a Data Source
  3. Go to Connections → Data sources → Add data source
  4. Search and select Loki
  5. Set URL to: http://loki-gateway.monitoring.svc.cluster.local/
  6. Click Save & test — should show "Data source connected"
  7. Click on "Drilldown - Logs" from the side bar


## Deploy application

### Production with SSL and domain names

First, you need to buy two public web domains, for example [here](https://www.godaddy.com/).
Then update the DNS records for your domains:

```
A @ <gui-floating-ip_IP_ADDRESS>
A www <gui-floating-ip_IP_ADDRESS>
```

```
A @ <mosquitto-floating-ip_IP_ADDRESS>
```

Wait a little while, then check that the domains and IPs match with:
```bash
dig <YOUR_DOMAIN>
dig <YOUR_MQTT_DOMAIN>
```

**Warning: do not proceed until your domain shows the correct IP in the `dig` command output.**

#### Password requirements

> **Important:** Passwords used in RabbitMQ (`rabbitmq.producer.password`, `rabbitmq.consumer.password`,
> `rabbitmq.admin.password`) and Mosquitto (`mosquitto.auth.password`) are embedded verbatim into
> connection URI strings (e.g. `amqp://user:PASSWORD@host:5672`). URI-unsafe characters cause
> `invalid port number` or silent connection failures at runtime.
>
> Use only alphanumeric characters and hyphens in these passwords.
> Avoid: `/ @ : + = %` and any other URI-special characters.
>
> Safe generation example:
> ```bash
> openssl rand -hex 24   # alphanumeric hex, always URI-safe
> ```


#### Step 1 — Define personal config in a private repository

Create a new private repository to store your secrets and private configuration, for example `private-config`.

#### Step 2 — Create custom values file

Create `private-config/custom-values.yaml`:

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

dhi:
  username: "your docker hub username"
  password: "your docker hub password"

mosquitto:
  auth:
    enable: true
    users:
      device:
        username: "<CHOOSE_MOSQUITTO_USERNAME_1>"
        password: "<ALPHANUMERIC_PASSWORD_1>"
      producer:
        username: "<CHOOSE_MOSQUITTO_USERNAME_2>"
        password: "<ALPHANUMERIC_PASSWORD_2>"
      onlineReceiver:
        username: "<CHOOSE_MOSQUITTO_USERNAME_3>"
        password: "<ALPHANUMERIC_PASSWORD_3>"
      apiDevices:
        username: "<CHOOSE_MOSQUITTO_USERNAME_4>"
        password: "<ALPHANUMERIC_PASSWORD_4>"

redis:
  username: "redisuser"
  password: "<REDIS_PASSWORD>"

# create rabbit password with 'openssl rand -hex 24'
rabbitmq:
  user: rabbituse
  password: <RABBIT_PASSWORD_HEX>
  producer:
    user: "produceruser"
    password: <PRODUCER_PASSWORD_HEX>
  consumer:
    user: "consumeruser"
    password: <CONSUMER_PASSWORD_HEX>
  amqpHmacSecret: "<AMQP_HMAC_SECRET_HEX>"

mongodbUrl: "mongodb+srv://<MONGODB_ATLAS_USERNAME>:<MONGODB_ATLAS_PASSWORD>@cluster0.4wies.mongodb.net"

apiServer:
  limitToUserEmails: "<GITHUB_ACCOUNT_EMAIL_TO_LOGIN>,<SECOND_GITHUB_ACCOUNT_EMAIL_TO_LOGIN>" # comma separated
  jwtPassword: "<JWT_PASSWORD>"
  jwtRefreshPassword: "<JWT_REFRESH_PASSWORD>"
  cookieSecret: "<COOKIE_SECRET>"
  oauth2ClientID: "<GITHUB_OAUTH_CLIENT>"
  oauth2SecretID: "<GITHUB_OAUTH_SECRET>"
  oauth2AppClientID: "<GITHUB_OAUTH_APP_CLIENT>"
  oauth2AppSecretID: "<GITHUB_OAUTH_APP_SECRET>"

# create rocket password with 'openssl rand -base64 32'
register:
  rocketSecretKey:
    release: "<ROCKET_REGISTER_SECRET_KEY>"

online:
  rocketSecretKey:
    release: "<ROCKET_ONLINE_SECRET_KEY>"

onlineReceiver:
  rocketSecretKey:
    release: "<ROCKET_ONLINE_RECEIVER_SECRET_KEY>"

onlineAlarm:
  rocketSecretKey:
    release: "<ROCKET_ONLINE_ALARM_SECRET_KEY>"
  firebaseServiceAccount:
    <PUT_FIREBASE_SERVICE_ACCOUNT_JSON_HERE>


# debug configuration, not for production environments
debug:
  pods:
    alwaysPullContainers: false
    # if your pods are crashing, you can enable this to prevent restarts
    # and to access them from your terminal.
    # Do not enable this in production.
    sleepInfinity: false
```

#### Step 3 (optional) - Preview rendered manifests

```bash
cd deployer/home-anthill
helm template -f values.yaml -f ../../private-config/custom-values.yaml . > output-manifests.yaml
```

#### Step 4 - Deploy with Helm

```bash
cd deployer/home-anthill
helm install -f values.yaml -f ../../private-config/custom-values.yaml home-anthill .
```

#### Step 5 - Verify in-cluster routing (no hairpin NAT workaround needed)

With Cilium L2 announcements, in-cluster pods can reach LoadBalancer IPs directly via eBPF,
so no CoreDNS split-horizon DNS patch is required.

Verify by running a test pod in the `cert-manager` namespace (which the NetworkPolicy allows to
reach NGF) using the LoadBalancer IP directly (domain name would redirect to HTTPS via 301):

```bash
# Get the web app LoadBalancer IP
LB_IP=$(kubectl get svc webapp-gateway-nginx -n home-anthill \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Testing hairpin NAT to: $LB_IP"

kubectl run hairpin-test --image=busybox -n cert-manager --restart=Never --rm -it -- \
  wget -T5 -O- http://$LB_IP/
```

Expected output: `wget: server returned error: HTTP/1.1 404 Not Found`

`404` means the packet successfully reached NGF, so hairpin NAT is working. A **timeout** means
something is wrong. Check:

```bash
cilium status | grep -i -E "l2|kube"
kubectl get ciliuml2announcementpolicies
kubectl get ciliumloadbalancerippools
# IPS AVAILABLE should be 0 (both IPs are allocated — this is correct)
```

#### Step 6 — Wait for TLS certificates to be issued

cert-manager will complete the ACME HTTP-01 self-check and obtain certificates from Let's Encrypt.
Watch until both show `READY = True`:

```bash
kubectl get certificates -n home-anthill -w
```

Expected output, which may take 2-5 minutes:
```
NAME         READY   SECRET       AGE
mqtt-tls     True    mqtt-tls     3m
webapp-tls   True    webapp-tls   3m
```

If certificates remain `False` after 10 minutes, diagnose the issue with:
```bash
kubectl get challenges -n home-anthill
kubectl get orders -n home-anthill
kubectl logs -n cert-manager deploy/cert-manager --tail=30
```

If cert-manager logs show `propagation check failed` / `context deadline exceeded`, verify
that Cilium L2 announcements are working (Step 5). Delete the stale challenges to force a retry:
```bash
kubectl delete challenges -n home-anthill --all
kubectl delete orders -n home-anthill --all
# cert-manager automatically recreates them within ~30 seconds
```

#### Step 7 — Verify all pods are running

Once both certificates are `True`, all services start within 1-2 minutes:

```bash
kubectl get pods -n home-anthill
```

Expected result: all pods in the `Running` state. Key startup dependencies:
- `mosquitto` — waits for `mqtt-tls` secret via `wait-for-cert` init container
- `api-devices`, `producer`, `online-receiver` — wait for mosquitto port 1883 via `wait-for-mqtt` init container


#### Step 8 — Verify Gateways and connectivity

```bash
# Both Gateways should show PROGRAMMED=True with the correct external IPs
kubectl get gateway -n home-anthill

# Both LoadBalancer services should show the Floating IPs as EXTERNAL-IP
kubectl get svc -n home-anthill | grep LoadBalancer
```

You should now be able to open `https://YOUR_DOMAIN` in your browser and connect to
`mqtts://YOUR_MQTT_DOMAIN:8883` from ESP32 devices.

#### Step 9 — Verify NetworkPolicies are enforced by Cilium

```bash
# Check Cilium is healthy and all components are running
cilium status

# Confirm Cilium has loaded the policies
kubectl get networkpolicies -n home-anthill

# Optional (it's a long test): run Cilium's full connectivity test suite
cilium connectivity test
```
<br/>


## Useful things

If you want to force-renew Let's Encrypt certificates in `cert-manager`, you can install `cmctl` with `brew install cmctl` on your local machine and run:

```bash
cmctl renew webapp-tls -n home-anthill
cmctl renew mqtt-tls -n home-anthill
```

If cert-manager ACME challenges are stuck in `pending` state (e.g. after a cluster rebuild),
delete the stale challenges and orders to force cert-manager to restart the issuance process:

```bash
kubectl delete challenges -n home-anthill --all
kubectl delete orders -n home-anthill --all
# cert-manager will automatically recreate them and retry
```
