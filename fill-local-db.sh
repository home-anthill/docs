#!/usr/bin/env bash

set -euo pipefail

MOSQUITTO_HOST="${MOSQUITTO_HOST:-localhost}"
MOSQUITTO_PORT="${MOSQUITTO_PORT:-1883}"
REDIS_HOST="${REDIS_HOST:-localhost}"
REDIS_PORT="${REDIS_PORT:-6379}"
MONGODB_URL="${MONGODB_URL:-mongodb://localhost:27017}"

LOGIN_SERVER="${LOGIN_SERVER:-http://localhost:4200}"
ADMISSION_SERVER="${ADMISSION_SERVER:-http://localhost:8099}"
API_SERVER="${API_SERVER:-http://localhost:8082}"
API_DEVICES_HOST="${API_DEVICES_HOST:-localhost}"
API_DEVICES_PORT="${API_DEVICES_PORT:-50051}"
REGISTER_SERVER="${REGISTER_SERVER:-http://localhost:8000}"
ALARM_SERVER="${ALARM_SERVER:-http://localhost:8089}"

JWT=""

usage() {
  echo "Usage:"
  echo "  $0"
  echo
  echo "Examples:"
  echo "  $0"
  echo
  echo "The script opens the app OAuth2 login in your browser,"
  echo "waits for the issued app login code in MongoDB, exchanges it for a JWT,"
  echo "and continues without manual JWT or cookie input."
  echo
  echo "Override LOGIN_SERVER if the GUI dev server is not on http://localhost:4200."
  echo "Override MONGODB_URL if MongoDB is not on mongodb://localhost:27017."
}

confirm_or_exit() {
  local prompt="$1"
  local answer

  printf "%s [y/N]: " "$prompt"
  IFS= read -r answer

  case "$answer" in
    y|Y|yes|YES)
      ;;
    *)
      echo "Aborted"
      exit 1
      ;;
  esac
}

check_http() {
  local name="$1"
  local url="$2"

  if curl -fsS --max-time 3 "$url" >/dev/null 2>&1; then
    echo "OK: $name ($url)"
    return 0
  fi

  echo "ERROR: $name is not reachable at $url"
  return 1
}

check_tcp() {
  local name="$1"
  local host="$2"
  local port="$3"

  if command -v nc >/dev/null 2>&1; then
    if nc -z -w 3 "$host" "$port" >/dev/null 2>&1; then
      echo "OK: $name ($host:$port)"
      return 0
    fi
  elif (echo >/dev/tcp/"$host"/"$port") >/dev/null 2>&1; then
    echo "OK: $name ($host:$port)"
    return 0
  fi

  echo "ERROR: $name is not reachable at $host:$port"
  return 1
}

check_mongodb() {
  local mongo_url="${MONGODB_URL%/}/api-server"

  if ! command -v mongosh >/dev/null 2>&1; then
    echo "ERROR: mongosh is required to check MongoDB and read the OAuth app login code"
    return 1
  fi

  if mongosh --quiet "$mongo_url" --eval "db.adminCommand({ ping: 1 }).ok" >/dev/null 2>&1; then
    echo "OK: MongoDB ($mongo_url)"
    return 0
  fi

  echo "ERROR: MongoDB is not reachable at $mongo_url"
  return 1
}

preflight_checks() {
  local failed=0

  echo "Checking required local services..."

  check_mongodb || failed=1
  check_tcp "Mosquitto" "$MOSQUITTO_HOST" "$MOSQUITTO_PORT" || failed=1
  check_tcp "Redis" "$REDIS_HOST" "$REDIS_PORT" || failed=1
  check_http "GUI" "$LOGIN_SERVER" || failed=1
  check_http "api-server" "$API_SERVER/api/keepalive" || failed=1
  check_http "admission" "$ADMISSION_SERVER/admission/keepalive" || failed=1
  check_http "alarm" "$ALARM_SERVER/keepalive" || failed=1
  check_http "register" "$REGISTER_SERVER/keepalive" || failed=1
  check_tcp "api-devices gRPC" "$API_DEVICES_HOST" "$API_DEVICES_PORT" || failed=1

  if [ "$failed" -ne 0 ]; then
    echo
    echo "One or more required home-anthill services are not running."
    echo "Please run all home-anthill services, then run this script again."
    exit 1
  fi

  echo "All required services are reachable."
  echo
}

