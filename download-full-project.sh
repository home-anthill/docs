#!/bin/sh
set -e

mkdir home-anthill
cd home-anthill
git clone https://github.com/home-anthill/gui.git
git clone https://github.com/home-anthill/api-server.git
git clone https://github.com/home-anthill/api-devices.git
git clone https://github.com/home-anthill/producer.git
git clone https://github.com/home-anthill/consumer.git
git clone https://github.com/home-anthill/register.git
git clone https://github.com/home-anthill/esp32-configurator.git
git clone https://github.com/home-anthill/mosquitto.git
git clone https://github.com/home-anthill/devices.git
git clone https://github.com/home-anthill/sensors.git
git clone https://github.com/home-anthill/deployer.git

mkdir private-config
# use the Helm Chart `values.yaml` file as a starting point to simplify the configuration
cp ../deployer/ac/values.yaml custom-values-no-ssl.yaml
cp ../deployer/ac/values.yaml custom-values.yaml
# use the `secrets-template` template as a starting point to simplify the configuration 
cp ../devices/secrets-template secrets-local.yaml
cp ../devices/secrets-template secrets.yaml

echo "Update `private-config` yaml files with your configurations!!!"
