# BallerBucks Stablecoin 💸
## About
This project is a implementation of a general purpose stablecoin management system much like MakerDAO's DAI token but with the added twist that is allows for setting a reference currency to peg against (given it has a chainlink feed). For example assuming a GBP deployment the coin will have the following properties:  
- Relative stability: Anchored or Pegged -> 1 GBP
- Stability mechanism (minting) : Algorithmic (Decentralised)
    - You can only mint the stable coin with enough collateral
- Collateral: Exogenous (Crypto)
    - wETH
    - wBTC

## Getting Started

### Requirements

- [git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
  - You'll know you did it right if you can run `git --version` and you see a response like `git version x.x.x`
- [foundry](https://getfoundry.sh/)
  - You'll know you did it right if you can run `forge --version` and you see a response like `forge 0.2.0 (816e00b 2023-03-16T00:05:26.396218Z)`

### Quickstart

```
git clone https://github.com/DarthShoge/foundry-ballerbucks-stablecoin
cd foundry-ballerbucks-stablecoin
make install
forge build
```

### Deploy

This will default to your local node. You need to have it running in another terminal in order for it to deploy.

```
make deploy
```
### Testing

Both unit testing and invariant testing are included

```
forge test
```
## Deployment to a testnet or mainnet

1. Setup environment variables

You'll want to set your `SEPOLIA_RPC_URL` and `SEPOLIA_PRIVATE_KEY` as environment variables. You can add them to a `.env` file, similar to what you see in `.env.example`.

- `SEPOLIA_PRIVATE_KEY`: The private key of your account (like from [metamask](https://metamask.io/)). **NOTE:** FOR DEVELOPMENT, PLEASE USE A KEY THAT DOESN'T HAVE ANY REAL FUNDS ASSOCIATED WITH IT.
  - You can [learn how to export it here](https://metamask.zendesk.com/hc/en-us/articles/360015289632-How-to-Export-an-Account-Private-Key).
- `SEPOLIA_RPC_URL`: This is url of the sepolia testnet node you're working with. You can get setup with one for free from [Alchemy](https://alchemy.com/?a=673c802981)

Optionally, add your `ETHERSCAN_API_KEY` if you want to verify your contract on [Etherscan](https://etherscan.io/).

2. Deploy

```
make deploy ARGS="--network sepolia"
```