explain_and_confirm_login() {
  echo "Required local home-anthill services are reachable."
  echo "This script will now:"
  echo "1. Open the app OAuth2 login in your browser at $LOGIN_SERVER."
  echo "2. Wait for the one-time app login code in MongoDB."
  echo "3. Exchange that code for a JWT."
  echo "4. Regenerate and print your cleartext profile apiToken."
  echo "5. Create a sample home with rooms."
  echo "6. Ask again before registering and assigning sample devices."
  echo
  confirm_or_exit "Continue and open the browser login?"
}

base64url() {
  openssl base64 -A | tr '+/' '-_' | tr -d '='
}

new_pkce_verifier() {
  openssl rand -base64 96 | tr '+/' '-_' | tr -d '=[:space:]' | cut -c1-128
}

pkce_challenge() {
  printf '%s' "$1" | openssl dgst -sha256 -binary | base64url
}

open_browser() {
  local url="$1"

  if command -v open >/dev/null 2>&1; then
    open "$url" >/dev/null 2>&1
    return
  fi

  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$url" >/dev/null 2>&1
    return
  fi

  echo "Open this URL in your browser:"
  echo "$url"
}

read_app_code_from_mongo() {
  local challenge="$1"
  local mongo_url="${MONGODB_URL%/}/api-server"

  mongosh --quiet "$mongo_url" --eval "
    const cursor = db.getCollection('app_login_codes')
      .find({
        pkceCodeChallenge: '$challenge',
        usedAt: { \$exists: false },
        expiresAt: { \$gt: new Date() }
      })
      .sort({ createdAt: -1 })
      .limit(1);
    if (cursor.hasNext()) print(cursor.next().code);
  " 2>/dev/null | tail -n 1
}

wait_for_app_code() {
  local challenge="$1"
  local code=""

  if ! command -v mongosh >/dev/null 2>&1; then
    echo "mongosh is required for automatic browser login"
    echo "Install mongosh and run: $0"
    exit 1
  fi

  echo "Waiting for OAuth app code in MongoDB..." >&2
  for _ in $(seq 1 60); do
    code=$(read_app_code_from_mongo "$challenge")
    if [ -n "$code" ] && [ "$code" != "null" ]; then
      printf "\n" >&2
      printf "%s" "$code"
      return
    fi
    printf "." >&2
    sleep 1
  done

  printf "\n" >&2
  echo "Timed out waiting for OAuth app code" >&2
  exit 1
}

login_with_browser() {
  local verifier
  local challenge
  local app_state
  local login_url
  local code
  local exchange_response

  if ! command -v openssl >/dev/null 2>&1; then
    echo "openssl is required for browser login"
    exit 1
  fi

  verifier=$(new_pkce_verifier)
  challenge=$(pkce_challenge "$verifier")
  app_state=$(new_pkce_verifier)

  login_url="$LOGIN_SERVER/api/oauth/app/login?code_challenge=$challenge&code_challenge_method=S256&app_state=$app_state"

  echo "Opening browser OAuth2 login..."
  open_browser "$login_url"
  echo
  echo "Complete the GitHub login in the browser. The browser may return to the GUI login page."
  code=$(wait_for_app_code "$challenge")

  exchange_response=$(
    json_curl -X POST "$API_SERVER/api/oauth/app/exchange-code" \
      -d '{
        "code": "'"$code"'",
        "codeVerifier": "'"$verifier"'"
      }'
  )

  JWT=$(echo "$exchange_response" | jq -r '.token // empty')

  if [ -z "$JWT" ]; then
    echo "Unable to exchange OAuth app code for JWT"
    echo "$exchange_response"
    exit 1
  fi
}

auth_curl() {
  curl -s \
    -H "Authorization: Bearer $JWT" \
    "$@"
}

json_curl() {
  curl -s \
    -H "Content-Type: application/json" \
    "$@"
}

extract_id() {
  jq -r 'first(.. | objects | .id? // empty) // empty'
}

if [ "$#" -ne 0 ]; then
  usage
  exit 1
fi

preflight_checks
explain_and_confirm_login
login_with_browser

echo "Regenerating profile apiToken..."

PROFILE_ID=$(
  auth_curl "$API_SERVER/api/profile" \
  | jq -r '.id // .profile.id'
)

if [ -z "$PROFILE_ID" ] || [ "$PROFILE_ID" = "null" ]; then
  echo "Unable to read profile id"
  exit 1
fi

