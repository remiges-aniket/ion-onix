#!/usr/bin/env bash

set -euo pipefail

CONFIG_FILE="config/local-simple-bpp.yaml"
LOCAL_TUNNEL_CONFIG_FILE="config/loca_lt_config.yaml"
ENV_FILE=".env"

# Return a YAML-safe single-quoted scalar.
yaml_quote() {
  local value=${1-}
  value=${value//\'/\'\'}
  printf "'%s'" "$value"
}

upsert_local_tunnel_subdomain() {
  local config_file=$1
  local subdomain=$2
  local tmp_file

  tmp_file=$(mktemp "${config_file}.XXXXXX")

  if [[ -f "$config_file" ]]; then
    awk -v value="$(yaml_quote "$subdomain")" '
      BEGIN { found = 0 }
      /^[[:space:]]*subdomain[[:space:]]*:/ {
        print "subdomain: " value
        found = 1
        next
      }
      { print }
      END {
        if (!found) {
          print "subdomain: " value
        }
      }
    ' "$config_file" > "$tmp_file"
  else
    printf 'subdomain: %s\n' "$(yaml_quote "$subdomain")" > "$tmp_file"
  fi

  mv "$tmp_file" "$config_file"
}


set_local_tunnel_compose_profile() {
  touch "$ENV_FILE"

  if grep -q '^COMPOSE_PROFILES=' "$ENV_FILE"; then
    sed -i.bak 's/^COMPOSE_PROFILES=.*/COMPOSE_PROFILES=localtunnel/' "$ENV_FILE"
    rm -f "${ENV_FILE}.bak"
  else
    printf '\nCOMPOSE_PROFILES=localtunnel\n' >> "$ENV_FILE"
  fi
}

unset_local_tunnel_compose_profile() {
  if [[ ! -f "$ENV_FILE" ]]; then
    return 0
  fi

  sed -i.bak '/^COMPOSE_PROFILES=localtunnel$/d' "$ENV_FILE"
  rm -f "${ENV_FILE}.bak"

  # Remove the file only if it is empty or contains whitespace only.
  if [[ ! -s "$ENV_FILE" ]] || ! grep -q '[^[:space:]]' "$ENV_FILE"; then
    rm -f "$ENV_FILE"
  fi
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

      print line
    }

    END {
      print_missing_keys()
    }
  ' "$config_file" > "$tmp_file"

  mv "$tmp_file" "$config_file"
}

echo "Welcome to ONIX configuration!!"
echo "Enter the ONIX configuration details. These will be available in the keys section of the ION Central Devlabs portal."
echo

read -rp "subscriber_id: " SUBSCRIBER_ID
read -rp "private_key: " PRIVATE_KEY
read -rp "public_key: " PUBLIC_KEY
read -rp "keyId: " KEY_ID

echo
echo "This script will modify ONIX configuration at:"
echo "  config/*.yml"
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
BACKUP_FILE="config/local-simple-bpp.${TIMESTAMP}.bak"

cp "$CONFIG_FILE" "$BACKUP_FILE"

update_onix_config "$CONFIG_FILE" "$SUBSCRIBER_ID" "$PRIVATE_KEY" "$PUBLIC_KEY" "$KEY_ID"

echo
echo "Current configuration has been backed up to:"
echo "  $BACKUP_FILE"
echo
echo "Configuration has been updated successfully in:"
echo "  $CONFIG_FILE"

echo "Local tunnel support lets a server running on your laptop receive traffic from the public internet through a stable tunnel URL."
read -rp "Do you need local tunnel support? (yes/no): " NEED_LOCAL_TUNNEL
NEED_LOCAL_TUNNEL_LOWER=$(echo "$NEED_LOCAL_TUNNEL" | tr '[:upper:]' '[:lower:]')

case "$NEED_LOCAL_TUNNEL_LOWER" in
  yes|y)
    read -rp "local tunnel subdomain: " LOCAL_TUNNEL_SUBDOMAIN

    mkdir -p config

    upsert_local_tunnel_subdomain "$LOCAL_TUNNEL_CONFIG_FILE" "$LOCAL_TUNNEL_SUBDOMAIN"

    set_local_tunnel_compose_profile

    echo
    echo "Local tunnel configuration has been updated in:"
    echo "  $LOCAL_TUNNEL_CONFIG_FILE"
    echo "Docker Compose profile has been set in:"
    echo "  $ENV_FILE"
    echo
    ;;
  *)
    echo "Continuing without local tunnel support."

    unset_local_tunnel_compose_profile

    echo "Docker Compose local tunnel profile has been removed from:"
    echo "  $ENV_FILE"
    echo
    ;;
esac

echo "Use ' docker compose -f docker-compose-BPPAdapter.yaml up --build -d' to run the BPP ONIX adapter"