# Devices install guide


## 1. Prepare ESP32 boards with wiring and electrical parts

In this section, I'll show how to prepare all types of devices and sensors.
Obviously, you are free to use only some of them.

Suggested hardware:
- some generic cables (I suggest [this product](https://www.amazon.it/gp/product/B08YRGVYPV/ref=ppx_yo_dt_b_asin_title_o07_s01?ie=UTF8&psc=1))
- 4 x Mini Breadboards [HERE](https://www.amazon.it/AZDelivery-MB-102-Breadboard-Alimentazione-Arduino/dp/B07VFK5CRP/ref=sr_1_5?keywords=breadboards&qid=1670794035&sr=8-5)
- 1 x `ESP32 S3 DevKit-C (ESP32-S3-WROOM-1)` [HERE](https://www.mouser.it/ProductDetail/Espressif-Systems/ESP32-S3-DevKitC-1-N8?qs=Wj%2FVkw3K%252BMCTHFMHLvA1pQ%3D%3D)
- 3 x `ESP32 S2 DevKit-C (ESP32-S2-SOLO)` [HERE](https://www.mouser.it/ProductDetail/Espressif-Systems/ESP32-S2-DevKitC-1?qs=sGAEpiMZZMuqBwn8WqcFUipNgoezRlc4yCMrcjU15dajQwJoGbTgng%3D%3D)
- 1 x `Grove - 4 pin Male Jumper to Grove 4 pin Conversion Cable` (SKU 110990210) [HERE](https://www.seeedstudio.com/Grove-4-pin-Male-Jumper-to-Grove-4-pin-Conversion-Cable-5-PCs-per-Pack.html?queryID=2303afdc4903ae3d41e29da30f358b96&objectID=1321&indexName=bazaar_retailer_products)
- 1 x `Grove - Digital Light Sensor - TSL2561` (SKU 101020030) [HERE](https://www.seeedstudio.com/Grove-Digital-Light-Sensor-TSL2561.html?queryID=4a3675ce800dd579fb0e50d00ef6b601&objectID=1594&indexName=bazaar_retailer_products)
- 1 x `Grove - Infrared Emitter` (SKU 101020026) [HERE](https://www.seeedstudio.com/Grove-Infrared-Emitter.html?queryID=160934d31f7e88ba03efa75a63d27010&objectID=2248&indexName=bazaar_retailer_products)
- 1 x `Grove - Air Quality Sensor v1.3 - Arduino Compatible` (SKU 101020078) [HERE](https://www.seeedstudio.com/Grove-Air-Quality-Sensor-v1-3-Arduino-Compatible.html?queryID=b39ed7edc031e50e2d00e646247cba7c&objectID=700&indexName=bazaar_retailer_products)
- 1 x `Grove - High Precision Barometric Pressure Sensor (DPS310)` (SKU 101020812) [HERE](https://www.seeedstudio.com/Grove-High-Precision-Barometer-Sensor-DPS310-p-4397.html?queryID=550beac2830c58583bcc256e3bf3f245&objectID=4397&indexName=bazaar_retailer_products)
- 1 x `Mini AM312 PIR sensor` [HERE](https://www.amazon.it/gp/product/B07FGG87JM/ref=ppx_yo_dt_b_asin_title_o07_s00?ie=UTF8&psc=1)
- 1 x `DHT22 AM2302 sensor` [HERE](https://www.amazon.it/AZDelivery-temperatura-circuito-Raspberry-gratuito/dp/B078SVZB1X/ref=sr_1_1_sspa?__mk_it_IT=%C3%85M%C3%85%C5%BD%C3%95%C3%91&crid=5C1HXGIU9M4H&keywords=dht22&qid=1670794113&sprefix=dht22%2Caps%2C90&sr=8-1-spons&sp_csd=d2lkZ2V0TmFtZT1zcF9hdGY&psc=1&smid=A1X7QLRQH87QA3)
- 4 x Micro USB cables
- 4 x USB power adapter


Sensor (DHT + Light)
<br/>
<img src="https://raw.githubusercontent.com/home-anthill/docs/master/images/hardware/sensor-dht-light.jpg" alt="sensor dht and light">
<br/>

Sensor (Barometer)
<br/>
<img src="https://raw.githubusercontent.com/home-anthill/docs/master/images/hardware/sensor-barometer.jpg" alt="sensor barometer">
<br/>

Sensor (Air quality + PIR)
<br/>
<img src="https://raw.githubusercontent.com/home-anthill/docs/master/images/hardware/sensor-airquality-pir.jpg" alt="sensor airquality and pir">
<br/>

Device (AC Beko or LG)
<br/>
<img src="https://raw.githubusercontent.com/home-anthill/docs/master/images/hardware/device-ac.jpg" alt="sensor air conditioner">
<br/>


Connections:
- all sensors are powered on with 3.3V
- DHT signal input on pin 4
- PIR signal input on pin 5
- IR emitter on pin 4
- Air quality signal on pin 4
- Barometric Pressure sensor I2C (SCL on pin 39, SDL on pin 40)
- Digital light sensor I2C (SCL on pin 39, SDL on pin 40)

You are free to change these inputs modifying firmwares accordingly.


## 2. Build and flash firmwares


1. Configure [Arduino IDE 2.x](https://www.arduino.cc/en/software) to build and flash ESP32 firmwares. You need the `esp32` board in `Board Manager` as described in [the official tutorial](https://espressif-docs.readthedocs-hosted.com/projects/arduino-esp32/en/latest/installing.html).
Then try to build and flash one of the official examples to see if everything is ok!
I'm using Board Manager `esp32` by Espressif (version `3.1.0` for sensors and `2.0.17` for devices).

2. From Arduino IDE install these libraries from `Library Manager` tab:
- `ArduinoJson` by Benoit Blanchon (version `7.3.0`)
- `HttpClient` by Adrian McEwen (version `2.2.0`)
- `PubSubClient` by Nick O'Leary (version `2.8`)
- `TimeAlarms` by Michael Margolis (version `1.5`)
- `Adafruit Unified Sensor` by Adafruit (version `1.1.15`)
- `DHT sensor library` by Adafruit (version `1.4.6`)
- `IRremoteESP8266` by David Conran, Sebastien Warin, Mark Szabo, Ken Shirriff (version `2.8.6`)
- `Time` by Michael Margolis (version `1.6.1`) (not used directly, but it's an indirect dependency of `TimeAlarms`)
- `XENSIV Digital Pressure Sensor` by Infineon Technologies (version `1.0.0`)
- `Grove - Air quality sensor` by Seeed Studio (version `1.0.2`)
- `Grove - Digital Light Sensor` by Seeed Studio (version `2.0.0`)

3. Create a new file `private-config/secrets.yaml` file with this content

```yaml
wifi_ssid: '<YOUR WIFI SSID>'
wifi_password: '<YOUR WIFI PASSWORD>'

manufacturer: 'ks89'
api_token: '<PROFILE API TOKEN>' # from your local DB

# enable both HTTPS and MQTTS
# you should change PORTS accordingly
# https port: 443
# mqtts port: 8883
ssl: true

server_domain: '<YOUR HTTPS PUBLIC DOMAIN>'
server_port: '443'
server_path: '/admission/register'

mqtt_domain: '<YOUR MQTTS PUBLIC DOMAIN>'
mqtt_port: 8883
mqtt_auth: true
mqtt_username: "<YOUR MOSQUITTO USERNAME>"
mqtt_password: "<YOUR MOSQUITTO PASSWORRD>"
```

4. Run `esp32-configurator` Python script:

```bash
cd esp32-configurator

# install dependencies
poetry install

# spawn poetry shell
poetry shell

# inside the poetry shell sun these commands
python3 -m src --model=dht-light --source=../private-config/secrets.yaml --destination=../sensors/sensor-dht-light
python3 -m src --model=airquality-pir --source=../private-config/secrets.yaml --destination=../sensors/sensor-airquality-pir
python3 -m src --model=barometer --source=../private-config/secrets.yaml --destination=../sensors/sensor-barometer
python3 -m src --model=power-outage --source=../private-config/secrets.yaml --destination=../sensors/sensor-power-outage

python3 -m src --model=ac-beko --source=../private-config/secrets.yaml --destination=../devices/device-ac-beko
python3 -m src --model=ac-lg --source=../private-config/secrets.yaml --destination=../devices/device-ac-lg
```

5. Build and flash firmwares

- Open `devices/device-ac-beko/device-ac-beko.ino` with ArduinoIDE and flash the firmware
- Open `devices/device-ac-lg/device-ac-lg.ino` with ArduinoIDE and flash the firmware
- Open `sensors/sensor-dht-light/sensor-dht-light.ino` with ArduinoIDE and flash the firmware
- Open `sensors/sensor-airquality-pir/sensor-airquality-pir.ino` with ArduinoIDE and flash the firmware
- Open `sensors/sensor-barometer/sensor-barometer.ino` with ArduinoIDE and flash the firmware
- Open `sensors/sensor-power-outage/sensor-power-outage.ino` with ArduinoIDE and flash the firmware
