# BPP ONIX Adapter

The BPP (Beckn Provider Platform) ONIX Adapter connects your Seller Application to the ION (Indonesia Open Network). It handles the Beckn protocol layer on your behalf: verifying signatures on incoming requests, signing outgoing responses, routing messages to your seller application, and managing your network participant identity.

Buyer apps on the ION network send discovery and transaction requests to your adapter's public URL. The adapter forwards them to your seller application, receives your responses, signs them, and sends them back through the network.

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

By the end of this guide your seller application will be live on the ION network, discoverable by buyers, and able to publish a product catalog. The BPP ONIX Adapter handles all Beckn protocol complexity (signing, verification, routing) — your seller app only needs to receive HTTP requests and send HTTP responses.

## Prerequisites

- A laptop or server running **Linux / macOS / Windows WSL2**
- **Docker Desktop** (or Docker Engine + Compose plugin) — [Install Docker](https://docs.docker.com/engine/install/)
  - Verify: `docker --version` and `docker compose version`
- A free **ngrok account** with a static domain — [Sign up at ngrok.com](https://ngrok.com)
- An **ION Central Devlabs account** — to register your network participant keys (ask your ION network coordinator for the portal URL if you don't have one)

## Step 1 — Set Up Your ngrok Static Domain

ngrok creates a stable public URL that routes internet traffic to your laptop. The ION network uses this URL as your BPP's public address, so buyers on the network can find and reach your seller application. You need a **static domain** so your URL never changes between restarts.

1. Log in to [dashboard.ngrok.com](https://dashboard.ngrok.com).
2. Go to **Your Authtoken** in the left sidebar and copy the token — it looks like `2abc123XYZ_abc123defghijklmnop456789`.
3. Go to **Domains** in the left sidebar, click **New Domain**, and claim your free static domain — it will look like `clever-mongoose-freely.ngrok-free.app`.

> Your ngrok static domain becomes your `subscriber_id` — your unique identity on the ION network. Every message sent to you arrives at `https://your-domain.ngrok-free.app`. Keep this domain; changing it later means re-registering on the network.

## Step 2 — Register Your Keys on ION Central

ION uses cryptographic key pairs to sign and verify every message. You must register your public key so other network participants can verify your messages.

1. Log in to the **ION Central Devlabs** portal.
2. Open the **Keys** tab and click **Create New Key**.
3. Fill in the form:
   - **Subscriber ID** — your ngrok static domain, bare domain only, no `https://` (e.g. `clever-mongoose-freely.ngrok-free.app`)
   - **Role** — select `BPP`
   - **Network** — select the ION network you are joining
4. Click **Generate & Register**. Note down the four values from the success screen:

   ```
   subscriber_id  :  clever-mongoose-freely.ngrok-free.app
   keyId          :  clever-mongoose-freely.ngrok-free.app|76EU7hRSVY...
   ```

5. Click **Download Public & Private Key** and save the file — it cannot be recovered from the portal if lost. Copy the base64 string inside it:

   ```
   public_key     :  ByLFEBucCC4bWAS9bEJAiEfDKw...  (base64)
   private_key  :  aMHqwCRjww9u4TFD0CTT+gSNg3V4Ehw/ECwfZIgyEEg=  (base64, from downloaded file)
   ```

> **Never share your private key.**

## Step 3 — Clone the Repository

```bash
git clone https://github.com/indonesiaopennetwork/ion-onix.git
cd ion-onix/bppONIX
```

## Step 4 — Configure the Adapter

The script patches all config files with your identity and sets up the ngrok tunnel.

```bash
chmod +x configure_onix.sh
./configure_onix.sh
```

The script prompts for the following values:

| Prompt | Value |
|--------|-------|
| `subscriber_id` | Your ngrok static domain (e.g. `clever-mongoose-freely.ngrok-free.app`) |
| `private_key` | Base64 value from the private key file you downloaded |
| `public_key` | Base64 signing public key from the ION Central Keys tab |
| `keyId` | Key identifier from the ION Central Keys tab |
| Seller app webhook URL | Where the adapter routes incoming Beckn requests to your app (see note below) |
| ngrok authtoken | From the ngrok dashboard |
| ngrok static domain | The domain you claimed in Step 1 |

You will see an interaction like this in your terminal:

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

Next, the script asks for your **seller app webhook URL** — the endpoint on your application that receives Beckn requests (`discover`, `select`, `init`, `confirm`, etc.):

Note : Use `seller-app` or `host.docker.internal` based on where application is deployed.
```
Seller app webhook URL [http://host.docker.internal:3002/api/webhook]:
```

- If your seller app **runs on this same machine**: press Enter to accept the default, adjusting the port and path if different.
- If your seller app **runs on a different server**: enter its full URL (e.g. `http://192.168.1.50:3002/api/webhook`).
- If you **don't have a seller app yet**: press Enter to use the default. A sample seller app is included and starts automatically with the adapter.

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

The script creates a backup of your config before applying changes, and writes an `.env` file with your ngrok credentials.

## Step 5 — Start the Adapter

```bash
docker compose -f docker-compose-BPPAdapter.yml up --build -d
```

The first run downloads images and may take a few minutes. Subsequent starts are fast.

## Step 6 — Verify the Adapter Is Running

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

Open the ngrok web dashboard at [http://localhost:4040](http://localhost:4040) to confirm the tunnel is active and note your public URL. Test your public endpoint is reachable:

```bash
curl -I https://clever-mongoose-freely.ngrok-free.app/bpp/receiver/
```

Any HTTP response (even 4xx) confirms the tunnel is working. Your BPP is now reachable at `https://<your-ngrok-domain>/bpp/receiver/`.

## How Your Seller App Integrates

**Receiving requests**: The adapter verifies incoming Beckn request signatures, then forwards the request body to the URL you configured in Step 4 (the seller app webhook). Your app processes the request and responds.

**Sending responses**: Your seller app posts Beckn response messages to the adapter's **caller** endpoint:

```
POST http://localhost:8082/bpp/caller/<action>
```

Common response actions:

| Action | Sent in response to |
|--------|---------------------|
| `on_discover` | `discover` |
| `on_select` | `select` |
| `on_init` | `init` |
| `on_confirm` | `confirm` |
| `on_status` | `status` |
| `on_cancel` | `cancel` |

The adapter signs the response and routes it back to the originating buyer app through the ION network.

## Step 7 — Publish Your Product Catalog

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

## Step 8 — Verify in the ngrok Web UI

Open [http://localhost:4040](http://localhost:4040). Under **Requests** you will see:

1. **Outgoing request** — the signed `catalog/publish` sent to `https://fabric.nfh.global/beckn/catalog`
2. **Incoming callback** — the `catalog/on_publish` result arriving at your BPP receiver

Click any request to inspect the full headers and body. This is the fastest way to debug message flows.

## Step 9 — Test with Postman (Optional)

A pre-built Postman collection is included at the repository root: `testnet/postman/ION Retail.postman_collection.json` (one level above `bppONIX/`). It contains requests for publish, discover, select, init, confirm, and their callbacks.

### Import the collection

1. Open Postman → click **Import**.
2. Select the file `testnet/postman/ION Retail.postman_collection.json`.
3. The collection imports with a variable set — open it and update these variables before running:

| Variable | Default | Change to |
|----------|---------|-----------|
| `bppId` | `dc-bpp.ion.id` | Your ngrok domain (e.g. `clever-mongoose-freely.ngrok-free.app`) |
| `bppUri` | `http://onix-bpp:8082/bpp/receiver` | `https://YOUR_DOMAIN/bpp/receiver` |
| `bpp_adapter_url` | `http://localhost:8082/bpp/caller` | Keep as-is (correct for local) |
| `networkId` | `ion.id/ION-DC-Registry` | Keep as-is |

> **Note**: The `publish` request in the collection has hardcoded catalog/resource IDs (`catalog-hbo-001`, `item-flask-mh500-yellow`, etc.). Change `catalog.bppId` and `catalog.bppUri` inside the message body to your values, and change all IDs to your prefixed versions to avoid ownership conflicts.

## What Happens Next

Your catalog is now registered on the ION network. Buyers running a BAP adapter can:
- Run `discover` to find your products
- Run `select` to choose an item
- Run `init` / `confirm` to place an order

When a buyer sends a request that matches your catalog, the ION network routes it to your ngrok URL → your BPP adapter verifies and signs → forwards to your seller application.

## Stopping the Adapter

```bash
docker compose -f docker-compose-BPPAdapter.yml down
```

## Troubleshooting

**Containers fail to start**

Check for port conflicts (8082, 4321, 4322, 4040) and inspect logs:
```bash
docker compose -f docker-compose-BPPAdapter.yml logs
```

**ngrok tunnel not active**

Verify your `NGROK_AUTHTOKEN` and `NGROK_DOMAIN` are set in `.env`, then check `http://localhost:4040`.

**Requests not reaching your seller app**

Verify the webhook URL in `config/local-simple-routing-BPPReceiver.yaml` is reachable from inside the Docker network. Use `host.docker.internal` if your app runs on the host machine.

**Common errors during catalog publish**

| Error | Cause | Fix |
|-------|-------|-----|
| `CATALOG_OWNERSHIP_MISMATCH` | `catalog.id` already registered | Change `catalog.id` to use your unique prefix |
| `RESOURCE_OWNERSHIP_MISMATCH` | A `resource.id` or `offer.id` already registered | Change all resource/offer IDs to use your unique prefix |
| `ngrok-bpp` container exits | Wrong `NGROK_AUTHTOKEN` in `.env` | Re-run `configure_onix.sh` with the correct token |
| Signature errors in logs | `networkParticipant` / `subscriberId` mismatch | Re-run `configure_onix.sh` with the correct subscriber_id |
| `seller-app` fails to start | `NGROK_DOMAIN` not set in `.env` | Ensure ngrok setup completed in `configure_onix.sh` |

**Re-configuring**

Run `./configure_onix.sh` again at any time. Previous configs are saved in `config/backup/` with timestamps.

## Running BAP and BPP on the Same Machine

If you are running both BAP ONIX and BPP ONIX adapters on the same machine, the redis service must be shared. See the instructions in `bapONIX/README.md` under "Running BAP and BPP on the Same Machine".

## Next Steps

See `BuildingSellerApp.md` for the broader journey of building and testing a seller application end to end — from picking a use case through onboarding to production.
