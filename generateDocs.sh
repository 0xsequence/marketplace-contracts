# Generate docs
forge doc

# Copy generated doc file
cp "docs/src/contracts/Orderbook.sol/contract.Orderbook.md" "contracts/Orderbook.md"

# Remove references to files that aren't copied
sed -i '2,5d' "contracts/Orderbook.md"
