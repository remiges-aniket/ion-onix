# ION Testnet

The ION Testnet is a self-contained local development environment for testing Beckn protocol message flows on the Indonesia Open Network (ION). It bundles a BAP ONIX adapter, a BPP ONIX adapter, a sample seller application, and a lightweight monitoring collector — all running together in Docker Compose.

Use the testnet to:
- Learn the Beckn message flow (discover → select → init → confirm → status) hands-on
- Test your buyer or seller application before connecting to the live network
- Run the provided Postman collections against a fully local stack

---

## Prerequisites

- **Docker** and **Docker Compose** — [Install Docker](https://docs.docker.com/engine/install/)
- **Postman** (optional, for the included collections) — [Download Postman](https://www.postman.com/downloads/)

No ION Central account or ngrok is required — the testnet runs entirely on your machine.

---

## Quick Start

```bash
git clone https://github.com/indonesiaopennetwork/ion-onix.git
cd ion-onix/testnet
docker compose -f docker-compose-testnet.yml up --build
```

The first run pulls and builds images; allow a few minutes. Once running, the stack exposes:

| Service | URL |
|---------|-----|
| BAP ONIX Adapter (caller) | `http://localhost:8081/bap/caller/` |
| BAP ONIX Adapter (receiver) | `http://localhost:8081/bap/receiver/` |
| BPP ONIX Adapter (caller) | `http://localhost:8082/bpp/caller/` |
| BPP ONIX Adapter (receiver) | `http://localhost:8082/bpp/receiver/` |
| Buyer App sample | `http://localhost:3001` |
| Seller App sample | `http://localhost:3002` |

---

## Verifying the Stack

```bash
docker compose -f docker-compose-testnet.yml ps
```

All services should show `running` or `healthy`.

---

## Running the Postman Collections

The `postman/` directory contains pre-built request collections for testing ION message flows.

1. Open Postman and click **Import**.
2. Select **File**, navigate to `postman/`, choose a collection `.json` file.
3. Run requests in the order shown — they follow the Beckn transaction sequence:
   `discover` → `on_discover` → `select` → `on_select` → `init` → `on_init` → `confirm` → `on_confirm`

Check Docker logs to see messages passing through the adapters:
```bash
docker compose -f docker-compose-testnet.yml logs -f onix-bap
docker compose -f docker-compose-testnet.yml logs -f onix-bpp
```

---

## Architecture

The testnet simulates a complete Beckn transaction between a buyer and a seller on a single machine:

```
Postman / Buyer App
      │
      │  POST /bap/caller/<action>
      ▼
  BAP ONIX Adapter  ─── signs request, routes via network ───►  BPP ONIX Adapter
  (port 8081)                                                     (port 8082)
      ▲                                                                │
      │  routes on_* responses back                                    │  forwards to
      └─────────────────────────────────────────────────────  Seller App (port 3002)
```

The seller app bundled in the testnet returns pre-packaged sample responses, so you can see the full round-trip without building any application code.

See `developing_with_testnet.md` for instructions on connecting your own buyer or seller application to the testnet.

---

## Stopping the Stack

```bash
docker compose -f docker-compose-testnet.yml down
```

---

## Troubleshooting

**Containers fail to start**

Check for port conflicts (8081, 8082, 3001, 3002, 6379) and inspect logs:
```bash
docker compose -f docker-compose-testnet.yml logs
```

**Postman requests return connection errors**

Ensure the stack is running and the `BASE_URL` variable in the Postman collection points to `http://localhost:8081`.

**Out of memory / build failures**

Make sure Docker has at least 4 GB of RAM allocated (Docker Desktop → Settings → Resources).
