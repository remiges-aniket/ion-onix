# BPP ONIX Adapter

The BPP (Beckn Provider Platform) ONIX Adapter connects your Seller Application to the ION (Indonesia Open Network). It handles the Beckn protocol layer on your behalf: verifying signatures on incoming requests, signing outgoing responses, routing messages to your seller application, and managing your network participant identity.

Buyer apps on the ION network send discovery and transaction requests to your adapter's public URL. The adapter forwards them to your seller application, receives your responses, signs them, and sends them back through the network.

```
ION Network  ──►  BPP ONIX Adapter  ──►  Seller App
             ◄──                    ◄──
```

## Prerequisites

- **Docker** and **Docker Compose** — [Install Docker](https://docs.docker.com/engine/install/)
- **ngrok account** with a free static domain — [Sign up at ngrok.com](https://ngrok.com)
- **ION Central Devlabs account** — to register your network participant keys

## Step 1 — Set Up Your ngrok Static Domain

ngrok creates a stable public URL that routes internet traffic to your laptop. The ION network uses this URL as your BPP's public address, so buyers on the network can find and reach your seller application.

1. Sign up or log in to [ngrok.com](https://ngrok.com).
2. Go to **Dashboard → Domains** and claim your free static domain (e.g. `clever-mongoose-freely.ngrok-free.app`).
3. Note your **authtoken** from [Dashboard → Your Authtoken](https://dashboard.ngrok.com/get-started/your-authtoken).

> Your ngrok static domain becomes your `subscriber_id` — your unique identity on the ION network. Use this same domain when registering keys in the next step.

## Step 2 — Register Your Keys on ION Central

1. Log in to the **ION Central Devlabs** portal.
2. Open the **Keys** tab and create a new key pair.
3. Enter your ngrok static domain as the **subscriber_id** when prompted.
4. Once registered, click the key entry to find:
   - **keyId** — identifies this key pair in the network registry
   - **signing public key** — registered so buyers can verify your responses
5. Download the **private key** file when prompted — it cannot be recovered later.

## Step 3 — Clone the Repository

```bash
git clone https://github.com/indonesiaopennetwork/ion-onix.git
cd ion-onix/bppONIX
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
| Seller app webhook URL | Where the adapter routes incoming Beckn requests to your app (see note below) |
| ngrok authtoken | From the ngrok dashboard |
| ngrok static domain | The domain you claimed in Step 1 |

> **Seller app webhook URL**: This is the endpoint on your seller application that receives Beckn requests (`discover`, `select`, `init`, `confirm`, etc.). If your application runs on the same machine as Docker, use `host.docker.internal` instead of `localhost` — Docker containers cannot reach the host via `localhost`. Example: `http://host.docker.internal:3002/api/webhook`.

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

All services should show `running` or `healthy`. Open the ngrok web dashboard at `http://localhost:4040` to confirm the tunnel is active and note your public URL.

Your BPP is now reachable at `https://<your-ngrok-domain>/bpp/receiver/`.

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

**Re-configuring**

Run `./configure_onix.sh` again at any time. Previous configs are saved in `config/backup/` with timestamps.

## Running BAP and BPP on the Same Machine

If you are running both BAP ONIX and BPP ONIX adapters on the same machine, the redis service must be shared. See the instructions in `bapONIX/README.md` under "Running BAP and BPP on the Same Machine".

## Next Steps

See `BuildingSellerApp.md` for a guided journey through building and testing your seller application.
