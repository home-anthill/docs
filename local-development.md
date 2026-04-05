# Local development setup

## 0. Install prerequisites

### Install GNU Make and cmake (both required)

On macOS install these with:
```bash
brew install make

# cmake is required by some rust dependencies
brew install cmake
```

Check if everything works correctly by running:
```bash
make -v
cmake --version
```


### Install `mosquitto_passwd` CLI (optional)

On macOS install it via [Homebrew](https://formulae.brew.sh/formula/mosquitto) with `brew install mosquitto`



## 1. Install Go


1. On macOS install it via [Homebrew](https://formulae.brew.sh/formula/go) with `brew install go`
2. Install [air](https://github.com/cosmtrek/air) to watch changes and auto-rebuild:

```bash
curl -sSfL https://raw.githubusercontent.com/cosmtrek/air/master/install.sh | sh -s -- -b $(go env GOPATH)/bin
```

Check if everything works correctly by running:
```bash
go version
air -v
```


## 2. Install Rust


Install Rust from [HERE](https://www.rust-lang.org/) with `rustup` script

Check if everything works correctly by running:
```bash
cargo --version
```


## 3. Install NodeJS


Install NodeJS LTS from [HERE](https://nodejs.org/)

Check if everything works correctly by running:
```bash
node -v
npm -v
```


## 4. Install Python and Poetry


Install Python 3.12 (or greater) from [HERE](https://www.python.org/downloads/)

Check if everything works correctly by running:
```bash
python3 --version
pip3 --version
```
then [install Poetry](https://python-poetry.org/docs/#installation)

Add the optional poetry shell plugin:
```bash
poetry self add poetry-plugin-shell
```


## 5. Install Android Studio and adb (only for Android app development)


On macOS install `adb` via [Homebrew](https://formulae.brew.sh/formula/android-platform-tools) with `brew install android-platform-tools`

Check if everything works correctly by running:
```bash
adb --version
```


## 6. Install `rabbitmqadmin v2` CLI (OPTIONAL)


This is **required only to run integration tests of `consumer` service**.
If you only want to run this project on your local PC **you can skip this step**.

On macOS install [rabbitmqadmin-ng](https://github.com/rabbitmq/rabbitmqadmin-ng) with `cargo install rabbitmqadmin`

You don't need to start RabbitMQ server locally, because we will use a Docker container.
Please check that local RabbitMQ server is not running:
```bash
brew services info --all
```

Check if everything works correctly by running:
```bash
rabbitmqadmin --help
# print the location of rabbitmqadmin executable
which rabbitmqadmin
```


## 7. Install and run Docker Desktop with docker compose


Install Docker Desktop from [HERE](https://www.docker.com/).

Then check if you can run these commands:

```bash
docker --version
docker compose version
```


## 8. Download repos


Run [this script](download-full-project.sh) in the location where you want to store `home-anthill` project.


## 9. Deploy local docker containers


1. Mosquitto

```bash
cd home-anthill/mosquitto
mkdir -p data
mkdir -p log

# build home-anthill mosquitto
docker build -t ks89/mosquitto .

docker run -it --name mosquitto \
    -p 1883:1883 \
    -p 9001:9001 \
    --rm \
    -v ./mosquitto-local-dev.conf:/mosquitto/config/mosquitto.conf:ro \
    -v ./data:/mosquitto/data \
    -v ./log:/mosquitto/log \
    -e MOSQUITTO_USERNAME=mosquser \
    -e MOSQUITTO_PASSWORD=Password1! \
    ks89/mosquitto
```
**Don't close this terminal window!**

2. RabbitMQ

Create a new terminal window and run:
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
      "write": "^ks89$",
      "read": ""
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

If you want, you can also restore a previous home-anthill Mongodb BSON backup :

```bash
# restore
mongorestore --uri="mongodb://localhost:27017" --nsInclude='*.*' ./backup-folder-with-prelude_json
# backup
mongodump --uri="mongodb://localhost:27017" --out ./backup-folder-with-prelude_json
```

4. Redis

Install Redis with persistence
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


## 10. Create 2 GitHub oAuth2 applications and update api-server .env file


1. GitHub oAuth2 app for website login

```bash
cd home-anthill/api-server
cp .env_template .env
```

You have to update `OAUTH2_CLIENTID` and `OAUTH2_SECRETID` properties in `.env` file.
These 2 values are the clientID and secretID of your github oAuth2 application, so you need to follow these steps:
- create an [oAuth2 app on Github](https://docs.github.com/en/developers/apps/building-oauth-apps/creating-an-oauth-app)
- go to the configuration page of your oAuth2 app and copy the Client ID (**this is the OAUTH2_CLIENTID value**)
- generate a new client secret and copy it to the `.env` file (**this is the OAUTH2_SECRETID value**)
- fill the `Homepage URL` input field: `http://localhost:8082`
- fill the `Authorization callback URL` input field: `http://localhost:8082/api/callback`
- save the oAuth2 app


2. GitHub oAuth2 app for Android login

```bash
cd home-anthill/app
cp secrets.defaults.properties secrets.properties
cp secrets.defaults.properties staging.properties
cp secrets.defaults.properties release.properties
```

You have to update `OAUTH2_APP_CLIENTID` and `OAUTH2_APP_SECRETID` properties in `.env` file.
These 2 values are the clientID and secretID of your github oAuth2 application, so you need to follow these steps:
- create an [oAuth2 app on Github](https://docs.github.com/en/developers/apps/building-oauth-apps/creating-an-oauth-app)
- go to the configuration page of your oAuth2 app and copy the Client ID (**this is the OAUTH2_APP_CLIENTID value**)
- generate a new client secret and copy it to the `.env` file (**this is the OAUTH2_APP_SECRETID value**)
- fill the `Homepage URL` input field: `http://localhost:8082`
- fill the `Authorization callback URL` input field: `http://localhost:8082/api/app_callback`
- save the oAuth2 app


## 11. Create a Firebase Cloud Messaging app


Create a new project at [Firebase console](https://console.firebase.google.com/) following these steps
1. ignore Google Analytics step
2. add an Android app to your new project
3. insert `eu.homeanthill` as package name, because it must match the name of the Android app
4. download the `google-services.json` file from 'Project Settings' -> 'General' (tab). This file will be required to build the Android app below and receive Push Notifications.
5. create the app
6. go to your 'Project Settings' -> 'Service account' (tab), select 'SDK Firebase Admin' and click
   on 'Generate a new private key' button to download the `serviceAccountKey.json` (this will be required to run `online-alarm` below to send Push Notifications).


## 12. Run all microservices

**With MongoDB, RabbitMQ, Mosquitto and Redis up and running**, you can start all microservices.

Open every microservice in a terminal tab (or multiple windows)

1. api-server

```bash
cd home-anthill/api-server
cp .env_template .env
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
# you should replace the template file with the one obtained above
cp serviceAccountKey.json_template serviceAccountKey.json
make deps
make run
```

10. gui

```bash
cd home-anthill/gui
npm i
# build command will copy the public folder into api-server to be exposed via `http://localhost:8082`
npm run build
# or, if you prefer the dev server at `http://localhost:4200`, you can use `npm start`
```

11. app

```bash
cd home-anthill/app
cp secrets.defaults.properties secrets.properties
cp secrets.defaults.properties staging.properties
cp secrets.defaults.properties release.properties
# you should replace the template file with the one obtained above
cp google-services.json_template app/google-services.json
```

12. login to the webapp with your GitHub account

If everything is up and running, **you should be able to access `http://localhost:8082`** from your favourite browser.
From `http://localhost:8082`, **log in with the GitHub account used to create the OAuth2 application**.
If you log in successfully, you will be redirected to the main app page.


## 13. Fill database with some data


At this point, you should be able to log in to the app, so the DB has a valid profile inside.
However, you don't have any other data yet.
You can navigate through the web app to add homes, rooms, and so on, but I prefer to show how to insert data manually via APIs using the free [Bruno](https://www.usebruno.com/) desktop app.


### Bruno

1. Install [Bruno](https://www.usebruno.com/) desktop app.
2. Open Bruno and click **Open Collection**, then select the `docs/bruno-collections` folder from this repository.
3. The collection includes requests for `api-server`, `admission`, and `online` endpoints.


### JWT

1. From your browser, login via GitHub at `http://localhost:8082`
2. Open the "Developer tools" and copy JWT `token` value (standard format `xxxx.xxxx.xxxx`) from "Local Storage" (in Chrome, you can find "Local Storage" under the "Application" tab).
3. In Bruno, open the collection's **Environments** (top-right), create or edit an environment and set `authToken` to the JWT value you copied.

4. Select the `getProfile` request (because it requires JWT authentication) from the collection and click **Send**. The response should be something like this:
```
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

5. You can try all other requests, but be sure to update **path** and **query parameters** with your object ids (taken from your local DB).
For example, **to get the `apiToken` (required in the next steps) you have to call `regenApiToken` changing the fake profile id from the path param with your profile id**
You can get your profile id from the response of step 4 (above) and update the path in this way:
```
localhost:8082/api/profiles/<YOUR PROFILE MONGODB OBJECTID>/tokens
```
**The response of `regenApiToken` contains the re-generated `apiToken`**. This token changes every time you call the API and the previous value won't be valid anymore.


## 14. Prepare firmwares


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

You'll get something like `192.168.?.?` or `10.x.x.x`, for example `192.168.1.7`.

In this way, you can create a new file called `private-config/secrets-local.yaml` with this content:

```yaml
# development configuration used locally

wifi_ssid: '<YOUR WIFI SSID>'
wifi_password: '<YOUR WIFI PASSWORD>'

manufacturer: 'ks89'
api_token: '<PROFILE API TOKEN>' # from your local DB or via `regenApiToken` in Bruno

ssl: false

server_domain: '192.168.1.7' # your local IP (for example 192.168.1.7)
server_port: '8082'
server_path: '/admission/register'

mqtt_domain: '192.168.1.7' # your local IP (for example 192.168.1.7)
mqtt_port: 1883
mqtt_auth: true
mqtt_username: "mosquser"
mqtt_password: "Password1!"
```


## 15. Run the Android app on a virtual device (still under development)


1. Import the `app` repository in Android Studio.
2. If you followed the previous steps, you should already have the property files:
   - release.properties: used for Release variant
   - staging.properties: used for Staging variant
   - secrets.properties: used for Debug variant (default)
3. Copy the `google-services.json` (obtained from the Firebase Cloud Messaging platform in one of the previous steps) into the `./app` folder.
4. Create a virtual local device (for instance Pixel 6A API 35).
   <br/>
   <img src="https://raw.githubusercontent.com/home-anthill/docs/master/images/android/device-manager.png" alt="device manager">
   <br/>
5. Start the virtual device.
   <br/>
   <img src="https://raw.githubusercontent.com/home-anthill/docs/master/images/android/virtual-device.png" alt="virtual device">
   <br/>
6. Build the app with the Debug variant (default) on the virtual device.
7. Run `api-server` and check if it's connected to the MongoDB Docker container started via `sharded-mongodb-compose` repository.
8. Run `online` and check if it's connected to the Redis Docker container.
9. To let the virtual device reach your local server via `http://localhost:8082`, run in a terminal:
   
   ```bash
   adb reverse tcp:8082 tcp:8082
   ```
   
10. On the virtual device, use the app to log in. You should be redirected to GitHub and back to the app with a valid FCMToken.