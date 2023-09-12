# Marketplace Contracts

Contains contracts for the Sequence Marketplace.

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

Please ensure code is formatted before committing with:

```bash
forge fmt contracts test script
```

### Docs

Generate docs with:

```bash
./generateDocs.sh
```

## License

Copyright (c) 2023-present [Horizon Blockchain Games Inc](https://horizon.io).

Licensed under [Apache-2.0](./LICENSE)
