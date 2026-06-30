# Developing ION Applications with the Testnet

The testnet is a local sandbox for developers who are new to ION and want to understand message formats and overall flow before connecting to the live network.

## Testnet Architecture

```
Postman (acts as buyer app)
      │
      ▼
  BAP ONIX Adapter  ────────────────────►  BPP ONIX Adapter
  (port 8081)                              (port 8082)
      ▲                                         │
      │  on_* callbacks                         │  incoming requests
      └─────────────────────────────────  Seller App sample
                                          (port 3002, returns pre-packaged responses)
```

The testnet includes a sample seller app that returns fixed responses, so you can observe a complete Beckn transaction without writing any application code.

## Bringing Up the Testnet

```bash
cd testnet
docker compose -f docker-compose-testnet.yml up --build
```

Remove `--build` on subsequent starts to skip the image build step. Add `-d` to run in detached mode.

To bring down:

```bash
docker compose -f docker-compose-testnet.yml down
```

## Exploring the Message Flow

Once the testnet is running, use the Postman collection in `postman/` to send Beckn messages and observe how they flow through the adapters.

Watch the adapter logs to see messages in real time:

```bash
docker logs -f onix-bap   # BAP adapter logs
docker logs -f onix-bpp   # BPP adapter logs
```

Each log entry shows the action, routing decision, and any signature validation results.

## Developing a Buyer App

Your buyer app sends Beckn requests to the BAP adapter and receives callbacks at a webhook URL.

**Sending requests**: POST to `http://localhost:8081/bap/caller/<action>`

```
POST http://localhost:8081/bap/caller/discover   # search for products
POST http://localhost:8081/bap/caller/select     # select an item
POST http://localhost:8081/bap/caller/init       # initiate order
POST http://localhost:8081/bap/caller/confirm    # confirm order
```

**Receiving callbacks**: Edit `config/local-simple-routing-BAPReceiver.yaml` to point `routingRules[].target.url` at your application's webhook endpoint. If your app runs on the host machine (outside Docker), use `host.docker.internal` instead of `localhost`:

```yaml
routingRules:
  - version: "2.0.0"
    targetType: "url"
    target:
      url: "http://host.docker.internal:3001/api/bap-webhook"
    endpoints:
      - on_discover
      - on_select
      - on_init
      - on_confirm
      - on_status
      - on_cancel
      - on_support
```

Restart the testnet after editing config files:
```bash
docker compose -f docker-compose-testnet.yml restart onix-bap
```

## Developing a Seller App

Your seller app receives incoming Beckn requests from the BPP adapter and sends responses back.

**Receiving requests**: Edit `config/local-simple-routing-BPPReceiver.yaml` to point `routingRules[].target.url` at your seller application's webhook endpoint:

```yaml
routingRules:
  - version: "2.0.0"
    targetType: "url"
    target:
      url: "http://host.docker.internal:3002/api/webhook"
    endpoints:
      - discover
      - select
      - init
      - confirm
      - status
      - cancel
      - support
```

Restart the BPP adapter after editing:
```bash
docker compose -f docker-compose-testnet.yml restart onix-bpp
```

**Sending responses**: POST Beckn response messages to the BPP caller endpoint:

```
POST http://localhost:8082/bpp/caller/on_discover
POST http://localhost:8082/bpp/caller/on_select
POST http://localhost:8082/bpp/caller/on_init
POST http://localhost:8082/bpp/caller/on_confirm
```

The adapter signs each response and routes it back to the originating buyer app through the BAP adapter.

## Moving to the Live ION Network

Once you have tested your application against the testnet, the next step is to connect to the live ION network:

- For buyer apps: set up the **BAP ONIX Adapter** — see `bapONIX/README.md`
- For seller apps: set up the **BPP ONIX Adapter** — see `bppONIX/README.md`

Both require registering keys on ION Central and setting up an ngrok tunnel so the network can reach your machine.
