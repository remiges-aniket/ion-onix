## ion-onix Repository

### Introduction
This repository contain files required to setup ONIX adapters and tools to help developers build applications on ION(Indonesia Open Network). It contains the following folders

- **bapONIX** - Contains the BAP ONIX Adapter. Used to integrate Buyer App into ION network.

- **bppONIX** - Contains the BPP ONIX Adapter. Used to integrate Seller App into ION network. 

- **testnet** - Contains a sandbox ION Network. Used to understand message communication, try out sample postman collection, develop on local machine etc.

- **common** - Contains common utilities such as key generator etc. 


### Running both BAP and BPP individually on the same machine
1. Configure BAPOnix and run the BAP docker compose.
2. Configure BPPOnix
3. Modify the docker-compose-BPPAdapter.yml to do the following:
    a. Remove the entire redis service (as the redis from BAP will continue to be used)
    b. Add `external=true` to the beckn_network network.
4. Start BPP docker compose.
5. When you want to shutdown the two docker compose networks, first bring down the BPP docker compose network and then bring down the BAP docker compose (as the redis service is present in BAP)
