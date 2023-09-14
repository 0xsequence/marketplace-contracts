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


## Functions
### createOrder

Creates an order.

A listing is when the maker is selling tokens for currency.

An offer is when the maker is buying tokens with currency.


```solidity
function createOrder(OrderRequest memory request) external returns (bytes32 orderId);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`request`|`OrderRequest`|The requested order's details.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`orderId`|`bytes32`|The ID of the order.|


### createOrderBatch

Creates orders.


```solidity
function createOrderBatch(OrderRequest[] memory requests) external returns (bytes32[] memory orderIds);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`requests`|`OrderRequest[]`|The requested orders' details.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`orderIds`|`bytes32[]`|The IDs of the orders.|


### acceptOrder

Accepts an order.


```solidity
function acceptOrder(
  bytes32 orderId,
  uint256 quantity,
  uint256[] memory additionalFees,
  address[] memory additionalFeeReceivers
)
  external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`orderId`|`bytes32`|The ID of the order.|
|`quantity`|`uint256`|The quantity of tokens to accept.|
|`additionalFees`|`uint256[]`|The additional fees to pay.|
|`additionalFeeReceivers`|`address[]`|The addresses to send the additional fees to.|


### acceptOrderBatch

Accepts orders.


```solidity
function acceptOrderBatch(
  bytes32[] memory orderIds,
  uint256[] memory quantities,
  uint256[] memory additionalFees,
  address[] memory additionalFeeReceivers
)
  external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`orderIds`|`bytes32[]`|The IDs of the orders.|
|`quantities`|`uint256[]`|The quantities of tokens to accept.|
|`additionalFees`|`uint256[]`|The additional fees to pay.|
|`additionalFeeReceivers`|`address[]`|The addresses to send the additional fees to.|


### cancelOrder

Cancels an order.


```solidity
function cancelOrder(bytes32 orderId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`orderId`|`bytes32`|The ID of the order.|


### cancelOrderBatch

Cancels orders.


```solidity
function cancelOrderBatch(bytes32[] memory orderIds) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`orderIds`|`bytes32[]`|The IDs of the orders.|


### getOrder

Gets an order.


```solidity
function getOrder(bytes32 orderId) external view returns (Order memory order);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`orderId`|`bytes32`|The ID of the order.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`order`|`Order`|The order.|


### getOrderBatch

Gets orders.


```solidity
function getOrderBatch(bytes32[] memory orderIds) external view returns (Order[] memory orders);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`orderIds`|`bytes32[]`|The IDs of the orders.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`orders`|`Order[]`|The orders.|


### isOrderValid

Checks if an order is valid.

An order is valid if it is active, has not expired and tokens (currency for offers, tokens for listings) are transferrable.


```solidity
function isOrderValid(bytes32 orderId) external view returns (bool valid);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`orderId`|`bytes32`|The ID of the order.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`valid`|`bool`|The validity of the order.|


### isOrderValidBatch

Checks if orders are valid.

An order is valid if it is active, has not expired and tokens (currency for offers, tokens for listings) are transferrable.


```solidity
function isOrderValidBatch(bytes32[] memory orderIds) external view returns (bool[] memory valid);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`orderIds`|`bytes32[]`|The IDs of the orders.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`valid`|`bool[]`|The validities of the orders.|



## Events
### OrderCreated
Emitted when an Order is created.


```solidity
event OrderCreated(
  bytes32 indexed orderId,
  address indexed tokenContract,
  uint256 indexed tokenId,
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
  bytes32 indexed orderId,
  address indexed buyer,
  address indexed tokenContract,
  uint256 quantity,
  uint256 quantityRemaining
);
```

### OrderCancelled
Emitted when an Order is cancelled.


```solidity
event OrderCancelled(bytes32 indexed orderId, address indexed tokenContract);
```

## Errors
### InvalidTokenApproval
Thrown when the token approval is invalid.


```solidity
error InvalidTokenApproval(address tokenContract, uint256 tokenId, uint256 quantity, address owner);
```

### InvalidCurrencyApproval
Thrown when the currency approval is invalid.


```solidity
error InvalidCurrencyApproval(address currency, uint256 quantity, address owner);
```

### InvalidOrderId
Thrown when order id is invalid.


```solidity
error InvalidOrderId(bytes32 orderId);
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

