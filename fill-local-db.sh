#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <JWT> <COOKIE_VALUE>"
  echo 'Example: ./fill-local-db.sh "JWT" "COOKIE_VALUE"'
  exit 1
fi

JWT="$1"
COOKIE="$2"

API_SERVER="${API_SERVER:-http://localhost:8082}"
ADMISSION_SERVER="${ADMISSION_SERVER:-http://localhost:8099}"

auth_curl() {
  curl -s \
    -H "Authorization: Bearer $JWT" \
    --cookie "oauth_session=$COOKIE" \
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
  { "type": "sensor", "name": "temperature", "enable": true, "order": 1, "unit": "\u00b0C" },
  { "type": "sensor", "name": "humidity", "enable": true, "order": 2, "unit": "%" },
  { "type": "sensor", "name": "light", "enable": true, "order": 3, "unit": "lux" }
]'

register_device "BB:99:77:22:12:04" "airquality-pir" '[
  { "type": "sensor", "name": "motion", "enable": true, "order": 1, "unit": "-" },
  { "type": "sensor", "name": "airquality", "enable": true, "order": 2, "unit": "-" }
]'

register_device "CC:99:77:22:12:05" "barometer" '[
  { "type": "sensor", "name": "airpressure", "enable": true, "order": 1, "unit": "hPa" }
]'

register_device "DD:99:77:22:12:06" "power-outage" '[
  { "type": "sensor", "name": "online", "enable": true, "order": 1, "unit": "-" }
]'

register_device "EE:02:55:99:99:01" "ac-lg" '[
  { "type": "controller", "name": "on", "enable": true, "order": 1, "unit": "-" },
  { "type": "controller", "name": "setpoint", "enable": true, "order": 2, "unit": "\u00b0C" },
  { "type": "controller", "name": "mode", "enable": true, "order": 3, "unit": "-" },
  { "type": "controller", "name": "fanSpeed", "enable": true, "order": 4, "unit": "-" }
]'

register_device "FF:02:55:99:99:02" "ac-beko" '[
  { "type": "controller", "name": "on", "enable": true, "order": 1, "unit": "-" },
  { "type": "controller", "name": "setpoint", "enable": true, "order": 2, "unit": "\u00b0C" },
  { "type": "controller", "name": "mode", "enable": true, "order": 3, "unit": "-" },
  { "type": "controller", "name": "fanSpeed", "enable": true, "order": 4, "unit": "-" }
]'

register_device "00:90:33:77:22:03" "thermostat" '[
  { "type": "controller", "name": "setpoint", "enable": true, "order": 1, "unit": "\u00b0C" },
  { "type": "controller", "name": "tolerance", "enable": true, "order": 2, "unit": "\u00b0C" },
  { "type": "sensor", "name": "temperature", "enable": true, "order": 3, "unit": "\u00b0C" }
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
