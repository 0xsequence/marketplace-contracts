# Generate docs
forge doc

# Create contract docs
cp docs/src/contracts/Orderbook.sol/contract.Orderbook.md contracts/Orderbook.md
sed -i '2,5d' contracts/Orderbook.md

# Create interface docs
cp docs/src/contracts/interfaces/IOrderbook.sol/interface.IOrderbook*.md contracts/interfaces
sed -i '2,6d' contracts/interfaces/interface.IOrderbook.md
sed -i '1,6d' contracts/interfaces/interface.IOrderbookFunctions.md
sed -i '1,3d' contracts/interfaces/interface.IOrderbookStorage.md contracts/interfaces/interface.IOrderbookSignals.md
cat contracts/interfaces/interface.IOrderbook.md contracts/interfaces/interface.IOrderbookStorage.md contracts/interfaces/interface.IOrderbookFunctions.md contracts/interfaces/interface.IOrderbookSignals.md > contracts/interfaces/IOrderbook.md
rm contracts/interfaces/interface.IOrderbook*.md
