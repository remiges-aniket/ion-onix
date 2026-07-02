# BAP ONIX Adapter

The BAP (Beckn Application Platform) ONIX Adapter connects your Buyer Application to the ION (Indonesia Open Network). It handles the Beckn protocol layer on your behalf: signing outgoing requests, verifying signatures on incoming responses, routing messages through the network, and managing your network participant identity.

Your buyer application talks to the adapter over a local HTTP connection. The adapter handles all ION network communication.

```
Your Buyer App  ──POST──►  BAP ONIX Adapter  ──►  ION Gateway  ──►  BPP ONIX Adapters (sellers)
               ◄──webhook──                  ◄──               ◄──
```

By the end of this guide your buyer application will be live on the ION network and able to discover, select, and transact with any registered seller. The BAP ONIX Adapter handles all Beckn protocol complexity (signing, routing, registry lookups) — your buyer app only needs to send HTTP requests to the adapter and receive callbacks at a webhook URL.

## Prerequisites

- A laptop or server running **Linux / macOS / Windows WSL2**
- **Docker Desktop** (or Docker Engine + Compose plugin) — [Install Docker](https://docs.docker.com/engine/install/)
  - Verify: `docker --version` and `docker compose version`
- A free **ngrok account** with a static domain — [Sign up at ngrok.com](https://ngrok.com)
- An **ION Central Devlabs account** — to register your network participant keys (ask your ION network coordinator for the portal URL if you don't have one)

## Step 1 — Set Up Your ngrok Static Domain

ngrok creates a stable public URL that routes internet traffic to your laptop. The ION network uses this URL as your BAP's public address to deliver callback messages. You need a **static domain** so your URL never changes between restarts.

1. Log in to [dashboard.ngrok.com](https://dashboard.ngrok.com).
2. Go to **Your Authtoken** in the left sidebar and copy the token — it looks like `2abc123XYZ_abc123defghijklmnop456789`.
3. Go to **Domains** in the left sidebar, click **New Domain**, and claim your free static domain — it will look like `purple-dragon-quietly.ngrok-free.app`.

> Your ngrok static domain becomes your `subscriber_id` — your unique identity on the ION network. Seller responses (`on_discover`, `on_select`, etc.) are delivered to `https://your-domain.ngrok-free.app/bap/receiver/`. Keep this domain stable; changing it later means re-registering on the network.

## Step 2 — Register Your Keys on ION Central

ION uses cryptographic key pairs to sign and verify every message. You must register your public key so sellers can verify your requests.

1. Log in to the **ION Central Devlabs** portal.
2. Open the **Keys** tab and click **Create New Key**.
3. Fill in the form:
   - **Subscriber ID** — your ngrok static domain, bare domain only, no `https://` (e.g. `purple-dragon-quietly.ngrok-free.app`)
   - **Role** — select `BAP`
   - **Network** — select the ION network you are joining
4. Click **Generate & Register**. Note down the four values from the success screen:

   ```
   subscriber_id  :  purple-dragon-quietly.ngrok-free.app
   keyId          :  purple-dragon-quietly.ngrok-free.app|76EU8EFszF...
   ```

5. Click **Download Public & Private Key** and save the file — it cannot be recovered from the portal if lost. Copy the base64 string inside it:

   ```
   public_key     :  H07+Y1NUMFflt6HafVRChIEKw...  (base64)
   private_key  :  Evr3oR6wpOZMas/A8sLEcuQCQ5o8Qa5yg8TOT5Jygeo=  (base64, from downloaded file)
   ```

> **Never share your private key.**

## Step 3 — Clone the Repository

```bash
git clone https://github.com/indonesiaopennetwork/ion-onix.git
cd ion-onix/bapONIX
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
| `subscriber_id` | Your ngrok static domain (e.g. `purple-dragon-quietly.ngrok-free.app`) |
| `private_key` | Base64 value from the private key file you downloaded |
| `public_key` | Base64 signing public key from the ION Central Keys tab |
| `keyId` | Key identifier from the ION Central Keys tab |
| Buyer app webhook URL | Where the adapter routes Beckn callbacks to your app (see note below) |
| ngrok authtoken | From the ngrok dashboard |
| ngrok static domain | The domain you claimed in Step 1 |

You will see an interaction like this in your terminal:

```
Welcome to BAP ONIX configuration!

Enter the values from the Keys tab of the ION Central Devlabs portal.
Your ngrok static domain is your subscriber_id (e.g. clever-mongoose-freely.ngrok-free.app).

subscriber_id (your ngrok static domain): purple-dragon-quietly.ngrok-free.app
private_key (base64, from downloaded key file): Evr3oR6wpOZMas/A8sLEcuQCQ5o8Qa5yg8TOT5Jygeo=
public_key (base64, from ION Central Keys tab): H07+Y1NUMFflt6HafVRChIEKw+2ohdzks9J+OSb2lwE=
keyId (from ION Central Keys tab): purple-dragon-quietly.ngrok-free.app|76EU8EFszF...

This script will update:
  config/local-simple-bap.yaml
  config/local-simple-routing-BAPReceiver.yaml

Do you want to proceed? (yes/no): yes
```

Next, the script asks for your **buyer app webhook URL** — the endpoint on your application that receives Beckn responses (`on_discover`, `on_select`, `on_init`, etc.):

```
Buyer app webhook URL [http://host.docker.internal:3001/api/bap-webhook]:
```

- If your buyer app **runs on this same machine**: press Enter to accept the default, adjusting the port and path if different.
- If your buyer app **runs on a different server**: enter its full URL.
- If you **don't have a buyer app yet**: press Enter. Responses will still be visible in adapter logs and the ngrok web UI.

> **Why `host.docker.internal` instead of `localhost`?** Docker containers cannot reach the host machine via `localhost`. `host.docker.internal` is Docker's built-in hostname that resolves to the host machine from inside a container.

Finally, the script asks about ngrok:

```
ngrok provides a stable public URL so the ION network can reach your BAP adapter.
Get your authtoken at: https://dashboard.ngrok.com/get-started/your-authtoken
Do you need ngrok tunnel support? (yes/no): yes
ngrok authtoken (from https://dashboard.ngrok.com/get-started/your-authtoken): 2abc123XYZ_abc123defghijklmnop456789
ngrok static domain (from https://dashboard.ngrok.com/domains, e.g. clever-mongoose-freely.ngrok-free.app): purple-dragon-quietly.ngrok-free.app
```

> **Note**: After setup the script prints `Use 'https://purple-dragon-quietly.ngrok-free.app' as your subscriber_id`. This is a reminder for the ION Central registration — if you already completed Step 2, ignore this message.

The script creates a backup of your config before applying changes, and writes an `.env` file with your ngrok credentials.

## Step 5 — Start the Adapter

```bash
docker compose -f docker-compose-BAPAdapter.yml up --build -d
```

The first run downloads images and may take a few minutes. Subsequent starts are fast.

## Step 6 — Verify the Adapter Is Running

```bash
docker compose -f docker-compose-BAPAdapter.yml ps
```

Expected output:

```
NAME                STATUS
onix-bap            running
otel-collector-bap  running
nginx-bap           running
ngrok-bap           running
```

> **Need Redis?** The BAP adapter requires Redis for caching. The `redis` service is commented out in `docker-compose-BAPAdapter.yml` by default because it's normally provided by the BPP stack when both adapters run on the same machine (see "Running BAP and BPP on the Same Machine" below). If you are running the BAP standalone, uncomment the `redis` service before starting.

Open the ngrok web dashboard at [http://localhost:4041](http://localhost:4041) to confirm the tunnel is active and note your public URL.

> The BAP ngrok dashboard runs on port **4041** (not 4040 — that's the BPP).

Your BAP is now reachable at `https://<your-ngrok-domain>/bap/receiver/`.

## Sending Beckn Messages

Your buyer application sends Beckn requests to the adapter's **caller** endpoint:

```
POST http://localhost:8081/bap/caller/<action>
```

Common actions:

| Action | Description |
|--------|-------------|
| `discover` | Search for products or services |
| `select` | Select an item from search results |
| `init` | Initiate an order |
| `confirm` | Confirm the order |
| `status` | Check order status |
| `cancel` | Cancel an order |

The adapter signs the request, looks up the destination BPP via the ION registry, forwards the message, and routes the response back to your buyer app webhook.

## Step 7 — Discover Products

The `discover` action searches the ION network for products matching your intent. Your request goes to the ION gateway which fans it out to all registered sellers; each matching seller responds asynchronously with their catalog.

> **ION Gateway**: The BAP adapter routes `discover` requests to the configured ION gateway (`config/local-simple-routing-BAPCaller.yaml`). The gateway address is pre-configured. Contact your ION network coordinator if discover requests are not reaching sellers.

### Send a discover request

```bash
curl -X POST http://localhost:8081/bap/caller/discover \
  -H "Content-Type: application/json" \
  -d '{
  "context": {
    "version": "2.0.0",
    "action": "discover",
    "timestamp": "2026-01-01T00:00:00.000Z",
    "messageId": "msg-discover-001",
    "transactionId": "txn-001",
    "bapId": "YOUR_SUBSCRIBER_ID",
    "bapUri": "https://YOUR_SUBSCRIBER_ID/bap/receiver",
    "ttl": "PT30S",
    "networkId": "ion.id/ION-DC-Registry"
  },
  "message": {
    "intent": {
      "textSearch": "flask"
    }
  }
}'
```

**Filled example** (for domain `purple-dragon-quietly.ngrok-free.app`):

```bash
curl -X POST http://localhost:8081/bap/caller/discover \
  -H "Content-Type: application/json" \
  -d '{
  "context": {
    "version": "2.0.0",
    "action": "discover",
    "timestamp": "2026-01-01T00:00:00.000Z",
    "messageId": "msg-discover-001",
    "transactionId": "txn-001",
    "bapId": "purple-dragon-quietly.ngrok-free.app",
    "bapUri": "https://purple-dragon-quietly.ngrok-free.app/bap/receiver",
    "ttl": "PT30S",
    "networkId": "ion.id/ION-DC-Registry"
  },
  "message": {
    "intent": {
      "textSearch": "flask"
    }
  }
}'
```

You can also filter results by item attribute:

```json
"intent": {
  "textSearch": "flask",
  "filters": {
    "type": "jsonpath",
    "expression": "$[?(@.resourceAttributes.identity.brand == 'MyBrand')]"
  }
}
```

The adapter returns `200 OK` immediately. Seller responses arrive asynchronously.

### See the on_discover response

**Option A — Adapter logs** (quickest):

```bash
docker logs onix-bap --tail 50 -f
```

Look for log entries containing `"action":"on_discover"`.

**Option B — ngrok web UI** (most detail):

Open [http://localhost:4041](http://localhost:4041). Under **Requests** you will see each incoming `on_discover` callback with full request/response bodies.

**Option C — Your buyer app webhook** (production flow):

If you configured a webhook URL in Step 4, each `on_discover` is POSTed directly to your application.

### Sample on_discover response

```json
{
  "context": {
    "action": "on_discover",
    "bppId": "clever-mongoose-freely.ngrok-free.app",
    "bppUri": "https://clever-mongoose-freely.ngrok-free.app/bpp/receiver"
  },
  "message": {
    "catalogs": [
      {
        "id": "cmf-catalog-001",
        "bppId": "clever-mongoose-freely.ngrok-free.app",
        "resources": [
          {
            "id": "cmf-item-001",
            "descriptor": { "name": "Stainless Steel Flask 500ml" }
          }
        ],
        "offers": [
          {
            "id": "cmf-offer-001",
            "resourceIds": ["cmf-item-001"],
            "provider": { "id": "cmf-provider-001" }
          }
        ]
      }
    ]
  }
}
```

From the `on_discover` response, note down:
- `context.bppId` and `context.bppUri` — the seller's identity
- `offers[].id` — the offer ID you want to select
- `offers[].provider.id` — the provider ID
- `resources[].id` — the resource (item) ID

You will use all of these in the `select` request.

> **Critical — bppUri must come from on_discover, not from the gateway**: The discover request goes through the ION gateway (`34.47.138.217.sslip.io`). Do **not** use the gateway URL as `bppUri` in select. The `bppUri` for select must be the BPP's own endpoint URL, taken from `context.bppUri` in the `on_discover` callback. It will look like `https://some-seller-domain.ngrok-free.app/bpp/receiver` — always including the `/bpp/receiver` path. Using the gateway URL will cause: `failed to determine route: could not determine destination for endpoint 'select': neither request contained a BPP URI`.

## Step 8 — Select a Product

The `select` action tells a specific seller you are interested in one of their offers.

**Important**: The Beckn v2 protocol uses `message.contract` (not `message.order`) for all transactional actions. The contract contains three sections:
- `participants` — the seller (provider) and buyer
- `commitments` — what is being ordered (offer + item + quantity)
- `performance` — how and where to fulfill (delivery details)

Use the **same `transactionId`** as the discover request to link the conversation.

### Send a select request

```bash
curl -X POST http://localhost:8081/bap/caller/select \
  -H "Content-Type: application/json" \
  -d '{
  "context": {
    "version": "2.0.0",
    "action": "select",
    "timestamp": "2026-01-01T00:00:01.000Z",
    "messageId": "msg-select-001",
    "transactionId": "txn-001",
    "bapId": "YOUR_BAP_SUBSCRIBER_ID",
    "bapUri": "https://YOUR_BAP_SUBSCRIBER_ID/bap/receiver",
    "bppId": "BPP_ID_FROM_ON_DISCOVER",
    "bppUri": "BPP_URI_FROM_ON_DISCOVER",
    "ttl": "PT30S",
    "networkId": "ion.id/ION-DC-Registry"
  },
  "message": {
    "contract": {
      "status": { "code": "DRAFT" },
      "participants": [
        {
          "id": "PROVIDER_ID_FROM_ON_DISCOVER",
          "descriptor": { "name": "Seller Store Name" }
        },
        {
          "id": "buyer-001",
          "descriptor": { "name": "Your Name" }
        }
      ],
      "commitments": [
        {
          "id": "commitment-001",
          "status": { "descriptor": { "code": "DRAFT" } },
          "resources": [
            { "id": "RESOURCE_ID_FROM_ON_DISCOVER", "quantity": 1 }
          ],
          "offer": {
            "id": "OFFER_ID_FROM_ON_DISCOVER",
            "resourceIds": ["RESOURCE_ID_FROM_ON_DISCOVER"],
            "descriptor": { "name": "Item Name" },
            "provider": {
              "id": "PROVIDER_ID_FROM_ON_DISCOVER",
              "descriptor": { "name": "Seller Store Name" }
            }
          }
        }
      ],
      "performance": [
        {
          "id": "perf-001",
          "status": { "code": "PENDING" },
          "commitmentIds": ["commitment-001"]
        }
      ]
    }
  }
}'
```

**Filled example** using values from the sample on_discover above:

```bash
curl -X POST http://localhost:8081/bap/caller/select \
  -H "Content-Type: application/json" \
  -d '{
  "context": {
    "version": "2.0.0",
    "action": "select",
    "timestamp": "2026-01-01T00:00:01.000Z",
    "messageId": "msg-select-001",
    "transactionId": "txn-001",
    "bapId": "purple-dragon-quietly.ngrok-free.app",
    "bapUri": "https://purple-dragon-quietly.ngrok-free.app/bap/receiver",
    "bppId": "clever-mongoose-freely.ngrok-free.app",
    "bppUri": "https://clever-mongoose-freely.ngrok-free.app/bpp/receiver",
    "ttl": "PT30S",
    "networkId": "ion.id/ION-DC-Registry"
  },
  "message": {
    "contract": {
      "status": { "code": "DRAFT" },
      "participants": [
        {
          "id": "cmf-provider-001",
          "descriptor": { "name": "CMF Store" }
        },
        {
          "id": "buyer-001",
          "descriptor": { "name": "Your Name" }
        }
      ],
      "commitments": [
        {
          "id": "commitment-001",
          "status": { "descriptor": { "code": "DRAFT" } },
          "resources": [
            { "id": "cmf-item-001", "quantity": 1 }
          ],
          "offer": {
            "id": "cmf-offer-001",
            "resourceIds": ["cmf-item-001"],
            "descriptor": { "name": "Stainless Steel Flask 500ml" },
            "provider": {
              "id": "cmf-provider-001",
              "descriptor": { "name": "CMF Store" }
            }
          }
        }
      ],
      "performance": [
        {
          "id": "perf-001",
          "status": { "code": "PENDING" },
          "commitmentIds": ["commitment-001"]
        }
      ]
    }
  }
}'
```

### See the on_select response

```bash
docker logs onix-bap --tail 50 -f
```

Look for `"action":"on_select"`. A successful response from the seller contains the contract with confirmed pricing and availability. You can also see it in the ngrok web UI at [http://localhost:4041](http://localhost:4041) — the `on_select` callback appears as an incoming request.

## Step 9 — Test with Postman (Recommended)

A pre-built Postman collection is included at the repository root: `testnet/postman/ION Retail.postman_collection.json` (one level above `bapONIX/`). It contains complete working payloads for the entire transaction flow.

### Import the collection

1. Open Postman → click **Import**.
2. Select the file `testnet/postman/ION Retail.postman_collection.json`.
3. The collection imports with a pre-configured variable set.

### Update collection variables

Open the collection → **Variables** tab and update these before running:

| Variable | Default | Change to |
|----------|---------|-----------|
| `bapId` | `dc-bap.ion.id` | Your BAP ngrok domain (e.g. `purple-dragon-quietly.ngrok-free.app`) |
| `bapUri` | `http://onix-bap:8081/bap/receiver` | `https://YOUR_BAP_DOMAIN/bap/receiver` |
| `bppId` | `dc-bpp.ion.id` | The BPP's ngrok domain from the `on_discover` response |
| `bppUri` | `http://onix-bpp:8082/bpp/receiver` | `https://BPP_DOMAIN/bpp/receiver` |
| `bap_adapter_url` | `http://localhost:8081/bap/caller` | Keep as-is |
| `networkId` | `ion.id/ION-DC-Registry` | Keep as-is |

### Run requests in order

1. **discover** — search for products; check logs/ngrok for `on_discover` response
2. **select** — select an item from the on_discover results; check for `on_select`
3. **init** — initiate the order with delivery details
4. **confirm** — confirm the order

> The collection uses `message.contract` (the correct Beckn v2 schema) for select, init, and confirm — more complete than the minimal curl examples above. Use the Postman collection for a full end-to-end test.

## Continuing the Transaction (Optional)

| Action | What it does | Adapter endpoint |
|--------|-------------|-----------------|
| `init` | Initiate the order, share delivery details | `POST http://localhost:8081/bap/caller/init` |
| `confirm` | Confirm and place the order | `POST http://localhost:8081/bap/caller/confirm` |
| `status` | Check order status | `POST http://localhost:8081/bap/caller/status` |
| `cancel` | Cancel the order | `POST http://localhost:8081/bap/caller/cancel` |

All use the same `transactionId` and `message.contract` structure. Refer to the Postman collection for complete payload examples.

## Viewing All Traffic

**Adapter logs**:

```bash
docker logs onix-bap --tail 100 -f

# Filter to a specific transaction
docker logs onix-bap 2>&1 | grep "txn-001"
```

**ngrok web UI**: Open [http://localhost:4041](http://localhost:4041). Every outgoing request and every incoming callback is visible with full body inspection. This is the fastest way to see and debug message flows.

## Stopping the Adapter

```bash
docker compose -f docker-compose-BAPAdapter.yml down
```

## Troubleshooting

**Containers fail to start**

Check for port conflicts (8081, 4317, 4318, 4041) and inspect logs:
```bash
docker compose -f docker-compose-BAPAdapter.yml logs
```

**ngrok tunnel not active**

Verify your `NGROK_AUTHTOKEN` and `NGROK_DOMAIN` are set in `.env`, then check `http://localhost:4041`.

**Responses not reaching your buyer app**

Verify the webhook URL in `config/local-simple-routing-BAPReceiver.yaml` is reachable from inside the Docker network. Use `host.docker.internal` if your app runs on the host machine.

**Common errors during discover / select**

| Error | Cause | Fix |
|-------|-------|-----|
| `on_discover` never arrives | ngrok tunnel not active | Check [http://localhost:4041](http://localhost:4041) |
| `on_discover` arrives but is empty | No matching seller catalog on network | Confirm a BPP has published a matching catalog; check `networkId` matches |
| Signature validation failed | `subscriber_id` mismatch in config | Re-run `configure_onix.sh` with the correct subscriber_id |
| `bapId not registered` | Keys not yet in ION registry | Complete Step 2; wait a few minutes for registry sync |
| `failed to determine route … neither request contained a BPP URI` | `bppUri` in select context is wrong or missing `/bpp/receiver` | Copy `context.bppUri` exactly from the `on_discover` response; it must end with `/bpp/receiver`, not the gateway IP |
| Select returns empty `on_select` | Wrong message structure in select body | Ensure you are using `message.contract`, not `message.order` |
| Adapter fails to start | Redis not running | Uncomment the `redis` service in `docker-compose-BAPAdapter.yml` |

**Re-configuring**

Run `./configure_onix.sh` again at any time. Previous configs are saved in `config/backup/` with timestamps.

## Running BAP and BPP on the Same Machine

If you are running both BAP ONIX and BPP ONIX adapters on the same machine:

1. Configure and start the BAP adapter first (`docker compose -f docker-compose-BAPAdapter.yml up --build -d`).
2. Configure the BPP adapter.
3. In `bppONIX/docker-compose-BPPAdapter.yml`, remove the `redis` service entirely and mark the `beckn_network` as external:
   ```yaml
   networks:
     beckn_network:
       external: true
   ```
4. Start the BPP adapter.
5. When shutting down, bring down BPP first, then BAP.

## Next Steps

See `BuildingBuyerApp.md` for the broader journey of building and testing a buyer application end to end — from picking a use case through onboarding to production.
