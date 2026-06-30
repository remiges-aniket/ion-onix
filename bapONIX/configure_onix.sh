#!/usr/bin/env bash

set -euo pipefail

CONFIG_FILE="config/local-simple-bap.yaml"
ROUTING_RECEIVER_FILE="config/local-simple-routing-BAPReceiver.yaml"
ROUTING_CALLER_FILE="config/local-simple-routing-BAPCaller.yaml"
ENV_FILE=".env"

# Return a YAML-safe single-quoted scalar.
yaml_quote() {
  local value=${1-}
  value=${value//\'/\'\'}
  printf "'%s'" "$value"
}


set_ngrok_compose_profile() {
  local authtoken=$1
  local domain=$2
  touch "$ENV_FILE"

  if grep -q '^COMPOSE_PROFILES=' "$ENV_FILE"; then
    sed -i.bak 's/^COMPOSE_PROFILES=.*/COMPOSE_PROFILES=ngrok/' "$ENV_FILE"
    rm -f "${ENV_FILE}.bak"
  else
    printf '\nCOMPOSE_PROFILES=ngrok\n' >> "$ENV_FILE"
  fi

  if grep -q '^NGROK_AUTHTOKEN=' "$ENV_FILE"; then
    sed -i.bak "s/^NGROK_AUTHTOKEN=.*/NGROK_AUTHTOKEN=${authtoken}/" "$ENV_FILE"
    rm -f "${ENV_FILE}.bak"
  else
    printf 'NGROK_AUTHTOKEN=%s\n' "$authtoken" >> "$ENV_FILE"
  fi

  if grep -q '^NGROK_DOMAIN=' "$ENV_FILE"; then
    sed -i.bak "s/^NGROK_DOMAIN=.*/NGROK_DOMAIN=${domain}/" "$ENV_FILE"
    rm -f "${ENV_FILE}.bak"
  else
    printf 'NGROK_DOMAIN=%s\n' "$domain" >> "$ENV_FILE"
  fi
}

unset_ngrok_compose_profile() {
  if [[ ! -f "$ENV_FILE" ]]; then
    return 0
  fi

  sed -i.bak '/^COMPOSE_PROFILES=ngrok$/d' "$ENV_FILE"
  sed -i.bak '/^NGROK_AUTHTOKEN=/d' "$ENV_FILE"
  sed -i.bak '/^NGROK_DOMAIN=/d' "$ENV_FILE"
  rm -f "${ENV_FILE}.bak"

  # Remove the file only if it is empty or contains whitespace only.
  if [[ ! -s "$ENV_FILE" ]] || ! grep -q '[^[:space:]]' "$ENV_FILE"; then
    rm -f "$ENV_FILE"
  fi
}


upsert_otelsetup_producer() {
  local config_file=$1
  local producer=$2
  local tmp_file

  tmp_file=$(mktemp "${config_file}.XXXXXX")

  awk -v producer="$(yaml_quote "$producer")" '
    function indent_of(line) {
      match(line, /^[[:space:]]*/)
      return RLENGTH
    }

    function print_missing_producer(    ind) {
      if (!in_otel_config || seen_producer) return

      ind = otel_config_child_indent
      if (ind == "") ind = otel_config_indent + 2

      print sprintf("%*sproducer: %s", ind, "", producer)
      seen_producer = 1
    }

    function print_missing_otel_config(    ind) {
      if (!in_otel || seen_otel_config) return

      ind = otel_child_indent
      if (ind == "") ind = otel_indent + 2

      print sprintf("%*sconfig:", ind, "")
      print sprintf("%*sproducer: %s", ind + 2, "", producer)
      seen_otel_config = 1
      seen_producer = 1
    }

    BEGIN {
      in_plugins = 0
      plugins_indent = -1
      in_otel = 0
      otel_indent = -1
      otel_child_indent = ""
      seen_otel_config = 0
      in_otel_config = 0
      otel_config_indent = -1
      otel_config_child_indent = ""
      seen_producer = 0
    }

    {
      line = $0
      indent = indent_of(line)
      nonblank = (line !~ /^[[:space:]]*$/)
      noncomment = (line !~ /^[[:space:]]*#/)

      if (in_otel_config && nonblank && noncomment && indent <= otel_config_indent) {
        print_missing_producer()
        in_otel_config = 0
        otel_config_indent = -1
        otel_config_child_indent = ""
      }

      if (in_otel && nonblank && noncomment && indent <= otel_indent) {
        print_missing_otel_config()
        in_otel = 0
        otel_indent = -1
        otel_child_indent = ""
        seen_otel_config = 0
        seen_producer = 0
      }

      if (in_plugins && nonblank && noncomment && indent <= plugins_indent) {
        in_plugins = 0
        plugins_indent = -1
      }

      if (!in_plugins && line ~ /^[[:space:]]*plugins:[[:space:]]*($|#)/) {
        in_plugins = 1
        plugins_indent = indent
        print line
        next
      }

      if (in_plugins && !in_otel && indent > plugins_indent && line ~ /^[[:space:]]*otelsetup:[[:space:]]*($|#)/) {
        in_otel = 1
        otel_indent = indent
        otel_child_indent = ""
        seen_otel_config = 0
        seen_producer = 0
        print line
        next
      }

      if (in_otel && nonblank && indent > otel_indent) {
        if (otel_child_indent == "" && line ~ /^[[:space:]]*[A-Za-z0-9_-]+[[:space:]]*:/) {
          otel_child_indent = indent
        }

        if (!in_otel_config && line ~ /^[[:space:]]*config:[[:space:]]*($|#)/) {
          in_otel_config = 1
          otel_config_indent = indent
          otel_config_child_indent = ""
          seen_otel_config = 1
          seen_producer = 0
          print line
          next
        }
      }

      if (in_otel_config && nonblank && indent > otel_config_indent) {
        if (otel_config_child_indent == "" && line ~ /^[[:space:]]*[A-Za-z0-9_-]+[[:space:]]*:/) {
          otel_config_child_indent = indent
        }

        if (line ~ /^[[:space:]]*producer[[:space:]]*:/) {
          print sprintf("%*sproducer: %s", indent, "", producer)
          seen_producer = 1
          next
        }
      }

      print line
    }

    END {
      print_missing_producer()
      print_missing_otel_config()
    }
  ' "$config_file" > "$tmp_file"

  mv "$tmp_file" "$config_file"
}

update_onix_config() {
  local config_file=$1
  local subscriber_id=$2
  local private_key=$3
  local public_key=$4
  local key_id=$5
  local tmp_file

  tmp_file=$(mktemp "${config_file}.XXXXXX")

  awk \
    -v subscriber_id="$(yaml_quote "$subscriber_id")" \
    -v private_key="$(yaml_quote "$private_key")" \
    -v public_key="$(yaml_quote "$public_key")" \
    -v key_id="$(yaml_quote "$key_id")" '
    function indent_of(line, prefix) {
      match(line, /^[[:space:]]*/)
      return RLENGTH
    }

    function print_missing_keys(    ind) {
      if (!in_cfg) return

      ind = child_indent
      if (ind == "") ind = cfg_indent + 2

      if (!seen_networkParticipant) print sprintf("%*snetworkParticipant: %s", ind, "", subscriber_id)
      if (!seen_keyId)              print sprintf("%*skeyId: %s", ind, "", key_id)
      if (!seen_signingPrivateKey)  print sprintf("%*ssigningPrivateKey: %s", ind, "", private_key)
      if (!seen_encrPrivateKey)     print sprintf("%*sencrPrivateKey: %s", ind, "", private_key)
      if (!seen_signingPublicKey)   print sprintf("%*ssigningPublicKey: %s", ind, "", public_key)
      if (!seen_encrPublicKey)      print sprintf("%*sencrPublicKey: %s", ind, "", public_key)
    }

    function reset_cfg_state() {
      in_cfg = 0
      cfg_indent = -1
      child_indent = ""
      seen_networkParticipant = 0
      seen_keyId = 0
      seen_signingPrivateKey = 0
      seen_encrPrivateKey = 0
      seen_signingPublicKey = 0
      seen_encrPublicKey = 0
    }

    BEGIN {
      in_key_manager = 0
      key_manager_indent = -1
      reset_cfg_state()
    }

    {
      line = $0
      indent = indent_of(line)
      nonblank = (line !~ /^[[:space:]]*$/)

      if (in_cfg && nonblank && indent <= cfg_indent && line !~ /^[[:space:]]*#/) {
        print_missing_keys()
        reset_cfg_state()
      }

      if (in_key_manager && nonblank && indent <= key_manager_indent && line !~ /^[[:space:]]*#/) {
        in_key_manager = 0
        key_manager_indent = -1
      }

      if (!in_key_manager && line ~ /^[[:space:]]*keyManager:[[:space:]]*($|#)/) {
        in_key_manager = 1
        key_manager_indent = indent
        print line
        next
      }

      if (in_key_manager && !in_cfg && line ~ /^[[:space:]]*config:[[:space:]]*($|#)/) {
        in_cfg = 1
        cfg_indent = indent
        child_indent = ""
        seen_networkParticipant = 0
        seen_keyId = 0
        seen_signingPrivateKey = 0
        seen_encrPrivateKey = 0
        seen_signingPublicKey = 0
        seen_encrPublicKey = 0
        print line
        next
      }

      if (in_cfg && nonblank && indent > cfg_indent) {
        if (child_indent == "" && line ~ /^[[:space:]]*[A-Za-z0-9_-]+[[:space:]]*:/) {
          child_indent = indent
        }

        if (line ~ /^[[:space:]]*networkParticipant[[:space:]]*:/) {
          print sprintf("%*snetworkParticipant: %s", indent, "", subscriber_id)
          seen_networkParticipant = 1
          next
        }
        if (line ~ /^[[:space:]]*keyId[[:space:]]*:/) {
          print sprintf("%*skeyId: %s", indent, "", key_id)
          seen_keyId = 1
          next
        }
        if (line ~ /^[[:space:]]*signingPrivateKey[[:space:]]*:/) {
          print sprintf("%*ssigningPrivateKey: %s", indent, "", private_key)
          seen_signingPrivateKey = 1
          next
        }
        if (line ~ /^[[:space:]]*encrPrivateKey[[:space:]]*:/) {
          print sprintf("%*sencrPrivateKey: %s", indent, "", private_key)
          seen_encrPrivateKey = 1
          next
        }
        if (line ~ /^[[:space:]]*signingPublicKey[[:space:]]*:/) {
          print sprintf("%*ssigningPublicKey: %s", indent, "", public_key)
          seen_signingPublicKey = 1
          next
        }
        if (line ~ /^[[:space:]]*encrPublicKey[[:space:]]*:/) {
          print sprintf("%*sencrPublicKey: %s", indent, "", public_key)
          seen_encrPublicKey = 1
          next
        }
      }

      # Update subscriberId at handler level (outside keyManager.config)
      if (line ~ /^[[:space:]]*subscriberId[[:space:]]*:/) {
        print sprintf("%*ssubscriberId: %s", indent, "", subscriber_id)
        next
      }

      print line
    }

    END {
      print_missing_keys()
    }
  ' "$config_file" > "$tmp_file"

  mv "$tmp_file" "$config_file"

  upsert_otelsetup_producer "$config_file" "$subscriber_id"
}

# Replace the url: value in a routing config file (all occurrences).
update_routing_url() {
  local config_file=$1
  local new_url=$2
  local tmp_file

  tmp_file=$(mktemp "${config_file}.XXXXXX")

  awk -v url="$new_url" '
    /^[[:space:]]*url[[:space:]]*:/ {
      match($0, /^[[:space:]]*/)
      print sprintf("%*surl: \"%s\"", RLENGTH, "", url)
      next
    }
    { print }
  ' "$config_file" > "$tmp_file"

  mv "$tmp_file" "$config_file"
}

echo "Welcome to BAP ONIX configuration!"
echo
echo "Enter the values from the Keys tab of the ION Central Devlabs portal."
echo "Your ngrok static domain is your subscriber_id (e.g. clever-mongoose-freely.ngrok-free.app)."
echo

read -rp "subscriber_id (your ngrok static domain): " SUBSCRIBER_ID
read -rp "private_key (base64, from downloaded key file): " PRIVATE_KEY
read -rp "public_key (base64, from ION Central Keys tab): " PUBLIC_KEY
read -rp "keyId (from ION Central Keys tab): " KEY_ID

echo
echo "This script will update:"
echo "  $CONFIG_FILE"
echo "  $ROUTING_RECEIVER_FILE"
echo

read -rp "Do you want to proceed? (yes/no): " CONFIRM

CONFIRM_LOWER=$(echo "$CONFIRM" | tr '[:upper:]' '[:lower:]')

case "$CONFIRM_LOWER" in
  yes|y)
    ;;
  *)
    echo "Operation cancelled."
    exit 0
    ;;
esac

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Error: Config file not found: $CONFIG_FILE"
  exit 1
fi

TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
BACKUP_DIR="config/backup"
mkdir -p "$BACKUP_DIR"

# Backup and update main ONIX config
BACKUP_FILE="${BACKUP_DIR}/local-simple-bap.${TIMESTAMP}.bak"
cp "$CONFIG_FILE" "$BACKUP_FILE"
update_onix_config "$CONFIG_FILE" "$SUBSCRIBER_ID" "$PRIVATE_KEY" "$PUBLIC_KEY" "$KEY_ID"

echo
echo "Main config backed up to:  $BACKUP_FILE"
echo "Main config updated:       $CONFIG_FILE"

# Buyer app webhook URL
echo
echo "The Buyer App Webhook URL is where the adapter forwards Beckn responses"
echo "(on_discover, on_select, etc.) to your buyer application."
echo "If your app runs on the same machine as Docker, use host.docker.internal"
echo "instead of localhost (e.g. http://host.docker.internal:3001/api/bap-webhook)."
echo
read -rp "Buyer app webhook URL [http://host.docker.internal:3001/api/bap-webhook]: " BUYER_APP_URL
BUYER_APP_URL="${BUYER_APP_URL:-http://host.docker.internal:3001/api/bap-webhook}"

if [[ -f "$ROUTING_RECEIVER_FILE" ]]; then
  ROUTING_BACKUP="${BACKUP_DIR}/local-simple-routing-BAPReceiver.${TIMESTAMP}.bak"
  cp "$ROUTING_RECEIVER_FILE" "$ROUTING_BACKUP"
  update_routing_url "$ROUTING_RECEIVER_FILE" "$BUYER_APP_URL"
  echo
  echo "Receiver routing backed up to: $ROUTING_BACKUP"
  echo "Receiver routing updated:      $ROUTING_RECEIVER_FILE"
fi

# ngrok tunnel setup
echo
echo "ngrok provides a stable public URL so the ION network can reach your BAP adapter."
echo "Get your authtoken at: https://dashboard.ngrok.com/get-started/your-authtoken"
read -rp "Do you need ngrok tunnel support? (yes/no): " NEED_NGROK
NEED_NGROK_LOWER=$(echo "$NEED_NGROK" | tr '[:upper:]' '[:lower:]')

case "$NEED_NGROK_LOWER" in
  yes|y)
    read -rp "ngrok authtoken (from https://dashboard.ngrok.com/get-started/your-authtoken): " NGROK_AUTHTOKEN
    read -rp "ngrok static domain (from https://dashboard.ngrok.com/domains, e.g. clever-mongoose-freely.ngrok-free.app): " NGROK_DOMAIN

    set_ngrok_compose_profile "$NGROK_AUTHTOKEN" "$NGROK_DOMAIN"

    echo
    echo "ngrok settings written to: $ENV_FILE"
    echo "Your BAP will be publicly accessible at: https://${NGROK_DOMAIN}"
    echo "Use 'https://${NGROK_DOMAIN}' as your subscriber_id when registering on ION Central."
    echo
    ;;
  *)
    echo "Continuing without ngrok support."
    unset_ngrok_compose_profile
    echo "ngrok profile removed from: $ENV_FILE"
    echo
    ;;
esac

echo "Run the adapter with:"
echo "  docker compose -f docker-compose-BAPAdapter.yml up --build -d"
