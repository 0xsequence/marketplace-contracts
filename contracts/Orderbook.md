# Orderbook


## State Variables
### _orders

```solidity
mapping(bytes32 => Order) internal _orders;
```


## Functions
### createOrder

Creates an order.

A listing is when the maker is selling tokens for currency.

An offer is when the maker is buying tokens with currency.


```solidity
function createOrder(OrderRequest memory request) public returns (bytes32 orderId);
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
  public;
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

*Additional fees are applied to each order.*


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
function cancelOrder(bytes32 orderId) public;
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


### hashOrder

Deterministically create the orderId for the given order.


```solidity
function hashOrder(Order memory order) public pure returns (bytes32 orderId);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`order`|`Order`|The order.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`orderId`|`bytes32`|The ID of the order.|


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
function isOrderValid(bytes32 orderId) public view returns (bool valid);
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


### _isExpired

Checks if a order has expired.


```solidity
function _isExpired(Order memory order) internal view returns (bool isExpired);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`order`|`Order`|The order to check.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`isExpired`|`bool`|True if the order has expired.|


### getRoyaltyInfo

Will return how much of currency need to be paid for the royalty.


```solidity
function getRoyaltyInfo(
  address tokenContract,
  uint256 tokenId,
  uint256 cost
)
  public
  view
  returns (address recipient, uint256 royalty);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenContract`|`address`|Address of the erc-1155 token being traded|
|`tokenId`|`uint256`|ID of the erc-1155 token being traded|
|`cost`|`uint256`|Amount of currency sent/received for the trade|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`recipient`|`address`|Address that will be able to claim the royalty|
|`royalty`|`uint256`|Amount of currency that will be sent to royalty recipient|


### _hasApprovedCurrency

Checks if the amount of currency is approved for transfer exceeds the given amount.


```solidity
function _hasApprovedCurrency(address currency, uint256 amount, address owner) internal view returns (bool isValid);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`currency`|`address`|The address of the currency.|
|`amount`|`uint256`|The amount of currency.|
|`owner`|`address`|The address of the owner of the currency.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`isValid`|`bool`|True if the amount of currency is sufficient and approved for transfer.|


### _hasApprovedTokens

Checks if a token contract is ERC1155 or ERC721 and if the token is owned and approved for transfer.

*Returns false if the token contract is not ERC1155 or ERC721.*


```solidity
function _hasApprovedTokens(
  bool isERC1155,
  address tokenContract,
  uint256 tokenId,
  uint256 quantity,
  address owner
)
  internal
  view
  returns (bool isValid);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`isERC1155`|`bool`|True if the token is an ERC1155 token, false if it is an ERC721 token.|
|`tokenContract`|`address`|The address of the token contract.|
|`tokenId`|`uint256`|The ID of the token.|
|`quantity`|`uint256`|The quantity of tokens to list.|
|`owner`|`address`|The address of the owner of the token.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`isValid`|`bool`|True if the token is owned and approved for transfer.|


