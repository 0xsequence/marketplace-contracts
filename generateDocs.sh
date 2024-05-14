# Generate docs
forge doc

# Create contract docs
cp docs/src/contracts/SequenceMarket.sol/contract.SequenceMarket.md contracts/SequenceMarket.md
sed -i '2,5d' contracts/SequenceMarket.md

# Create interface docs
cp docs/src/contracts/interfaces/ISequenceMarket.sol/interface.ISequenceMarket*.md contracts/interfaces
sed -i '2,6d' contracts/interfaces/interface.ISequenceMarket.md
sed -i '1,6d' contracts/interfaces/interface.ISequenceMarketFunctions.md
sed -i '1,3d' contracts/interfaces/interface.ISequenceMarketStorage.md contracts/interfaces/interface.ISequenceMarketSignals.md
cat contracts/interfaces/interface.ISequenceMarket.md contracts/interfaces/interface.ISequenceMarketStorage.md contracts/interfaces/interface.ISequenceMarketFunctions.md contracts/interfaces/interface.ISequenceMarketSignals.md > contracts/interfaces/ISequenceMarket.md
rm contracts/interfaces/interface.ISequenceMarket*.md

# Add reference to interface docs in contract doc
sed -i '3i Interface and struct definitions can be found at [ISequenceMarket.md](./interfaces/ISequenceMarket.md).' contracts/SequenceMarket.md
