# Heztner cloud with Kubernetes

Based on https://docs.k3s.io/quick-start

## Environment

- Ubuntu 22.04 LTS
- Kubernetes v1.25.4+k3s1
- [Flannel 0.20.2](https://github.com/flannel-io/flannel)
- [MetalLB 0.13.7](https://metallb.universe.tf/)

## Server creation

From Hetzner Cloud UI create a server like this:

REGION: Falkenstein
OS type: Ubuntu 22.04
Type: Standard - CPX11 - 2 vCPU - 2 GB RAM - 40 GB disk
Volume: none
Network: none
Firewalls: none
Additional features: none
SSH Keys: Create a SSH key-pair and paste the public one or enable an existing one
Name: what you like


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
ssh -i ~/.ssh/<private_key_file> root@<HETZNER_SERVER_IP>
```


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

Now, you should be able to connect to the cluster from your local machine, for example via `kubectl` or softwares like [k9s](https://k9scli.io/).


## Install Flannel CNI plugin

MetalLB reports some incompatibilities with different CNI plugins, so I chose Flannel, because it seems supported without issues.

```bash
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/v0.20.2/Documentation/kube-flannel.yml
```


## Install MetalLB

```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.7/config/manifests/metallb-native.yaml
```


## Prepare Persistent Volumes

Two PVs are required to store nginx.conf and SSL certificates.
Let's Encrypt certificates issued via Certbot are limited. You cannot register your domain multiple times, otherwise you'll be banned for many days.
So, you need to store certificates and re-use they.

Access to Hetzner server via SSH and prepare these two folders:

```bash
mkdir /root/lets-encrypt-certs
mkdir /root/lets-encrypt-certs-mqtt
mkdir /root/nginx-conf
```


## Deploy application

## Development without SLL and domain names (**NOT RECOMMENDED**)

1. Define personal config in a private repository

Create a new private repository to store your secrets and private configurations, for instance `private-config`

2. Create a custom values file in `private-config/custom-values.yaml` with a specific configuration like:

```yaml
domains:
  # overwrite default http domain to don't use domain name
  # in this way you'll be able to reach this web app and rest services via `gui.publicIp`
  http: "<gui-floating-ip_IP_ADDRESS>"
  mqtt: "localhost"

mosquitto:
  publicIp: "<mosquitto-floating-ip_IP_ADDRESS>"
  auth:
    enable: true
    username: "<CHOOSE_MOSQUITTO_USERNAME>"
    password: "<CHOOSE_MOSQUITTO_PASSWORD>"

apiServer:
  oauth2ClientID: "<GITHUB_OAUTH_CLIENT>"
  oauth2SecretID: "<GITHUB_OAUTH_SECRET>"
  singleUserLoginEmail: "<GITHUB_ACCOUNT_EMAIL_TO_LOGIN>"

gui:
  publicIp: "<gui-floating-ip_IP_ADDRESS>"

mongodbUrl: "mongodb+srv://<MONGODB_ATLAS_USERNAME>:<MONGODB_ATLAS_PASSWORD>@cluster0.4wies.mongodb.net"
```

3. (optional step) If you want to see all manifests processed by Helm without deploying them, you can run:

```bash
cd deployer/home-anthill
helm template -f values.yaml -f ../../private-config/custom-values.yaml . > output-manifests-no-ssl.yaml
```

4. Deploy with Helm

```bash
cd deployer/home-anthill
helm install -f values.yaml -f ../../private-config/custom-values.yaml home-anthill .
```

5. Check kubernetes services! You should see 2 LoadBalancers with the right Floating IPs assigned.
   After some time, you'll be able to navigate to the website via HTTP and to the Mosquitto server via MQTT connection.



## Production with SSL and domain names

First, you need to but 2 public web domains, for example [HERE](https://www.godaddy.com/).
Then, you can update DNS records of your domains:

```
A @ <gui-floating-ip_IP_ADDRESS>
A wwww <gui-floating-ip_IP_ADDRESS>
```

```
A @ <mosquitto-floating-ip_IP_ADDRESS>
A wwww <mosquitto-floating-ip_IP_ADDRESS>
```


1. Define personal config in a private repository

Create a new private repository to store your secrets and private configurations, for instance `private-config`

2. Create a custom values file in `private-config/custom-values.yaml` with a specific configuration like:

```yaml
domains:
  http: "YOUR_DOMAIN"
  mqtt: "YOUR_MQTT_DOMAIN"

mosquitto:
  publicIp: "<mosquitto-floating-ip_IP_ADDRESS>"
  auth:
    enable: true
    username: "<CHOOSE_MOSQUITTO_USERNAME>"
    password: "<CHOOSE_MOSQUITTO_PASSWORD>"
  ssl:
    enable: true
    certbot:
      email: "<YOUR_CERTIFICATE_EMAIL>"

apiServer:
  oauth2ClientID: "<GITHUB_OAUTH_CLIENT>"
  oauth2SecretID: "<GITHUB_OAUTH_SECRET>"
  singleUserLoginEmail: "<GITHUB_ACCOUNT_EMAIL_TO_LOGIN>"
  jwtPassword: "<JWT_PASSWORD>"
  cookieSecret: "<COOKIE_SECRET>"

gui:
  publicIp: "<gui-floating-ip_IP_ADDRESS>"
  ssl:
    enable: true
    certbot:
      email: "<YOUR_CERTIFICATE_EMAIL>"

mongodbUrl: "mongodb+srv://<MONGODB_ATLAS_USERNAME>:<MONGODB_ATLAS_PASSWORD>@cluster0.4wies.mongodb.net"
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

5. Check kubernetes services! You should see 2 LoadBalancers with the right Floating IPs assigned.
   After some time, you'll be able to navigate to the website via HTTPS and to the Mosquitto server via MQTTS connection.
   ESP32 device should already be working using secure connections.
   If you have problems with certificates, you should check if certbot is started getting SSL certificates from Let's Encrypt.
   Certbot runs on these 2 pods:
   - gui
   - mosquitto

<br/>