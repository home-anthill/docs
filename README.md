<h1 align="center">
  <br>
  <img src="https://github.com/home-anthill/docs/blob/master/icons/logo512.png?raw=true" alt="ks89/home-anthill" width="220">
  <br>
  <br>
Home Anthill
  <br>
</h1>

home-anthill is a project to control your home remotely with ESP32 devices.

There are 2 types of devices. I chose this categorization:
- `devices`: ESP32 devices to control something, like Air Conditioners.
- `sensors`: ESP32 devices to read physical phenomenons like temperature, humidity, air quality.

At the moment, the only supported `device` is the one to control `Beko air conditioner (Remote type: RG52A9/BGEF)`,
but you can modify the firmware changing the protocol to control you specific model, if supported by [`crankyoldgit/IRremoteESP8266`](https://github.com/crankyoldgit/IRremoteESP8266).

`Sensors` can read temperature, humidity, light (lux), air quality, motion, air pressure.
Feel free to extend this project to match your requirements.

**Please check the `Devices and Sensors` section below to verify the compatibility with ESP32 devices**.

On server-side, I'm using a Kubernetes cluster with a simple microservice architecture.

<br/>

## :house: Architecture :house:

<br/>
<img src="https://raw.githubusercontent.com/home-anthill/docs/master/diagrams/home-anthill-architecture.png" alt="ks89/home-anthill">
<br/>

### Devices sequence diagrams

<br/>
<img src="https://raw.githubusercontent.com/home-anthill/docs/master/diagrams/1-register-devices.png" alt="Sequence diagram register devices">
<br/>
<br/>
<img src="https://raw.githubusercontent.com/home-anthill/docs/master/diagrams/2-control-devices.png" alt="Sequence diagram control devices">
<br/>

### Sensors sequence diagrams

<br/>
<img src="https://raw.githubusercontent.com/home-anthill/docs/master/diagrams/3-register-sensors.png" alt="Sequence diagram register sensors">
<br/>
<br/>
<img src="https://raw.githubusercontent.com/home-anthill/docs/master/diagrams/4-notification-sensors.png" alt="Sequence diagram notification sensors">
<br/>

<br/>

## :building_construction: Local development :building_construction:

To setup this project on your PC to develop and run these microservices, please take a look at [docs/local-development.md](docs/local-development.md)

If everything works as expected, you can proceed to the next step and try to use the production configuration using a real remote server and domains.

<br/>

## :earth_africa: Production installation and deploy :earth_africa:

### Server

First you have to create a MongoDB database, for example on [MongoDB Atlas](https://www.mongodb.com/atlas) using a free account.
Then, you can check the official tutorial [docs/hetzner-install.md](docs/hetzner-install.md) to setup your Kubernetes cluster.
Before continue, you should verify that everything works fine, for example trying to login to the web interface with your GitHub account.

### Devices and Sensors

Supported devices:
- devices:
  **device-ac-beko**: `ESP32 DevKit-C (ESP32-WROOM-32)`, `ESP32 S3 DevKit-C (ESP32-S3-WROOM-1)`
- sensors:
    **sensor-airquality-pir**: `ESP32 DevKit-C (ESP32-WROOM-32)`, `ESP32 S2 DevKit-C (ESP32-S2-SOLO)`, `ESP32 S3 DevKit-C (ESP32-S3-WROOM-1)`
    **sensor-barometer**: `ESP32 DevKit-C (ESP32-WROOM-32)`, `ESP32 S2 DevKit-C (ESP32-S2-SOLO)`, `ESP32 S3 DevKit-C (ESP32-S3-WROOM-1)`
    **sensor-dht-light**: `ESP32 DevKit-C (ESP32-WROOM-32)`, `ESP32 S2 DevKit-C (ESP32-S2-SOLO)`, `ESP32 S3 DevKit-C (ESP32-S3-WROOM-1)`

As you can see, devices are not working with `ESP32 S2 DevKit-C (ESP32-S2-SOLO)` because of [this issue](https://github.com/crankyoldgit/IRremoteESP8266/issues/1922)

To configure and flash firmwares, follow this guide [docs/devices-install.md](docs/devices-install.md).

<br/>
<br/>

## :sparkling_heart: A big thank you to :sparkling_heart:

##### the authors of the main icon of this project:

- <a href="https://www.freepik.com/free-vector/underground-ant-nest-with-red-ants_18582279.htm">Image by brgfx</a> from <a href="https://www.freepik.com/" title="Freepik">Freepik</a>

<br/>
<br/>

# :copyright: License :copyright:

The MIT License (MIT)

Copyright (c) 2021-2022 Stefano Cappa (Ks89)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NON INFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

<br/>
