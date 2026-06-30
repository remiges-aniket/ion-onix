# Deploying a Seller App on the ION Network (BPP)

This guide walks you through everything needed to connect a seller application to the ION (Indonesia Open Network) — from creating an ngrok tunnel to publishing your product catalog and receiving buyer requests.

By the end of this guide your seller application will be live on the ION network and discoverable by buyers.

---

## What You Are Building

```
Buyer (anywhere on ION)
        │
        │  discover / select / init / confirm
        ▼
  ION Network (registry + gateway)
        │
        │  routes to your public URL
        ▼
  ngrok tunnel  ──►  BPP ONIX Adapter (your laptop)  ──►  Your Seller App
                ◄──                                   ◄──
```

The BPP ONIX Adapter handles all Beckn protocol complexity (signing, verification, routing). Your seller app only needs to receive HTTP requests and send HTTP responses.

---

## Prerequisites

- A laptop or server running **Linux / macOS / Windows WSL2**
- **Docker Desktop** (or Docker Engine + Compose plugin)
  - [Install Docker](https://docs.docker.com/engine/install/)
  - Verify: `docker --version` and `docker compose version`
- A free **ngrok account** — [sign up at ngrok.com](https://ngrok.com)
- A free **ION Central Devlabs account** — ask your ION network coordinator for the portal URL

---

## Step 1 — Get Your ngrok Authtoken and Static Domain

ngrok creates a stable public URL that lets the ION network reach your laptop. You need a **static domain** so your URL never changes between restarts.

### 1a. Get your authtoken

1. Log in to [dashboard.ngrok.com](https://dashboard.ngrok.com)
2. Go to **Your Authtoken** in the left sidebar
3. Copy the token — it looks like: `2abc123XYZ_abc123defghijklmnop456789`

### 1b. Claim a free static domain

1. In the ngrok dashboard, go to **Domains** in the left sidebar
2. Click **New Domain** — ngrok assigns you a free static subdomain
3. Your domain will look like: `clever-mongoose-freely.ngrok-free.app`
4. Copy this domain — you will use it as your **subscriber_id** on the ION network

> **Important**: Your ngrok static domain IS your identity on the ION network. Every message sent to you arrives at `https://your-domain.ngrok-free.app`. Keep this domain — changing it means re-registering on the network.

---

## Step 2 — Register Your Keys on ION Central

ION uses cryptographic key pairs to sign and verify every message. You must register your public key so other network participants can verify your messages.

1. Log in to the **ION Central Devlabs** portal
2. Navigate to the **Keys** tab
3. Click **Create New Key**
4. Fill in the form:
   - **Subscriber ID**: enter your ngrok static domain — the bare domain only, no `https://` (e.g. `clever-mongoose-freely.ngrok-free.app`)
   - **Role**: select `BPP`
   - **Network**: select the ION network you are joining
5. Click **Generate & Register**
6. Note down all four values from the success screen:

```
subscriber_id  :  clever-mongoose-freely.ngrok-free.app
keyId          :  clever-mongoose-freely.ngrok-free.app|76EU7hRSVY...
public_key     :  ByLFEBucCC4bWAS9bEJAiEfDKw...  (base64)
```

7. Click **Download Private Key** — save the file. Copy the base64 string inside:

```
private_key  :  aMHqwCRjww9u4TFD0CTT+gSNg3V4Ehw/ECwfZIgyEEg=  (base64, from downloaded file)
```

> **Never share your private key.** It cannot be recovered from the portal if lost.

---

## Step 3 — Clone the Repository

```bash
git clone https://github.com/indonesiaopennetwork/ion-onix.git
cd ion-onix/bppONIX
```

---

## Step 4 — Run the Configuration Script

The script patches all config files with your identity and sets up the ngrok tunnel.

```bash
chmod +x configure_onix.sh
./configure_onix.sh
```

You will see exactly this interaction in your terminal:

```
Welcome to BPP ONIX configuration!

Enter the values from the Keys tab of the ION Central Devlabs portal.
Your ngrok static domain is your subscriber_id (e.g. clever-mongoose-freely.ngrok-free.app).

subscriber_id (your ngrok static domain): clever-mongoose-freely.ngrok-free.app
private_key (base64, from downloaded key file): aMHqwCRjww9u4TFD0CTT+gSNg3V4Ehw/ECwfZIgyEEg=
public_key (base64, from ION Central Keys tab): ByLFEBucCC4bWAS9bEJAiEfDKw6QqI0HesI7SAALPN8=
keyId (from ION Central Keys tab): clever-mongoose-freely.ngrok-free.app|76EU7hRS...

This script will update:
  config/local-simple-bpp.yaml
  config/local-simple-routing-BPPReceiver.yaml

Do you want to proceed? (yes/no): yes
```

Next, the script asks for your seller app webhook URL. This is where the adapter forwards incoming Beckn requests (discover, select, init, etc.) to your application:

```
Seller app webhook URL [http://host.docker.internal:3002/api/webhook]:
```

- If your seller app is **running on this same machine**: press Enter to accept the default, adjusting the port and path if different.
- If your seller app is **running on a different server**: enter its full URL (e.g. `http://192.168.1.50:3002/api/webhook`).
- If you **do not have a seller app yet**: press Enter to use the default. A sample seller app is included and starts automatically with the adapter.

> **Why `host.docker.internal` instead of `localhost`?** Docker containers cannot reach the host machine via `localhost`. `host.docker.internal` is Docker's built-in hostname that resolves to the host machine from inside a container.

Finally, the script asks about ngrok:

```
ngrok provides a stable public URL so the ION network can reach your BPP adapter.
Get your authtoken at: https://dashboard.ngrok.com/get-started/your-authtoken
Do you need ngrok tunnel support? (yes/no): yes
ngrok authtoken (from https://dashboard.ngrok.com/get-started/your-authtoken): 2abc123XYZ_abc123defghijklmnop456789
ngrok static domain (from https://dashboard.ngrok.com/domains, e.g. clever-mongoose-freely.ngrok-free.app): clever-mongoose-freely.ngrok-free.app
```

> **Note**: After setup the script prints `Use 'https://clever-mongoose-freely.ngrok-free.app' as your subscriber_id`. This is a reminder for the ION Central registration — if you already completed Step 2, ignore this message.

The script writes a `.env` file with your ngrok credentials. Configuration is complete.

---

## Step 5 — Start the BPP Adapter

```bash
docker compose -f docker-compose-BPPAdapter.yml up --build -d
```

The first run takes a few minutes to download images. Subsequent starts are fast.

### Verify all services are running

```bash
docker compose -f docker-compose-BPPAdapter.yml ps
```

Expected output:

```
NAME                 STATUS
redis                running (healthy)
onix-bpp             running
seller-app           running
otel-collector-bpp   running
nginx-bpp            running
ngrok-bpp            running
```

> **seller-app** is the sample seller application bundled with this adapter. It auto-publishes a catalog on startup and responds to incoming Beckn requests with pre-packaged responses. You can replace it with your own application.

### Verify the ngrok tunnel is active

Open [http://localhost:4040](http://localhost:4040) in your browser. You should see the ngrok dashboard showing your tunnel URL and live request traffic.

Test your public endpoint is reachable:

```bash
curl -I https://clever-mongoose-freely.ngrok-free.app/bpp/receiver/
```

Any HTTP response (even 4xx) confirms the tunnel is working.

---

## Step 6 — Publish Your Product Catalog

The catalog publish step registers your products on the ION network catalog service so buyers can discover them via `discover` requests.

> **If you are using the bundled `seller-app`**: it auto-publishes its own catalog on startup. Check `docker logs seller-app` to confirm. You can skip this step or publish an additional catalog.

### Understanding the Publish Payload

A publish request has three sections in the message body:

- **catalogs[].id** — unique catalog ID across the entire ION network
- **resources** — your products (items for sale)
- **offers** — your selling terms (price, availability, policies) tied to resources

> **Critical — Global ID uniqueness**: All IDs (catalog, resources, offers, providers) must be **globally unique** across the ION network. Two sellers registering the same ID will cause `RESOURCE_OWNERSHIP_MISMATCH`. The safest convention is to prefix every ID with a short slug of your subscriber_id.
>
> Example: domain `clever-mongoose-freely.ngrok-free.app` → use prefix `cmf`

### Send the Publish Request

Replace `YOUR_SUBSCRIBER_ID` and `YOUR_PREFIX` with your values:

```bash
curl -X POST http://localhost:8082/bpp/caller/publish \
  -H "Content-Type: application/json" \
  -d '{
  "context": {
    "version": "2.0.0",
    "action": "catalog/publish",
    "timestamp": "2026-01-01T00:00:00.000Z",
    "messageId": "msg-001",
    "transactionId": "txn-pub-001",
    "bppId": "YOUR_SUBSCRIBER_ID",
    "bppUri": "https://YOUR_SUBSCRIBER_ID/bpp/receiver",
    "ttl": "PT30S",
    "networkId": "ion.id/ION-DC-Registry"
  },
  "message": {
    "catalogs": [
      {
        "id": "YOUR_PREFIX-catalog-001",
        "bppId": "YOUR_SUBSCRIBER_ID",
        "bppUri": "https://YOUR_SUBSCRIBER_ID/bpp/receiver",
        "descriptor": {
          "name": "My Store",
          "shortDesc": "Electronics and accessories"
        },
        "provider": {
          "id": "YOUR_PREFIX-provider-001",
          "descriptor": { "name": "My Store Name" }
        },
        "validity": {
          "startDate": "2026-01-01T00:00:00Z",
          "endDate": "2027-12-31T23:59:59Z"
        },
        "resources": [
          {
            "id": "YOUR_PREFIX-item-001",
            "descriptor": {
              "name": "Stainless Steel Flask 500ml",
              "shortDesc": "Double-walled vacuum insulated thermos flask"
            },
            "resourceAttributes": {
              "identity": { "brand": "MyBrand", "originCountry": "ID" },
              "physical": {
                "weight": { "unitCode": "G", "unitQuantity": 350 },
                "volume": { "unitCode": "ML", "unitQuantity": 500 }
              }
            }
          }
        ],
        "offers": [
          {
            "id": "YOUR_PREFIX-offer-001",
            "descriptor": { "name": "Stainless Steel Flask 500ml" },
            "resourceIds": ["YOUR_PREFIX-item-001"],
            "provider": {
              "id": "YOUR_PREFIX-provider-001",
              "descriptor": { "name": "My Store Name" }
            },
            "validity": {
              "startDate": "2026-01-01T00:00:00Z",
              "endDate": "2027-12-31T23:59:59Z"
            }
          }
        ]
      }
    ]
  }
}'
```

**Filled example** (prefix `cmf` for domain `clever-mongoose-freely.ngrok-free.app`):

```bash
curl -X POST http://localhost:8082/bpp/caller/publish \
  -H "Content-Type: application/json" \
  -d '{
  "context": {
    "version": "2.0.0",
    "action": "catalog/publish",
    "timestamp": "2026-01-01T00:00:00.000Z",
    "messageId": "msg-001",
    "transactionId": "txn-pub-001",
    "bppId": "clever-mongoose-freely.ngrok-free.app",
    "bppUri": "https://clever-mongoose-freely.ngrok-free.app/bpp/receiver",
    "ttl": "PT30S",
    "networkId": "ion.id/ION-DC-Registry"
  },
  "message": {
    "catalogs": [
      {
        "id": "cmf-catalog-001",
        "bppId": "clever-mongoose-freely.ngrok-free.app",
        "bppUri": "https://clever-mongoose-freely.ngrok-free.app/bpp/receiver",
        "descriptor": {
          "name": "CMF Store",
          "shortDesc": "Electronics and accessories"
        },
        "provider": {
          "id": "cmf-provider-001",
          "descriptor": { "name": "CMF Store" }
        },
        "validity": {
          "startDate": "2026-01-01T00:00:00Z",
          "endDate": "2027-12-31T23:59:59Z"
        },
        "resources": [
          {
            "id": "cmf-item-001",
            "descriptor": {
              "name": "Stainless Steel Flask 500ml",
              "shortDesc": "Double-walled vacuum insulated thermos flask"
            },
            "resourceAttributes": {
              "identity": { "brand": "MyBrand", "originCountry": "ID" },
              "physical": {
                "weight": { "unitCode": "G", "unitQuantity": 350 },
                "volume": { "unitCode": "ML", "unitQuantity": 500 }
              }
            }
          }
        ],
        "offers": [
          {
            "id": "cmf-offer-001",
            "descriptor": { "name": "Stainless Steel Flask 500ml" },
            "resourceIds": ["cmf-item-001"],
            "provider": {
              "id": "cmf-provider-001",
              "descriptor": { "name": "CMF Store" }
            },
            "validity": {
              "startDate": "2026-01-01T00:00:00Z",
              "endDate": "2027-12-31T23:59:59Z"
            }
          }
        ]
      }
    ]
  }
}'
```

### Check the on_publish Result

The adapter returns `200 OK` immediately (accepted for processing). The actual result comes asynchronously as an `on_publish` callback. Check adapter logs:

```bash
docker logs onix-bpp --tail 30
```

Successful registration:
```json
{
  "message": {
    "results": [{ "catalogId": "cmf-catalog-001", "status": "ACCEPTED" }]
  }
}
```

If you see `CATALOG_OWNERSHIP_MISMATCH` or `RESOURCE_OWNERSHIP_MISMATCH` — the IDs are already taken by another subscriber. Change your prefix and retry.

---

## Step 7 — Verify in the ngrok Web UI

Open [http://localhost:4040](http://localhost:4040). Under **Requests** you will see:

1. **Outgoing request** — the signed `catalog/publish` sent to `https://fabric.nfh.global/beckn/catalog`
2. **Incoming callback** — the `catalog/on_publish` result arriving at your BPP receiver

Click any request to inspect the full headers and body. This is the fastest way to debug message flows.

---

## Step 8 — Test with Postman (Optional)

A pre-built Postman collection is included at `testnet/postman/ION Retail.postman_collection.json`. It contains requests for publish, discover, select, init, confirm, and their callbacks.

### Import the collection

1. Open Postman → click **Import**
2. Select the file `testnet/postman/ION Retail.postman_collection.json`
3. The collection imports with a variable set — open it and update these variables before running:

| Variable | Default | Change to |
|----------|---------|-----------|
| `bppId` | `dc-bpp.ion.id` | Your ngrok domain (e.g. `clever-mongoose-freely.ngrok-free.app`) |
| `bppUri` | `http://onix-bpp:8082/bpp/receiver` | `https://YOUR_DOMAIN/bpp/receiver` |
| `bpp_adapter_url` | `http://localhost:8082/bpp/caller` | Keep as-is (correct for local) |
| `networkId` | `ion.id/ION-DC-Registry` | Keep as-is |

> **Note**: The `publish` request in the collection has hardcoded catalog/resource IDs (`catalog-hbo-001`, `item-flask-mh500-yellow`, etc.). Change `catalog.bppId` and `catalog.bppUri` inside the message body to your values, and change all IDs to your prefixed versions to avoid ownership conflicts.

---

## What Happens Next

Your catalog is now registered on the ION network. Buyers running a BAP adapter can:
- Run `discover` to find your products
- Run `select` to choose an item
- Run `init` / `confirm` to place an order

When a buyer sends a request that matches your catalog, the ION network routes it to your ngrok URL → your BPP adapter verifies and signs → forwards to your seller application.

---

## Common Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `CATALOG_OWNERSHIP_MISMATCH` | `catalog.id` already registered | Change `catalog.id` to use your unique prefix |
| `RESOURCE_OWNERSHIP_MISMATCH` | A `resource.id` or `offer.id` already registered | Change all resource/offer IDs to use your unique prefix |
| `ngrok-bpp` container exits | Wrong `NGROK_AUTHTOKEN` in `.env` | Re-run `configure_onix.sh` with the correct token |
| Signature errors in logs | `networkParticipant` / `subscriberId` mismatch | Re-run `configure_onix.sh` with the correct subscriber_id |
| `seller-app` fails to start | `NGROK_DOMAIN` not set in `.env` | Ensure ngrok setup completed in `configure_onix.sh` |

---

## Stopping the Adapter

```bash
docker compose -f docker-compose-BPPAdapter.yml down
```

## Re-configuring

Run `./configure_onix.sh` again at any time. Previous configs are saved in `config/backup/` with timestamps.
