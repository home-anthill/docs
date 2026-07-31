#!/bin/sh
set -e

mkdir home-anthill
cd home-anthill

git clone https://github.com/home-anthill/gui.git
git clone https://github.com/home-anthill/api-server.git
git clone https://github.com/home-anthill/api-devices.git
git clone https://github.com/home-anthill/admission.git
git clone https://github.com/home-anthill/producer.git
git clone https://github.com/home-anthill/consumer.git
git clone https://github.com/home-anthill/register.git
git clone https://github.com/home-anthill/esp32-configurator.git
git clone https://github.com/home-anthill/mosquitto.git
git clone https://github.com/home-anthill/firmwares.git
git clone https://github.com/home-anthill/deployer.git
git clone https://github.com/home-anthill/alarm-api.git
git clone https://github.com/home-anthill/alarm-receiver.git
git clone https://github.com/home-anthill/alarm-notifier.git
git clone https://github.com/home-anthill/sharded-mongodb-compose.git
git clone https://github.com/home-anthill/app.git
git clone https://github.com/home-anthill/mqtt-communication-checker.git

# always from the `home-anthill` folder created above:
# create a folder where you can put your custom configuration
mkdir private-config