API_TOKEN=$(
  auth_curl -X POST "$API_SERVER/api/profiles/$PROFILE_ID/tokens" \
    -H "Content-Type: application/json" \
    -d '{}' \
  | jq -r 'first(.. | .apiToken? // empty) // empty'
)

if [ -z "$API_TOKEN" ]; then
  echo "Unable to regenerate apiToken"
  exit 1
fi

echo "Regenerated profile apiToken:"
echo "$API_TOKEN"
echo

echo "Creating home and rooms..."

HOME_JSON=$(
  auth_curl -X POST "$API_SERVER/api/homes" \
    -H "Content-Type: application/json" \
    -d '{
      "name": "My Home",
      "location": "My Location",
      "rooms": [
        { "name": "Living Room", "floor": 0 },
        { "name": "Kitchen", "floor": 0 },
        { "name": "Bedroom", "floor": 1 },
        { "name": "Bathroom", "floor": 1 }
      ]
    }'
)

HOME_ID=$(echo "$HOME_JSON" | jq -r '.id // .home.id')
ROOM_IDS=()
while IFS= read -r room_id; do
  ROOM_IDS+=("$room_id")
done < <(echo "$HOME_JSON" | jq -r '(.rooms // .home.rooms)[] | .id')

if [ -z "$HOME_ID" ] || [ "$HOME_ID" = "null" ] || [ "${#ROOM_IDS[@]}" -eq 0 ]; then
  echo "Unable to read created home or room ids"
  echo "$HOME_JSON"
  exit 1
fi

echo "Profile apiToken regenerated and home created:"
echo "Home id: $HOME_ID"
echo "Rooms created: ${#ROOM_IDS[@]}"
echo
confirm_or_exit "Continue with sample device registration and room assignment?"

DEVICE_IDS=()
DEVICE_MODELS=()

register_device() {
  local mac="$1"
  local model="$2"
  local features="$3"
  local response
  local device_id

  echo "Registering $model..."

  response=$(
    json_curl -X POST "$ADMISSION_SERVER/admission/register" \
      -d '{
        "mac": "'"$mac"'",
        "manufacturer": "ks89",
        "model": "'"$model"'",
        "apiToken": "'"$API_TOKEN"'",
        "features": '"$features"'
      }'
  )

  device_id=$(echo "$response" | extract_id)

  if [ -z "$device_id" ]; then
    device_id=$(
      auth_curl "$API_SERVER/api/devices" \
      | jq -r 'first(.. | objects | select(.mac? == "'"$mac"'") | .id) // empty'
    )
  fi

  if [ -z "$device_id" ]; then
    echo "Unable to find registered device id for $model ($mac)"
    echo "$response"
    exit 1
  fi

  DEVICE_IDS+=("$device_id")
  DEVICE_MODELS+=("$model")
}

register_device "AA:99:77:22:12:AA" "dht-light" '[
  { "type": "sensor", "name": "temperature", "enable": true, "order": 1, "unit": "\u00b0C", "spec": { "format": "float", "min": -40, "max": 80, "step": 0.05 } },
  { "type": "sensor", "name": "humidity", "enable": true, "order": 2, "unit": "%", "spec": { "format": "float", "min": 0, "max": 100, "step": 2.5 } },
  { "type": "sensor", "name": "light", "enable": true, "order": 3, "unit": "lux", "spec": { "format": "int", "min": 0, "max": 40000, "step": 1 } },
  { "type": "sensor", "name": "online", "enable": true, "order": 4, "unit": "-", "spec": { "format": "bool" } }
]'

register_device "BB:99:77:22:12:04" "airquality-pir" '[
  { "type": "sensor", "name": "motion", "enable": true, "order": 1, "unit": "-", "spec": { "format": "bool" } },
  { "type": "sensor", "name": "airquality", "enable": true, "order": 2, "unit": "-", "spec": { "format": "int", "min": 0, "max": 3, "step": 1 } },
  { "type": "sensor", "name": "online", "enable": true, "order": 3, "unit": "-", "spec": { "format": "bool" } }
]'

register_device "CC:99:77:22:12:05" "barometer" '[
  { "type": "sensor", "name": "airpressure", "enable": true, "order": 1, "unit": "hPa", "spec": { "format": "float", "min": 300, "max": 1200, "step": 0.0002 } },
  { "type": "sensor", "name": "temperature", "enable": true, "order": 2, "unit": "\u00b0C", "spec": { "format": "float", "min": -40, "max": 85, "step": 0.5 } },
  { "type": "sensor", "name": "online", "enable": true, "order": 3, "unit": "-", "spec": { "format": "bool" } }
]'

