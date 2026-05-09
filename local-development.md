# Local development setup (macOS)

## 0. Install prerequisites

### Install GNU Make and CMake (both required)

On macOS install these with:
```bash
brew install make

# cmake is required by some rust dependencies
brew install cmake
```

Check that everything works correctly by running:
```bash
make -v
cmake --version
```


### Install `mosquitto_passwd` CLI

On macOS, install it via [Homebrew](https://formulae.brew.sh/formula/mosquitto) with `brew install mosquitto`.



## 1. Install Go


1. On macOS install it via [Homebrew](https://formulae.brew.sh/formula/go) with `brew install go`
2. Install [air](https://github.com/cosmtrek/air) to watch for changes and automatically rebuild:

```bash
curl -sSfL https://raw.githubusercontent.com/cosmtrek/air/master/install.sh | sh -s -- -b $(go env GOPATH)/bin
```

Check that everything works correctly by running:
```bash
go version
air -v
```


## 2. Install Rust


Install Rust from [here](https://www.rust-lang.org/) with the `rustup` script.

Check that everything works correctly by running:
```bash
cargo --version
```


## 3. Install Node.js


Install Node.js LTS from [here](https://nodejs.org/).

Check that everything works correctly by running:
```bash
node -v
npm -v
```


## 4. Install Python and Poetry


Install Python 3.12 or later from [HERE](https://www.python.org/downloads/).

Check that everything works correctly by running:
```bash
python3 --version
pip3 --version
```
Then [install Poetry](https://python-poetry.org/docs/#installation).

Add the optional poetry shell plugin:
```bash
poetry self add poetry-plugin-shell
```


## 5. Install Android Studio and adb (only for Android app development)


Install Android Studio from [here](https://developer.android.com/studio).

Also install `adb` via [Homebrew](https://formulae.brew.sh/formula/android-platform-tools) with `brew install android-platform-tools`.

Check that everything works correctly by running:
```bash
adb --version
```


## 6. Install `rabbitmqadmin v2` CLI (optional)


This is **required only to run integration tests for some services, such as `consumer`**.
If you only want to run this project locally, **you can skip this step**.

On macOS, install [rabbitmqadmin-ng](https://github.com/rabbitmq/rabbitmqadmin-ng) with `cargo install rabbitmqadmin`.

You do not need to start a local RabbitMQ server, because we will use a Docker container.
Make sure the local RabbitMQ server is not running:
```bash
brew services info --all
```

Check that everything works correctly by running:
```bash
rabbitmqadmin --help
# print the location of rabbitmqadmin executable
which rabbitmqadmin
```


## 7. Install and run Docker Desktop with docker compose


Install Docker Desktop from [HERE](https://www.docker.com/).

Then check that you can run these commands:

```bash
docker --version
docker compose version
```


## 8. Download repos


Run [this script](download-full-project.sh) in the location where you want to store the `home-anthill` project.
I suggest using a main `home-anthill` folder for all of your Git repositories.


## 9. Deploy local docker containers


1. Mosquitto

```bash
cd home-anthill/mosquitto
mkdir -p data
mkdir -p log
chmod 0700 mosquitto-local-acl.conf

# Build home-anthill Mosquitto
docker build -t ks89/mosquitto:local .

docker run -it --name mosquitto \
    -p 1883:1883 \
    -p 9001:9001 \
    --rm \
    -v ./mosquitto-local-dev.conf:/mosquitto/config/mosquitto.conf:ro \
    -v ./mosquitto-local-acl.conf:/mosquitto/acl/acl_file:ro \
    -v ./data:/mosquitto/data \
    -v ./log:/mosquitto/log \
    -e MOSQUITTO_USERS='device_pubsub:DevicePassword1!,producer_sub:ProducerPassword1!,online_receiver_sub:OnlineReceiverPassword1!,api_devices_pub:ApiDevicesPassword1!' \
    ks89/mosquitto:local
```
**Do not close this terminal window.**

2. RabbitMQ

Open a new terminal window and run:
```bash
cd home-anthill

# Ensure the configuration directory and files exist
mkdir -p rabbitmq-local

cat << 'EOF' > rabbitmq-local/definitions.json
{
  "users": [
    {
      "name": "guest",
      "password": "guest",
      "tags": "administrator"
    },
    {
      "name": "produceruser",
      "password": "producerpassword",
      "tags": ""
    },
    {
      "name": "consumeruser",
      "password": "consumerpassword",
      "tags": ""
    }
  ],
  "vhosts": [
    {
      "name": "/"
    }
  ],
  "permissions": [
    {
      "user": "guest",
      "vhost": "/",
      "configure": ".*",
      "write": ".*",
      "read": ".*"
    },
    {
      "user": "produceruser",
      "vhost": "/",
      "configure": "^ks89$",
      "write": "^(amq\\.default|ks89)$",
      "read": "^ks89$"
    },
    {
      "user": "consumeruser",
      "vhost": "/",
      "configure": "^ks89$",
      "write": "",
      "read": "^ks89$"
    }
  ]
}
EOF

cat << 'EOF' > rabbitmq-local/rabbitmq.conf
management.load_definitions = /etc/rabbitmq/definitions.json
EOF

docker pull rabbitmq:management

# run this from the root ./home-anthill folder
docker run -d --name rabbitmq --hostname my-rabbit \
  -p 15672:15672 -p 15671:15671 -p 5672:5672 \
  -v ./rabbitmq-local/rabbitmq.conf:/etc/rabbitmq/rabbitmq.conf:ro \
  -v ./rabbitmq-local/definitions.json:/etc/rabbitmq/definitions.json:ro \
  rabbitmq:management
```
If you want, you can access the UI at `http://localhost:15672` and log in with:
```
user: guest
password: guest
```

3. MongoDB

**ATTENTION**: To be able to use **MongoDB transactions**, we need a cluster. To deploy it with 2 replicas on your local machine,
I suggest using Docker compose with the `.yml` available in `sharded-mongodb-compose`.

```bash
cd home-anthill/sharded-mongodb-compose
docker compose up --build -d
```

You can also restore a previous home-anthill MongoDB BSON backup:

```bash
# Restore
mongorestore --uri="mongodb://localhost:27017" --nsInclude='*.*' ./backup-folder-with-prelude_json
# Backup
mongodump --uri="mongodb://localhost:27017" --out ./backup-folder-with-prelude_json
```

4. Redis

Install Redis with persistence:
```bash
docker run --name redis -p 6379:6379 -d redis redis-server \
  --save 60 1 \
  --loglevel warning \
  --user redisuser on '>Password1!' '~*' '+@all'

# --user redisuser: Defines the new username.
# on: Enables the user account.
# >Password1!: Sets the password (the > symbol is required before the password).
# ~*: Grants access to all keys.
# +@all: Grants permissions for all commands.
```


## 10. Create two GitHub OAuth2 applications and update the `api-server` `.env` file


1. GitHub OAuth2 app for website login

```bash
cd home-anthill/api-server
cp .env_template .env
```

Update the `OAUTH2_CLIENTID` and `OAUTH2_SECRETID` properties in the `api-server` `.env` file.
These two values are the client ID and client secret of your GitHub OAuth2 application, so follow these steps:
- create an [OAuth2 app on GitHub](https://docs.github.com/en/developers/apps/building-oauth-apps/creating-an-oauth-app) (suggested name: `home-anthill-web-dev`)
- go to the configuration page of your OAuth2 app and copy the `Client ID` value (`OAUTH2_CLIENTID`)
- click `Generate a new client secret` and copy the code to the `.env` file (`OAUTH2_SECRETID`)
- fill the `Application name` input field: `home-anthill-web-dev`
- fill the `Homepage URL` input field: `http://localhost:4200`
- fill the `Authorization callback URL` input field: `http://localhost:4200/api/oauth/callback`
- save the OAuth2 app


2. GitHub OAuth2 app for Android login

Update the `OAUTH2_APP_CLIENTID` and `OAUTH2_APP_SECRETID` properties in the `api-server` `.env` file.
These two values are the client ID and client secret of your GitHub OAuth2 application, so follow these steps:
- create an [OAuth2 app on GitHub](https://docs.github.com/en/developers/apps/building-oauth-apps/creating-an-oauth-app) (suggested name: `home-anthill-app-dev`)
- go to the configuration page of your OAuth2 app and copy the `Client ID` value (`OAUTH2_APP_CLIENTID`)
- click `Generate a new client secret` and copy the code to the `.env` file (`OAUTH2_APP_SECRETID`)
- fill the `Application name` input field: `home-anthill-app-dev`
- fill the `Homepage URL` input field: `http://localhost:4200`
- fill the `Authorization callback URL` input field: `http://localhost:4200/api/oauth/app/callback`
- save the OAuth2 app


## 11. Create a Firebase Cloud Messaging app


Create a new project in the [Firebase console](https://console.firebase.google.com/) by following these steps:
1. ignore Google Analytics step
2. add an Android app to your new project
3. insert `eu.homeanthill` as package name, because it must match the name of the Android app
4. download the `google-services.json` file from `Project Settings` -> `General`. This file is required to build the Android app below and receive push notifications.
5. create the app
6. go to `Project Settings` -> `Service account`, select `SDK Firebase Admin`, and click
   the `Generate a new private key` button to download `serviceAccountKey.json` (this is required to run `online-alarm` below and send push notifications).


## 12. Run all microservices

**With MongoDB, RabbitMQ, Mosquitto and Redis up and running**, you can start all microservices.

Open each microservice in a terminal tab or separate window.

1. api-server

```bash
cd home-anthill/api-server
cp .env_template .env
# `.env` must contain valid client IDs and client secrets
make deps
make run
```

2. admission

```bash
cd home-anthill/admission
cp .env_template .env
make deps
make run
```

3. api-devices

```bash
cd home-anthill/api-devices
cp .env_template .env
make deps
make run
```

4. register

```bash
cd home-anthill/register
cp .env_template .env
make deps
make run
```

5. producer

```bash
cd home-anthill/producer
cp .env_template .env
make deps
make run
```

6. consumer

```bash
cd home-anthill/consumer
cp .env_template .env
make deps
make run
```

7. online-receiver

```bash
cd home-anthill/online-receiver
cp .env_template .env
make deps
make run
```

8. online

```bash
cd home-anthill/online
make deps
make run
```

9. online-alarm

```bash
cd home-anthill/online-alarm
cp .env_template .env
# replace the template file with the one obtained above
cp serviceAccountKey.json_template serviceAccountKey.json
make deps
make run
```

10. gui

```bash
cd home-anthill/gui
npm i
# run the dev server on port 4200 at `http://localhost:4200` with the local proxy
npm start
```

11. app

```bash
cd home-anthill/app
cp secrets.defaults.properties secrets.properties
cp secrets.defaults.properties staging.properties
cp secrets.defaults.properties release.properties
# replace the template file with the one obtained above
cp google-services.json_template app/google-services.json
```

12. login to the webapp with your GitHub account

If everything is running, **you should be able to access `http://localhost:4200`** from your browser.
From `http://localhost:4200`, **log in with the GitHub account used to create the OAuth2 application**.
If the login succeeds, you will be redirected to the main app page.


## 13. Fill MongoDB with some data


At this point, you should be able to log in to the app, so the database already contains a valid profile.
However, you do not have any other data yet.


### Log in to create a Profile and get a valid JWT

1. From your browser, log in via GitHub at `http://localhost:4200`
2. Open the browser developer tools and copy the JWT `token` value (standard format `xxxx.xxxx.xxxx`) from `Local Storage` (in Chrome, you can find `Local Storage` under the `Application` tab).
3. From the `Cookies` section, copy the cookie called `oauth_session`.


### Fill MongoDB with useful data

If you logged in and copied the JWT `token` and `oauth_session` cookie, I suggest using this script to fill MongoDB with sample data and expose all `home-anthill` capabilities.

ATTENTION: this script regenerates the profile API token. If you followed this guide in order, that is not a problem, because the API token is still unknown at this point.

```bash
./fill-local-db.sh "<JWT_VALUE>" "<COOKIE_VALUE>"
```


### Bruno

1. Install the [Bruno](https://www.usebruno.com/) desktop app.
2. Open Bruno and click **Open Collection**, then select the `docs/bruno-collections` folder from this repository.
3. The collection includes requests for endpoints such as `api-server`, `admission`, and `online`.
4. In Bruno, open the collection's **Environments** (top-right), create or edit an environment, and set `authToken` to the **JWT token** you copied.
5. In Bruno, **create a new cookie** called `oauth_session`, with path `/` and the value copied from the browser.
6. Select the `getProfile` request (because it requires JWT authentication) from the collection and click **Send**. The response should be something like this:

```json
{
    "profile": {
        "id": "<YOUR PROFILE MONGODB OBJECTID>",
        "github": {
            "login": "<YOUR GITHUB NICKNAME>",
            "name": "<YOUR GITHUB NAME>",
            "email": "<YOUR GITHUB EMAIL>",
            "avatarURL": "<YOUR GITHUB AVATAR URL>"
        }
        ...
    }
}
```

7. You can try the other requests too, but be sure to update **path** and **query parameters** with your object IDs (taken from your local database).
For example, to get the `apiToken` required in the next steps, call `regenApiToken` and replace the fake profile id in the path parameter with your profile id.
You can get your profile id from the response of step 4 (above) and update the path in this way:
```
localhost:4200/api/profiles/<YOUR PROFILE MONGODB OBJECTID>/tokens
```
**The response of `regenApiToken` contains the regenerated `apiToken`.** This token changes every time you call the API, and the previous value is no longer valid.


## 14. Check MQTT services local communication (optional)

With all services and Docker containers up and running, and existing devices in MongoDB, you can check MQTT communication with this Python script:

```bash
cd mqtt-communication-checker

# install dependencies
poetry install

# run this command
# ATTENTION: be sure to replace `API_TOKEN_ENCRYPTION_KEY` value with the one in `api-server/.env`
API_TOKEN_ENCRYPTION_KEY=cZk!tEefGGEwAK7PwKba3ZCBRbp6Vj8* poetry run mqtt-communication-checker
```

This script sends a value or command for every supported feature and verifies that MongoDB collections stored those values correctly.


## 15. Prepare firmwares


Start from this guide [HERE](firmwares-install.md).

To work locally, you need to replace the remote URLs with your local IP address.
First, check the IP address of your PC (based on your OS):

```bash
ip a
# or
ifconfig
# or (on windows)
ipconfig /a
```

You will get something like `192.168.?.?` or `10.x.x.x`, for example `192.168.1.7`.

You can then create a new file called `home-anthill/private-config/secrets-local.yaml` with this content:

```yaml
# development configuration used locally

wifi_ssid: '<YOUR WIFI SSID>'
wifi_password: '<YOUR WIFI PASSWORD>'

manufacturer: 'ks89'
api_token: '<PROFILE API TOKEN>' # from your local DB or via `regenApiToken` in Bruno

ssl: false

server_domain: '192.168.1.7' # your local IP discovered above
server_port: '4200'          # if you don't want to start `gui` you can also use '8082' without differences
server_path: '/admission/register'

mqtt_domain: '192.168.1.7' # your local IP discovered above
mqtt_port: 1883
mqtt_auth: true
mqtt_username: "device_pubsub"
mqtt_password: "DevicePassword1!"
```


## 16. Run the Android app on a virtual device (still under development)


1. Import the `app` repository in Android Studio.
2. If you followed the previous steps, you should already have the property files:
   - release.properties: used for Release variant
   - staging.properties: used for Staging variant
   - secrets.properties: used for Debug variant (default)
3. Copy the `google-services.json` (obtained from the Firebase Cloud Messaging platform in one of the previous steps) into the `./app` folder.
4. Create a virtual local device (for instance Pixel 9a API 37).
   <br/>
   <img src="https://raw.githubusercontent.com/home-anthill/docs/master/images/android/device-manager.png" alt="device manager">
   <br/>
5. Run all `home-anthill` services and docker containers
6. To let the virtual device reach your local server via `http://localhost:4200`, run:
  
   ```bash
   adb reverse tcp:4200 tcp:4200
   ```
7. Start the virtual device.
   <br/>
   <img src="https://raw.githubusercontent.com/home-anthill/docs/master/images/android/virtual-device.png" alt="virtual device">
   <br/>
8. Build the app with the Debug variant (default) on the virtual device.
9. On the virtual device, use the app to log in via GitHub. You should be redirected to GitHub and back to the app with a valid FCMToken.
