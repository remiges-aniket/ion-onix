# ion-onix

Tools and adapters for building and testing applications on the ION (Indonesia Open Network), a Beckn-protocol-based open commerce network.

## Repository Contents

| Folder | Purpose |
|--------|---------|
| `testnet/` | Self-contained local network — start here to learn Beckn message flows |
| `bapONIX/` | BAP ONIX Adapter — connects a Buyer Application to the live ION network |
| `bppONIX/` | BPP ONIX Adapter — connects a Seller Application to the live ION network |
| `common/` | Utilities (ED25519 key generation) |

## Where to Start

**Learning / exploring**: Use the testnet. It runs entirely on your machine with no external accounts required. See `testnet/README.md`.

**Building a buyer app**: Set up the BAP ONIX Adapter. See `bapONIX/README.md`.

**Building a seller app**: Set up the BPP ONIX Adapter. See `bppONIX/README.md`.

## How the ION Network Works

ION is built on the [Beckn Protocol](https://github.com/beckn/protocol-specifications-v2), an open standard for decentralised commerce. Key concepts:

- **BAP (Beckn Application Platform)** — the buyer side. Your buyer app sends requests through the BAP ONIX Adapter, which handles signing, routing, and network communication.
- **BPP (Beckn Provider Platform)** — the seller side. Your seller app receives requests through the BPP ONIX Adapter, which handles signature verification and message forwarding.
- **Registry** — a network directory where participants register their public keys and URLs so others can find and verify them.
- **Beckn Gateway (BG)** — routes `discover` requests to all registered BPPs matching a search query.

A typical transaction flows like this:

```
Buyer App  →  BAP ONIX  →  BG  →  BPP ONIX  →  Seller App
           ←           ←      ←            ←
```

Each message is signed with the sender's private key and verified against the public key in the registry, ensuring authenticity end-to-end.

## Running Both Adapters on the Same Machine

If you run both BAP ONIX and BPP ONIX on the same machine, they share a single Redis instance (started by the BAP compose file). Steps:

1. Start the BAP adapter: `cd bapONIX && docker compose -f docker-compose-BAPAdapter.yml up --build -d`
2. In `bppONIX/docker-compose-BPPAdapter.yml`, remove the `redis` service and set the network to external:
   ```yaml
   networks:
     beckn_network:
       external: true
   ```
3. Start the BPP adapter: `cd bppONIX && docker compose -f docker-compose-BPPAdapter.yml up --build -d`
4. Shut down BPP first, then BAP.
