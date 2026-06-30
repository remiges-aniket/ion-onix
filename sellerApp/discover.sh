#!/usr/bin/env bash
# Trigger a discover via BAP Caller.
# on_discover will be delivered to the buyer app (check buyer-app logs).
# Usage: ./discover.sh [BAP_CALLER_URL]
# Default target: http://localhost:8081/bap/caller/discover

BAP_CALLER="${1:-http://localhost:8081/bap/caller}"
BAP_ID="${BAP_ID:-dc-bap.ion.id}"
BAP_URI="${BAP_URI:-http://onix-bap:8081/bap/receiver}"
NETWORK_ID="${NETWORK_ID:-ion.id/ION-DC-Registry}"

TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
MSG_ID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null || echo "$(date +%s)-msg")
TXN_ID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null || echo "$(date +%s)-txn")

curl -s -X POST "${BAP_CALLER}/discover" \
  -H "Content-Type: application/json" \
  -d @- <<EOF
{
  "context": {
    "version":       "2.0.0",
    "action":        "discover",
    "timestamp":     "${TS}",
    "messageId":     "${MSG_ID}",
    "transactionId": "${TXN_ID}",
    "bapId":         "${BAP_ID}",
    "bapUri":        "${BAP_URI}",
    "networkId":     "${NETWORK_ID}",
    "ttl":           "PT30S"
  },
  "message": {
    "intent": {
      "descriptor": {
        "name": "thermos flask"
      }
    }
  }
}
EOF

echo ""
echo "ACK received above. on_discover will arrive async at buyer app."
echo "Watch: docker logs buyer-app -f --tail=30"
