# BAP ONIX Adapter

The BAP (Beckn Application Platform) ONIX Adapter connects your Buyer Application to the ION (Indonesia Open Network). It handles the Beckn protocol layer on your behalf: signing outgoing requests, verifying signatures on incoming responses, routing messages through the network, and managing your network participant identity.

Your buyer application talks to the adapter over a local HTTP connection. The adapter handles all ION network communication.

```
Buyer App  ──POST──►  BAP ONIX Adapter  ──►  ION Network  ──►  BPP ONIX Adapter  ──►  Seller App
           ◄──webhook──                  ◄──                ◄──
```

## Prerequisites

- **Docker** and **Docker Compose** — [Install Docker](https://docs.docker.com/engine/install/)
- **ngrok account** with a free static domain — [Sign up at ngrok.com](https://ngrok.com)
- **ION Central Devlabs account** — to register your network participant keys

## Step 1 — Set Up Your ngrok Static Domain

ngrok creates a stable public URL that routes internet traffic to your laptop. The ION network uses this URL as your BAP's public address to deliver callback messages.

1. Sign up or log in to [ngrok.com](https://ngrok.com).
2. Go to **Dashboard → Domains** and claim your free static domain (e.g. `clever-mongoose-freely.ngrok-free.app`).
3. Note your **authtoken** from [Dashboard → Your Authtoken](https://dashboard.ngrok.com/get-started/your-authtoken).

> Your ngrok static domain becomes your `subscriber_id` — your unique identity on the ION network. Use this same domain in the next step.

## Step 2 — Register Your Keys on ION Central

1. Log in to the **ION Central Devlabs** portal.
2. Open the **Keys** tab and create a new key pair.
3. Enter your ngrok static domain as the **subscriber_id** when prompted.
4. Once registered, click the key entry to find:
   - **keyId** — identifies this key pair in the network registry
   - **signing public key** — registered so other participants can verify your messages
5. Download the **private key** file when prompted — it cannot be recovered later.

## Step 3 — Clone the Repository

```bash
git clone https://github.com/indonesiaopennetwork/ion-onix.git
cd ion-onix/bapONIX
```

## Step 4 — Configure the Adapter

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
| Buyer app webhook URL | Where the adapter routes Beckn callbacks to your app (see note below) |
| ngrok authtoken | From the ngrok dashboard |
| ngrok static domain | The domain you claimed in Step 1 |

> **Buyer app webhook URL**: This is the endpoint on your buyer application that receives Beckn responses (`on_discover`, `on_select`, `on_init`, etc.). If your application runs on the same machine as Docker, use `host.docker.internal` instead of `localhost` — Docker containers cannot reach the host via `localhost`. Example: `http://host.docker.internal:3001/api/bap-webhook`.

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

All services should show `running` or `healthy`. Open the ngrok web dashboard at `http://localhost:4041` to confirm the tunnel is active and note your public URL.

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

See `BuildingBuyerApp.md` for a guided journey through building and testing your buyer application.
