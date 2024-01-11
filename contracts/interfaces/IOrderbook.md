# IOrderbook


## Structs
### OrderRequest
Order request parameters.


```solidity
struct OrderRequest {
  bool isListing;
  bool isERC1155;
  address tokenContract;
  uint256 tokenId;
  uint256 quantity;
  uint96 expiry;
  address currency;
  uint256 pricePerToken;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`isListing`|`bool`|True if the order is a listing, false if it is an offer.|
|`isERC1155`|`bool`|True if the token is an ERC1155 token, false if it is an ERC721 token.|
|`tokenContract`|`address`|The address of the token contract.|
|`tokenId`|`uint256`|The ID of the token.|
|`quantity`|`uint256`|The quantity of tokens.|
|`expiry`|`uint96`|The expiry of the order.|
|`currency`|`address`|The address of the currency.|
|`pricePerToken`|`uint256`|The price per token, including royalty fees.|

### Order
Order parameters.


```solidity
struct Order {
  address creator;
  bool isListing;
  bool isERC1155;
  address tokenContract;
  uint256 tokenId;
  uint256 quantity;
  uint96 expiry;
  address currency;
  uint256 pricePerToken;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`creator`|`address`|The address of the order creator.|
|`isListing`|`bool`|True if the order is a listing, false if it is an offer.|
|`isERC1155`|`bool`|True if the token is an ERC1155 token, false if it is an ERC721 token.|
|`tokenContract`|`address`|The address of the token contract.|
|`tokenId`|`uint256`|The ID of the token.|
|`quantity`|`uint256`|The quantity of tokens.|
|`expiry`|`uint96`|The expiry of the order.|
|`currency`|`address`|The address of the currency.|
|`pricePerToken`|`uint256`|The price per token, including royalty fees.|

### CustomRoyalty
Custom royalty parameters.

*Used to store custom royalty settings for contracts do not support ERC2981.*


```solidity
struct CustomRoyalty {
  address recipient;
  uint96 fee;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`recipient`|`address`|Address to send the fees to.|
|`fee`|`uint96`|Fee percentage with a 10000 basis (e.g. 0.3% is 30 and 1% is 100 and 100% is 10000).|


## Functions
### createOrder

Creates an order.

A listing is when the maker is selling tokens for currency.

An offer is when the maker is buying tokens with currency.


```solidity
function createOrder(OrderRequest calldata request) external returns (uint256 orderId);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`request`|`OrderRequest`|The requested order's details.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`orderId`|`uint256`|The ID of the order.|


### createOrderBatch

Creates orders.


```solidity
function createOrderBatch(OrderRequest[] calldata requests) external returns (uint256[] memory orderIds);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`requests`|`OrderRequest[]`|The requested orders' details.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`orderIds`|`uint256[]`|The IDs of the orders.|


### acceptOrder

Accepts an order.


```solidity
function acceptOrder(
  uint256 orderId,
  uint256 quantity,
  uint256[] calldata additionalFees,
  address[] calldata additionalFeeReceivers
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`orderId`|`uint256`|The ID of the order.|
|`quantity`|`uint256`|The quantity of tokens to accept.|
|`additionalFees`|`uint256[]`|The additional fees to pay.|
|`additionalFeeReceivers`|`address[]`|The addresses to send the additional fees to.|


### acceptOrderBatch

Accepts orders.


```solidity
function acceptOrderBatch(
  uint256[] calldata orderIds,
  uint256[] calldata quantities,
  uint256[] calldata additionalFees,
  address[] calldata additionalFeeReceivers
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`orderIds`|`uint256[]`|The IDs of the orders.|
|`quantities`|`uint256[]`|The quantities of tokens to accept.|
|`additionalFees`|`uint256[]`|The additional fees to pay.|
|`additionalFeeReceivers`|`address[]`|The addresses to send the additional fees to.|


### cancelOrder

Cancels an order.


```solidity
function cancelOrder(uint256 orderId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`orderId`|`uint256`|The ID of the order.|


### cancelOrderBatch

Cancels orders.


```solidity
function cancelOrderBatch(uint256[] calldata orderIds) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`orderIds`|`uint256[]`|The IDs of the orders.|


### getOrder

Gets an order.


```solidity
function getOrder(uint256 orderId) external view returns (Order memory order);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`orderId`|`uint256`|The ID of the order.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`order`|`Order`|The order.|


### getOrderBatch

Gets orders.


```solidity
function getOrderBatch(uint256[] calldata orderIds) external view returns (Order[] memory orders);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`orderIds`|`uint256[]`|The IDs of the orders.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`orders`|`Order[]`|The orders.|


### isOrderValid

Checks if an order is valid.

An order is valid if it is active, has not expired and give amount of tokens (currency for offers, tokens for listings) are transferrable.


```solidity
function isOrderValid(uint256 orderId, uint256 quantity) external view returns (bool valid, Order memory order);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`orderId`|`uint256`|The ID of the order.|
|`quantity`|`uint256`|The amount of tokens to exchange. 0 is assumed to be the order's available quantity.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`valid`|`bool`|The validity of the order.|
|`order`|`Order`|The order.|


### isOrderValidBatch

Checks if orders are valid.

An order is valid if it is active, has not expired and give amount of tokens (currency for offers, tokens for listings) are transferrable.


```solidity
function isOrderValidBatch(uint256[] calldata orderIds, uint256[] calldata quantities)
  external
  view
  returns (bool[] memory valid, Order[] memory orders);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`orderIds`|`uint256[]`|The IDs of the orders.|
|`quantities`|`uint256[]`|The amount of tokens to exchange per order. 0 is assumed to be the order's available quantity.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`valid`|`bool[]`|The validities of the orders.|
|`orders`|`Order[]`|The orders.|


### getRoyaltyInfo

Returns the royalty details for the given token and cost.


```solidity
function getRoyaltyInfo(address tokenContract, uint256 tokenId, uint256 cost)
  external
  view
  returns (address recipient, uint256 royalty);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenContract`|`address`|Address of the token being traded.|
|`tokenId`|`uint256`|The ID of the token.|
|`cost`|`uint256`|Amount of currency sent/received for the trade.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`recipient`|`address`|Address to send royalties to.|
|`royalty`|`uint256`|Amount of currency to be paid as royalties.|



## Events
### OrderCreated
Emitted when an Order is created.


```solidity
event OrderCreated(
  uint256 indexed orderId,
  address indexed creator,
  address indexed tokenContract,
  uint256 tokenId,
  bool isListing,
  uint256 quantity,
  address currency,
  uint256 pricePerToken,
  uint256 expiry
);
```

### OrderAccepted
Emitted when an Order is accepted.


```solidity
event OrderAccepted(
  uint256 indexed orderId,
  address indexed buyer,
  address indexed tokenContract,
  uint256 quantity,
  uint256 quantityRemaining
);
```

### OrderCancelled
Emitted when an Order is cancelled.


```solidity
event OrderCancelled(uint256 indexed orderId, address indexed tokenContract);
```

### CustomRoyaltyChanged
Emitted when custom royalty settings are changed.


```solidity
event CustomRoyaltyChanged(address indexed tokenContract, address recipient, uint96 fee);
```

## Errors
### UnsupportedContractInterface
Thrown when the contract address does not support the required interface.


```solidity
error UnsupportedContractInterface(address contractAddress, bytes4 interfaceId);
```

### InvalidTokenApproval
Thrown when the token approval is invalid.


```solidity
error InvalidTokenApproval(address tokenContract, uint256 tokenId, uint256 quantity, address owner);
```

### InvalidCurrency
Thrown when the currency address is invalid.


```solidity
error InvalidCurrency();
```

### InvalidCurrencyApproval
Thrown when the currency approval is invalid.


```solidity
error InvalidCurrencyApproval(address currency, uint256 quantity, address owner);
```

### InvalidOrderId
Thrown when order id is invalid.


```solidity
error InvalidOrderId(uint256 orderId);
```

### InvalidBatchRequest
Thrown when the parameters of a batch accept request are invalid.


```solidity
error InvalidBatchRequest();
```

### InvalidQuantity
Thrown when quantity is invalid.


```solidity
error InvalidQuantity();
```

### InvalidPrice
Thrown when price is invalid.


```solidity
error InvalidPrice();
```

### InvalidRoyalty
Thrown when royalty is invalid.


```solidity
error InvalidRoyalty();
```

### InvalidExpiry
Thrown when expiry is invalid.


```solidity
error InvalidExpiry();
```

### InvalidAdditionalFees
Thrown when the additional fees are invalid.


```solidity
error InvalidAdditionalFees();
```

