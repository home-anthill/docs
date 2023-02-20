# Local development setup

## 0. Install some dependencies

### Install GNU Make (required)

On macOS install it via [Homebrew](https://formulae.brew.sh/formula/make) with `brew install make`

Check if everything works fine running:
```bash
make -v
```

### Install `rabbitmqadmin` CLI (optional)

This is **required only to run integration tests of `consumer` service**.
If you only want to run this project on your local PC **you can skip this step**.

On macOS install it via [Homebrew](https://formulae.brew.sh/formula/rabbitmq) with `brew install rabbitmq`

Check if everything works fine running:
```bash
/usr/local/sbin/rabbitmqadmin --version
```

You don't need to start RabbitMQ server, because we will use it as a Docker container.
Please check that RabbitMQ server is not running:
```bash
brew services info --all
```


## 1. Install Go


1. Install Go from [HERE](https://go.dev/)
2. Install [air](https://github.com/cosmtrek/air) to watch changes and auto-rebuild:

```bash
curl -sSfL https://raw.githubusercontent.com/cosmtrek/air/master/install.sh | sh -s -- -b $(go env GOPATH)/bin
```

Check if everything works fine running:
```bash
go version
air -v
```


## 2. Install Rust


Install Rust from [HERE](https://www.rust-lang.org/)

Check if everything works fine running:
```bash
cargo --version
```


## 3. Install NodeJS


Install NodeJS LTS from [HERE](https://nodejs.org/)

Check if everything works fine running:
```bash
node -v
npm -v
```


## 4. Install Python 3.10 (or greater)


Install Python 3 from [HERE](https://www.python.org/downloads/)

Check if everything works fine running:
```bash
python3 --version
pip3 --version
```


## 5. Install and run Docker Desktop


Install Docker Desktop from [HERE](https://www.docker.com/products/docker-desktop/)


## 6. Download repos


Run [this script](download-full-project.sh) in the location where you want to store `home-anthill` project.


## 7. Deploy local docker containers


1. Mosquitto

```bash
cd home-anthill/mosquitto
mosquitto_passwd -b -c password_file mosquser Password1!
cd ..
docker pull eclipse-mosquitto

docker run -it --name mosquitto -p 1883:1883 -p 9001:9001 --rm -v $PWD/mosquitto/mosquitto-nossl-auth.conf:/mosquitto/config/mosquitto.conf -v $PWD/mosquitto/password_file:/etc/mosquitto/password_file -v $PWD/mosquitto/data:/mosquitto/data -v $PWD/mosquitto/log:/mosquitto/log eclipse-mosquitto
```
**Don't close this terminal window!**

2. RabbitMQ

```bash
docker pull rabbitmq:management
docker run -d --name rabbitmq --hostname my-rabbit -p 15672:15672 -p 15671:15671 -p 5672:5672 rabbitmq:management
```

If you want you can access to the UI at `http://locahost:15672` and login with:
```
user: guest
password: guest
```

3. MongoDB

```bash
docker run -d --name mongodb -v ~/mongodb:/data/db -p 27017:27017 mongo:6
```


## 8. Create GitHub oAuth2 application


```bash
cd home-anthill
cp api-server/.env_template api-server/.env
```

You have to update `OAUTH2_CLIENTID` and `OAUTH2_SECRETID` properties in `.env` file.
These 2 values are the clientID and secretID of your github oAuth2 application, so you need to follow these steps:
1. create an [oAuth2 app on Github](https://docs.github.com/en/developers/apps/building-oauth-apps/creating-an-oauth-app)
2. go to the configuration page of your oAuth2 app and copy the Client ID (**this is the OAUTH2_CLIENTID value**)
3. generate a new client secret and copy it to the `.env` file (**this is the OAUTH2_SECRETID value**)
4. fill the `Homepage URL` input field: `http://localhost:8082`
5. fill the `Authorization callback URL` input field: `http://localhost:8082/api/callback`
6. save the oAuth2 app


## 9. Run all microservices

**With MongoDB, RabbitMQ and Mosquitto up and running**, you can start all microservices.

Open every microservice in a terminal tab (or multiple windows)

1. api-server

```bash
cd home-anthill/api-server
cp .env_template .env
make run
```

2. api-devices

```bash
cd home-anthill/api-devices
cp .env_template .env
make run
```

3. sensor register

```bash
cd home-anthill/register
cp .env_template .env
make run
```

4. producer

```bash
cd home-anthill/producer
cp .env_template .env
make run
```

5. consumer

```bash
cd home-anthill/consumer
cp .env_template .env
make run
```

6. gui

```bash
cd home-anthill/gui
npm i
npm run build
# or, if you prefer the dev server at `http://localhost:4200`, you can use `npm run start`
```

7. login to the webapp with your GitHub account

If everything is up and running, **you should be able to access at `http://localhost:8082`** from your favourite browser.
From `http://localhost:8082` **login with the GitHub account used to create the oAuth2 application**.
If you'll login successfully you'll be redirected to the main app page.


## 10. Fill database with some data


At this point, you should be able to login to the app, so the DB has a valid profile inside.
However, you don't have any other data.
You can navigate across the webapp to add homes, rooms and so on, but I prefer to show how to insert data manually via APIs using the free [Postman](https://www.postman.com/) desktop app.

### Postman


1. click on `cookies` on the bottom bar
2. enable the "Cookies interceptor" on Domains = `localhost`
<img src="https://raw.githubusercontent.com/home-anthill/docs/master/images/postman-cookies-interceptor.png" alt="Postman cookies interceptor">

3. Download and import in Postman this file `docs/postman-collections/postman_collection.json`

### JWT


1. From your browser, login via GitHub at `http://localhost:8082`
2. Open the "Developer tools" and copy JWT `token` value (standard format `xxxx.xxxx.xxxx`) from "Local Storage" (in Chrome, you can find "Local Storage" under the "Application" tab).
3. Paste this JWT into `authToken` value of collection `Variables` in Postman

<img src="https://raw.githubusercontent.com/home-anthill/docs/master/images/postman-variables-jwt.png" alt="Postman collection variable authToken">

4. Select `getProfile` request (because it requires JWT authentication) from the collection `api-server` and click on the `Send` button. The response should be something like this:
```
{
    "profile": {
        "id": "<YOUR PROFILE MONGODB OBJECTID>",
        "github": {
            "login": "<YOUR GITHUB NICKNAME>",
            "name": "<YOUR GITHUB NAME>",
            "email": "<YOUR GITHUB EMAIL>",
            "avatarURL": ""<YOUR GITHUB AVATAR URL>"
        }
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


## 11. Prepare devices and flash firmwares

Starts from this guide [HERE](devices-install.md)

To work locally, you need to change remote URLs with your local ip addresses
First check the IP address of your pc (based on your OS):

```bash
ip a
# or
ifconfig
# or (on windows)
ipconfig /a
```

You'll get something like `192.168.1.???`, for example `192.168.1.7`.

In this way, you can create a new file called `private-config/secrets-local.yaml` with this content:

```yaml
# development configuration used locally

wifi_ssid: '<YOUR WIFI SSID>'
wifi_password: '<YOUR WIFI PASSWORD>'

manufacturer: 'ks89'
api_token: '<PROFILE API TOKEN>' # from your local DB or via `regenApiToken` in Postman

ssl: false

server_domain: '192.168.1.7' # your local IP (for example 192.168.1.7)
server_port: '8082'
server_path: '/api/register'

mqtt_domain: '192.168.1.7' # your local IP (for example 192.168.1.7)
mqtt_port: 1883
mqtt_auth: true
mqtt_username: "mosquser"
mqtt_password: "Password1!"
```
