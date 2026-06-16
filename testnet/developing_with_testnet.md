# Developing ION Applications with testnet

The testnet is a test network created for the purpose of developers who are new to ION and want to understand ION message formats and overall flow. It also acts as a sandbox during development process. This document currently is the barebones version that works. It will be enhanced with the following:
1. Images for each section to show the network structure at the stage.
2. A new observe UI will give a visual view of the messages and should be easier than the docker logs method described below.

## Structure of the testnet

The testnet contained in this folder includes all the components of a ION test network. In general, the Postman(running on local machine) is imagined as a buyer app. It has a BAP ONIX, BPP ONIX and a sandbox seller app (that sends some prepackged responses). 

## Bringing up the testnet

In this current folder, run the following command. If you do not want the aggregated logs streaming in the console, use the -d flag to run it in detached mode. 

```
docker compose -f docker-compose-testnet.yaml up --build 
```

To bring down the testnet, if it is running in an attached mode, you can type ctrl-c and then run the following command. If you are running in the detached mode, you can directly run this command from this folder.

```
docker compose -f docker-compose-testnet.yaml down
```

## Understanding ION through the testnet
- Once you have the testnet running, use the postman collection present in the postman folder to trigger various Beckn messages and understand the format of requests and responses. For now use the docker logs feature (`docker logs onix-bap` etc) to see the individual logs. Soon there will be a UI through which you can better visualize the message flows.

## Developing buyer side app using the testnet
- When you are developing a buyer side app, your app will be replacing the postman. Before you build, you can modify the postman collection to use the messages appropriate for your usecase and test it out.
- When you want to hook the testnet with your software, you need to send the messages to `http://localhost:8081/bap/caller`. In order to have the responses from the network routed back to your software, in the file `config/local-simple-routing-BAPReceiver.yaml`, change the `routingRules.target.url` field which currently points to a sandbox-bap(which just prints out the response) to the port where your software is running. Restart the testnet after 

## Developing seller side app using the testnet
- When you are developing a seller side app, your app will be replacing the sandbox-bpp component of the testnet. 
- After you are done with trying out with postman and have your own software server, in the file `config/local-simple-routing-BPPReceiver.yaml`, change the `routingRules.target.url` field which currently points to the sandbox-bpp(which returns back sample responses) to the port where your seller side software is running. 
- Similarly your software should send its responses to ION messages to 'http://localhost:8082/bpp/caller`