register_device "EE:02:55:99:99:01" "ac-lg" '[
  { "type": "controller", "name": "on", "enable": true, "order": 1, "unit": "-", "spec": { "format": "bool" } },
  { "type": "controller", "name": "setpoint", "enable": true, "order": 2, "unit": "\u00b0C", "spec": { "format": "float", "min": 16, "max": 30, "step": 1 } },
  { "type": "controller", "name": "mode", "enable": true, "order": 3, "unit": "-", "spec": { "format": "list", "list": [ { "value": 0, "text": "Cool" }, { "value": 1, "text": "Dry" }, { "value": 2, "text": "Fan" }, { "value": 3, "text": "Auto" }, { "value": 5, "text": "Heat" } ] } },
  { "type": "controller", "name": "fanSpeed", "enable": true, "order": 4, "unit": "-", "spec": { "format": "list", "list": [ { "value": 10, "text": "Max" }, { "value": 2, "text": "Med" }, { "value": 3, "text": "Min" }, { "value": 4, "text": "Auto" } ] } },
  { "type": "sensor", "name": "online", "enable": true, "order": 5, "unit": "-", "spec": { "format": "bool" } }
]'

register_device "FF:02:55:99:99:02" "ac-beko" '[
  { "type": "controller", "name": "on", "enable": true, "order": 1, "unit": "-", "spec": { "format": "bool" } },
  { "type": "controller", "name": "setpoint", "enable": true, "order": 2, "unit": "\u00b0C", "spec": { "format": "float", "min": 17, "max": 30, "step": 1 } },
  { "type": "controller", "name": "mode", "enable": true, "order": 3, "unit": "-", "spec": { "format": "list", "list": [ { "value": 0, "text": "Cool" }, { "value": 1, "text": "Dry" }, { "value": 2, "text": "Auto" }, { "value": 3, "text": "Heat" }, { "value": 5, "text": "Fan" } ] } },
  { "type": "controller", "name": "fanSpeed", "enable": true, "order": 4, "unit": "-", "spec": { "format": "list", "list": [ { "value": 10, "text": "Auto0" }, { "value": 1, "text": "Max" }, { "value": 2, "text": "Med" }, { "value": 0, "text": "Min" }, { "value": 5, "text": "Auto" } ] } },
  { "type": "sensor", "name": "online", "enable": true, "order": 5, "unit": "-", "spec": { "format": "bool" } }
]'

register_device "00:90:33:77:22:03" "thermostat" '[
  { "type": "controller", "name": "setpoint", "enable": true, "order": 1, "unit": "\u00b0C", "spec": { "format": "float", "min": 10, "max": 30, "step": 0.5 } },
  { "type": "controller", "name": "tolerance", "enable": true, "order": 2, "unit": "\u00b0C", "spec": { "format": "float", "min": 0, "max": 10, "step": 0.5 } },
  { "type": "sensor", "name": "temperature", "enable": true, "order": 3, "unit": "\u00b0C", "spec": { "format": "float", "min": -40, "max": 200, "step": 0.01 } },
  { "type": "sensor", "name": "mode", "enable": true, "order": 4, "unit": "-", "spec": { "format": "int", "min": -1, "max": 2, "step": 1 } },
  { "type": "sensor", "name": "online", "enable": true, "order": 5, "unit": "-", "spec": { "format": "bool" } }
]'

UNASSIGNED_INDEX=$((RANDOM % ${#DEVICE_IDS[@]}))

echo "Assigning devices to random rooms in home $HOME_ID..."

for i in "${!DEVICE_IDS[@]}"; do
  device_id="${DEVICE_IDS[$i]}"
  model="${DEVICE_MODELS[$i]}"

  if [ "$i" -eq "$UNASSIGNED_INDEX" ]; then
    echo "Leaving $model ($device_id) unassigned"
    continue
  fi

  room_id="${ROOM_IDS[$((RANDOM % ${#ROOM_IDS[@]}))]}"

  auth_curl -X PUT "$API_SERVER/api/devices/$device_id" \
    -H "Content-Type: application/json" \
    -d '{
      "name": "'"$model"'",
      "homeId": "'"$HOME_ID"'",
      "roomId": "'"$room_id"'"
    }' > /dev/null

  echo "Assigned $model ($device_id) to room $room_id"
done

echo "Done"
