# Marketplace Contracts

Contains contracts for the Sequence Marketplace.

## Contracts

### Orderbook

The Orderbook contract enables marketplace participants to create and fill listings and offers exchanging ERC-1155 and ERC-721 tokens for ERC-20 tokens.

The Orderbook accept partial fills of any order using ERC-1155 tokens.

The Orderbook contract is unowned and does not have any adminstrative functions.
Any platform is fee to integrate with the Orderbook contract to provide a marketplace for their users.

#### Flow

1. The order creator approves the Orderbook contract to transfer of ERC-1155 or ERC-721 tokens for a listing, or ERC-20 tokens for an offer.
2. The order creator calls the Orderbook to create an order.
3. The order acceptor approves the Orderbook contract to transfer the corresponding ERC-20 tokens for a listing, or ERC-1155 or ERC-721 tokens for an offer.
4. The order acceptor calls the Orderbook to accept the order.
5. The Orderbook contract transfers the tokens between the order creator and acceptor, deducting fees as applicable.

Note: The order creator can cancel their order at any time, even after a partial fill.

#### Fees

The Orderbook automatically deducts ERC-2981 royalty payments from the order **creator** when an order is filled.

Additional fees (e.g. platform fees) can be taken from the **acceptor** of an order by specifying a fee recipient address when accepting an order.

All fees are taken from the ERC-20 token used in the transfer.


## Development

### Prerequisites

Clone the repo with submodules:

```bash
git clone https://github.com/0xsequence/marketplace-contracts
git submodule update --init --recursive
```

Install Forge via [Foundry](https://book.getfoundry.sh/getting-started/installation).

### Tests

Run the tests with:

```bash
forge test -vvv
```

Run coverage report with:

```bash
forge coverage --report lcov && lcov --remove lcov.info -o lcov.info 'test/*' 'script/*' && genhtml -o report lcov.info
cd report && py -m http.server
```

### Formatting

Please ensure code is formatted before committing. If you use VSCode, you will be prompted to install the Prettier extension.

### Docs

Generate docs with:

```bash
./generateDocs.sh
```

## License

Copyright (c) 2023-present [Horizon Blockchain Games Inc](https://horizon.io).

Licensed under [Apache-2.0](./LICENSE)
