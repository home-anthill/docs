# Firmwares install guide


## 1. Prepare ESP32 boards with wiring and electrical parts

This section shows how to prepare all firmware variants.
You can use only the ones you need.

Suggested hardware:
- some generic cables (I suggest [this product](https://www.amazon.it/gp/product/B08YRGVYPV/ref=ppx_yo_dt_b_asin_title_o07_s01?ie=UTF8&psc=1))
- 5 x Breadboards 830 points [HERE](https://www.amazon.it/ELEGOO-Breadboard-compatibile-Arduino-Jumper/dp/B06XRG7C5L?th=1)
- 5 x `ESP32 S3 DevKit-C (ESP32-S3-WROOM-1)` [HERE](https://www.digikey.it/it/products/detail/espressif-systems/ESP32-S3-DEVKITC-1U-N8R8/16162636?srsltid=AfmBOorUlJqz4HeVhK1713fLamIR2dg4pMgumz8HgpirVfO7L4LVzpTK)
- 5 x Micro USB cables
- 5 x USB power adapter
- 5 (all optional, 6 if you want to use the `thermostat-mcp9600-simulator`) x `Display OLED I2C 0,91” 128×32 pixel` [HERE](https://futuranet.it/prodotto/display-oled-i2c-091-128x32-pixel/?srsltid=AfmBOopjRC6Q5s2GWDbei20VWqEDNmeBWH89Jfnmz4c2NbtdR3P-GtGZ)
- 5 (all optional, and useful only with display. 9 buttons if you want to use the `thermostat-mcp9600-simulator`) x `Push Button` [HERE](https://www.amazon.it/Interruttore-momentaneo-interruttore-Interruttori-elettrodomestici/dp/B08D6PHYV2)
- 4 (all optional, only useful to show thermostat outputs) x `LED 5mm` [HERE](https://www.amazon.it/Assortimento-Progetti-Arduino-Esperimenti-Scientifici/dp/B0GHNSR6X8/)
and 4 `Resistor 200 Ohm 1/4 W` [HERE](https://www.amazon.it/ELEGOO-Resistenze-Resistori-Tolleranza-Resistenza/dp/B071Z66XDV)
- 5 x `Grove - 4 pin Male Jumper to Grove 4 pin Conversion Cable` (SKU 110990210) [HERE](https://www.seeedstudio.com/Grove-4-pin-Male-Jumper-to-Grove-4-pin-Conversion-Cable-5-PCs-per-Pack.html?queryID=2303afdc4903ae3d41e29da30f358b96&objectID=1321&indexName=bazaar_retailer_products)
- 1 x `Adafruit TSL2591 - High Dynamic Range Digital Light Sensor` (SKU 1980) [HERE](https://www.adafruit.com/product/1980?srsltid=AfmBOormuLaAuLdC5c9iU3ZmF9hiraX6dFdhGGYvwfYVdaNdxMoL_GHg)
- 1 x `Grove - Infrared Emitter` (SKU 101020026) [HERE](https://www.seeedstudio.com/Grove-Infrared-Emitter.html?queryID=160934d31f7e88ba03efa75a63d27010&objectID=2248&indexName=bazaar_retailer_products)
- 1 x `Grove - Air Quality Sensor v1.3 - Arduino Compatible` (SKU 101020078) [HERE](https://www.seeedstudio.com/Grove-Air-Quality-Sensor-v1-3-Arduino-Compatible.html?queryID=b39ed7edc031e50e2d00e646247cba7c&objectID=700&indexName=bazaar_retailer_products)
- 1 x `Adafruit BMP280 I2C or SPI Barometric Pressure & Altitude Sensor` (SKU 2651) [HERE](https://www.adafruit.com/product/2651)
- 1 x `Radar module 24G MmWave HLK-LD2410C` [HERE](https://www.amazon.it/Benefischl-HLK-LD2410C-Rilevazione-Movimento-Presenza/dp/B0CMCH34FY)
- 1 x `DHT22 AM2302 sensor` [HERE](https://www.amazon.it/AZDelivery-temperatura-circuito-Raspberry-gratuito/dp/B078SVZB1X/ref=sr_1_1_sspa?__mk_it_IT=%C3%85M%C3%85%C5%BD%C3%95%C3%91&crid=5C1HXGIU9M4H&keywords=dht22&qid=1670794113&sprefix=dht22%2Caps%2C90&sr=8-1-spons&sp_csd=d2lkZ2V0TmFtZT1zcF9hdGY&psc=1&smid=A1X7QLRQH87QA3)
- 1 x  `Adafruit MCP9600 I2C Thermocouple Amplifier - K, J, T, N, S, E, B and R Type T` [HERE](https://www.adafruit.com/product/4101?srsltid=AfmBOop2GS--fyHQFLK_w9Hz3XF21xN-o0HnBQf9MVE9l1vp0C1ncZiX)
- 1 x `Thermocouple K-Type` to connect to the `Adafruit MCP9600`


DHT + Light
<br/>
<img src="https://raw.githubusercontent.com/home-anthill/docs/master/images/hardware/sensor-dht-light.jpg" alt="dht and light">
<br/>

Barometer
<br/>
<img src="https://raw.githubusercontent.com/home-anthill/docs/master/images/hardware/sensor-barometer.jpg" alt="barometer">
<br/>

Air quality + motion
<br/>
<img src="https://raw.githubusercontent.com/home-anthill/docs/master/images/hardware/sensor-airquality-motion.jpg" alt="airquality and motion">
<br/>

Air Conditioner Beko or LG
<br/>
<img src="https://raw.githubusercontent.com/home-anthill/docs/master/images/hardware/device-ac.jpg" alt="air conditioner">
<br/>

Thermostat (outputs connected to LEDS)
<br/>
<img src="https://raw.githubusercontent.com/home-anthill/docs/master/images/hardware/thermostat-thermocouple-k.jpg" alt="thermostat">
<br/>

Thermostat (outputs connected to LEDS) with MCP9600 simulator (development only)
<br/>
<img src="https://raw.githubusercontent.com/home-anthill/docs/master/images/hardware/thermostat-with-mcp9600-simulator.jpg" alt="thermostat-with-mcp9600-simultor">
<br/>

Connections:
- all sensors are powered with 3.3V, except for MmWave HLK-LD2410C module
- DHT signal input on pin 4
- IR emitter on pin 4
- Air quality signal on pin 4
- 24G MmWave HLK-LD2410C motion sensor I2C (SCL on pin 39, SDL on pin 40)
- Barometric Pressure sensor I2C (SCL on pin 39, SDL on pin 40)
- Digital light sensor I2C (SCL on pin 39, SDL on pin 40)
- Thermocouple amplifier I2C (SCL on pin 39, SDL on pin 40)
- Display OLED I2C (SCL on pin 39, SDL on pin 40)

You can change these inputs as needed and adjust the firmware accordingly.


## 2. Build and flash firmwares


1. Configure [Arduino IDE 2.x](https://www.arduino.cc/en/software) to build and flash ESP32 firmware. You need the `esp32` board in `Board Manager`, as described in [the official tutorial](https://espressif-docs.readthedocs-hosted.com/projects/arduino-esp32/en/latest/installing.html).
Then build and flash one of the official examples to verify that everything works correctly.
These firmwares are known to build with the `esp32` board package from Espressif, version `3.3.7`.

2. In Arduino IDE, install these libraries from the `Library Manager` tab:
- `ArduinoJson` by Benoit Blanchon (version `7.4.3`)
- `PubSubClient` by Nick O'Leary (version `2.8`)
- `TimeAlarms` by Michael Margolis (version `1.5`)
- `Adafruit Unified Sensor` by Adafruit (version `1.1.15`)
- `DHT sensor library` by Adafruit (version `1.4.6`)
- `IRremoteESP8266` by David Conran, Sebastien Warin, Mark Szabo, Ken Shirriff (version `2.9.0`)
- `Time` by Michael Margolis (version `1.6.1`) (not used directly, but it's an indirect dependency of `TimeAlarms`)
- `Adafruit BMP280 library` by Adafruit (version `3.0.0`)
- `ld2410` by Nick Reynolds (version `0.2.2`)
- `Grove - Air quality sensor` by Seeed Studio (version `1.0.2`)
- `Adafruit TSL2591 Library` by Adafruit (version `1.4.5`)
- `Adafruit GFX Library` by Adafruit (version `1.12.6`)
- `Adafruit SSD1306` by Adafruit (version `2.5.16`)
- `Adafruit BusIO` by Adafruit (version `1.17.4`)
- `Adafruit MCP9600 Library` by Adafruit (version `2.0.4`)

`HTTPClient` is provided by the ESP32 Arduino core, so do not install the older `HttpClient` library by Adrian McEwen for this project.

3. Create a new `private-config/secrets.yaml` file.

For local development (suggested as first try):

```yaml
# development configuration used locally

wifi_ssid: '<YOUR WIFI SSID>'
wifi_password: '<YOUR WIFI PASSWORD>'

manufacturer: 'ks89'
api_token: '<PROFILE API TOKEN>' # from your local DB or via `regenApiToken` in Bruno

ssl: false
# HTTP server
server_domain: '192.168.1.7' # your local IP discovered above
server_port: 8099
server_path: '/admission/register'
# MQTT server
mqtt_domain: '192.168.1.7' # your local IP discovered above
mqtt_port: 1883
mqtt_auth: true
mqtt_username: "<YOUR MOSQUITTO USERNAME>"
mqtt_password: "<YOUR MOSQUITTO PASSWORD>"

oled_display: false
```

For production:

```yaml
wifi_ssid: '<YOUR WIFI SSID>'
wifi_password: '<YOUR WIFI PASSWORD>'

manufacturer: 'ks89'
api_token: '<PROFILE API TOKEN>' # from your local DB

# enable both HTTPS and MQTTS
# adjust the ports accordingly
# https port: 443
# mqtts port: 8883
ssl: true
# HTTP server
server_domain: '<YOUR HTTPS PUBLIC DOMAIN>'
server_port: '443'
server_path: '/admission/register'
# MQTT server
mqtt_domain: '<YOUR MQTTS PUBLIC DOMAIN>'
mqtt_port: 8883
mqtt_auth: true
mqtt_username: "<YOUR MOSQUITTO USERNAME>"
mqtt_password: "<YOUR MOSQUITTO PASSWORD>"

oled_display: false
```

4. Run the `esp32-configurator` Python script:

```bash
cd esp32-configurator

# install dependencies
poetry install

# run these commands
poetry run python -m src --model=dht-light --source=../private-config/secrets.yaml --destination=../firmwares/dht-light
poetry run python -m src --model=airquality-motion --source=../private-config/secrets.yaml --destination=../firmwares/airquality-motion
poetry run python -m src --model=barometer --source=../private-config/secrets.yaml --destination=../firmwares/barometer

poetry run python -m src --model=thermostat --source=../private-config/secrets.yaml --destination=../firmwares/thermostat

poetry run python -m src --model=ac-beko --source=../private-config/secrets.yaml --destination=../firmwares/ac-beko
poetry run python -m src --model=ac-lg --source=../private-config/secrets.yaml --destination=../firmwares/ac-lg
```

5. Build and flash the firmwares

- Open `firmwares/ac-beko/ac-beko.ino` in Arduino IDE and flash the firmware.
- Open `firmwares/ac-lg/ac-lg.ino` in Arduino IDE and flash the firmware.
- Open `firmwares/dht-light/dht-light.ino` in Arduino IDE and flash the firmware.
- Open `firmwares/airquality-motion/airquality-motion.ino` in Arduino IDE and flash the firmware.
- Open `firmwares/barometer/barometer.ino` in Arduino IDE and flash the firmware.
- Open `firmwares/thermostat/thermostat.ino` in Arduino IDE and flash the firmware.


6. (optional) Thermostat simulator with ESP-IDF

Testing `thermostat` firmware is difficult when relying on a real `thermocouple` and an `Adafruit MCP9600` to control temperatures. To make this easier, I built a simulator using another ESP32-S3, a display, and four buttons to send exact temperature values.

First, power off the `thermostat` and disconnect the `Adafruit MCP9600` from the I2C bus. Then, connect a second breadboard according to the wiring described in `firmwares/thermostat-mcp9600-simulator/README.md` (as shown in the image above). Once connected, you can simply press the buttons to increase or decrease the temperature registered by the `thermostat`.

**ATTENTION: You must start first the simulator and next the thermostat**

To build, flash firmware and read serial monitor of the simulator, please follow the guide in firmwares repository at `firmwares/thermostat-mcp9600-simulator/README.md`.