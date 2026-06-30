#!/usr/bin/env bash
# Publish catalog to NfH via BPP Caller.
# Usage: ./publish.sh [BPP_CALLER_URL]
# Default target: http://localhost:8082/bpp/caller/publish
#
# To add a new product: copy one block inside "resources" and "offers",
# give them new unique IDs, then make sure offer.resourceIds matches the resource id.

BPP_CALLER="${1:-http://localhost:8082/bpp/caller}"
# Production defaults — uses the ngrok domain registered on NfH.
# For testnet: BPP_ID=dc-bpp.ion.id BPP_URI=http://onix-bpp:8082/bpp/receiver ./publish.sh
BPP_ID="${BPP_ID:-greedy-pony-bubbling.ngrok-free.dev}"
BPP_URI="${BPP_URI:-https://greedy-pony-bubbling.ngrok-free.dev/bpp/receiver}"
NETWORK_ID="${NETWORK_ID:-ion.id/ION-DC-Registry}"

TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
END_DATE=$(date -u -d "+1 year" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -v+1y +"%Y-%m-%dT%H:%M:%SZ")
MSG_ID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null || echo "$(date +%s)-msg")
TXN_ID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null || echo "$(date +%s)-txn")

curl -s -X POST "${BPP_CALLER}/publish" \
  -H "Content-Type: application/json" \
  -d @- <<EOF
{
  "context": {
    "version":       "2.0.0",
    "action":        "catalog/publish",
    "timestamp":     "${TS}",
    "messageId":     "${MSG_ID}",
    "transactionId": "${TXN_ID}",
    "bppId":         "${BPP_ID}",
    "bppUri":        "${BPP_URI}",
    "networkId":     "${NETWORK_ID}",
    "ttl":           "PT30S"
  },
  "message": {
    "catalogs": [
      {
        "id":     "catalog-ion-seller-001",
        "bppId":  "${BPP_ID}",
        "bppUri": "${BPP_URI}",
        "descriptor": {
          "name":      "ION Seller Store",
          "shortDesc": "General goods and electronics catalog"
        },
        "provider": {
          "id":         "provider-ion-seller-001",
          "descriptor": { "name": "ION Seller Store Jakarta" }
        },
        "validity": {
          "startDate": "${TS}",
          "endDate":   "${END_DATE}"
        },

        "resources": [
          {
            "id": "tushar-thermos-flask-500ml",
            "descriptor": {
              "name":      "Tushar Thermos Flask 500ml",
              "shortDesc": "Double-wall stainless steel vacuum flask, keeps drinks hot/cold 12 hours",
              "mediaFile": [
                {
                  "label":    "Product Image",
                  "mimeType": "image/jpeg",
                  "uri":      "https://tourism-bpp-infra2.becknprotocol.io/attachments/view/253.jpg"
                }
              ]
            },
            "resourceAttributes": {
              "@context": "https://raw.githubusercontent.com/beckn/local-retail/refs/heads/main/schema/RetailResource/v2.1/context.jsonld",
              "@type":    "RetailResource",
              "identity": { "brand": "TusharMax", "originCountry": "ID" },
              "physical": {
                "weight":     { "unitCode": "G",  "unitQuantity": 320 },
                "volume":     { "unitCode": "ML", "unitQuantity": 500 },
                "appearance": { "color": "Silver", "material": "Stainless Steel 304", "finish": "Matte" }
              }
            }
          },
          {
            "id": "item-backpack-20l",
            "descriptor": {
              "name":      "Hiking Backpack 20L",
              "shortDesc": "Lightweight 20L hiking backpack with rain cover"
            },
            "resourceAttributes": {
              "@context": "https://raw.githubusercontent.com/beckn/local-retail/refs/heads/main/schema/RetailResource/v2.1/context.jsonld",
              "@type":    "RetailResource",
              "identity": { "brand": "TrailGear", "originCountry": "ID" },
              "physical": {
                "weight":     { "unitCode": "G", "unitQuantity": 450 },
                "volume":     { "unitCode": "L", "unitQuantity": 20 },
                "appearance": { "color": "Black/Green", "material": "Polyester 300D" }
              }
            }
          }
        ],

        "offers": [
          {
            "id":          "offer-thermos-flask",
            "descriptor":  { "name": "Tushar Thermos Flask 500ml" },
            "resourceIds": ["tushar-thermos-flask-500ml"],
            "provider":    { "id": "provider-ion-seller-001", "descriptor": { "name": "ION Seller Store Jakarta" } },
            "validity":    { "startDate": "${TS}", "endDate": "${END_DATE}" },
            "offerAttributes": {
              "@context": "https://raw.githubusercontent.com/beckn/local-retail/refs/heads/main/schema/RetailOffer/v2.1/context.jsonld",
              "@type":    "RetailOffer",
              "policies": {
                "returns":      { "allowed": true, "window": "P7D",  "method": "SELLER_PICKUP" },
                "cancellation": { "allowed": true, "window": "PT2H", "cutoffEvent": "BEFORE_PACKING" }
              },
              "paymentConstraints": { "codAvailable": true },
              "serviceability": {
                "distanceConstraint": { "maxDistance": 30, "unit": "KM" },
                "timing": [
                  {
                    "daysOfWeek": ["MON","TUE","WED","THU","FRI","SAT","SUN"],
                    "timeRange":  { "start": "09:00", "end": "21:00" }
                  }
                ]
              }
            }
          },
          {
            "id":          "offer-backpack-20l",
            "descriptor":  { "name": "Hiking Backpack 20L" },
            "resourceIds": ["item-backpack-20l"],
            "provider":    { "id": "provider-ion-seller-001", "descriptor": { "name": "ION Seller Store Jakarta" } },
            "validity":    { "startDate": "${TS}", "endDate": "${END_DATE}" },
            "offerAttributes": {
              "@context": "https://raw.githubusercontent.com/beckn/local-retail/refs/heads/main/schema/RetailOffer/v2.1/context.jsonld",
              "@type":    "RetailOffer",
              "policies": {
                "returns":      { "allowed": true, "window": "P10D", "method": "SELLER_PICKUP" },
                "cancellation": { "allowed": true, "window": "PT4H", "cutoffEvent": "BEFORE_PACKING" }
              },
              "paymentConstraints": { "codAvailable": true },
              "serviceability": {
                "distanceConstraint": { "maxDistance": 30, "unit": "KM" },
                "timing": [
                  {
                    "daysOfWeek": ["MON","TUE","WED","THU","FRI","SAT"],
                    "timeRange":  { "start": "09:00", "end": "21:00" }
                  }
                ]
              }
            }
          }
        ]
      }
    ]
  }
}
EOF

echo ""
echo "Done. Check onix-bpp logs: docker logs onix-bpp -n 20"
