# Orderbook


## State Variables
### _orders

```solidity
mapping(bytes32 => Order) internal _orders;
```


### customRoyalties

```solidity
mapping(address => CustomRoyalty) public customRoyalties;
```


### _nextOrderId

```solidity
uint256 private _nextOrderId;
```


## Functions
### constructor


```solidity
constructor(address _owner);
```

### createOrder

Creates an order.


```solidity
function createOrder(OrderRequest calldata request) external nonReentrant returns (bytes32 orderId);
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
function createOrderBatch(OrderRequest[] calldata requests) external nonReentrant returns (bytes32[] memory orderIds);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`requests`|`OrderRequest[]`|The requested orders' details.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`orderIds`|`bytes32[]`|The IDs of the orders.|


### _createOrder

Performs creation of an order.


```solidity
function _createOrder(OrderRequest calldata request) internal returns (bytes32 orderId);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`request`|`OrderRequest`|The requested order's details.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`orderId`|`bytes32`|The ID of the order.|


### acceptOrder

Accepts an order.


```solidity
function acceptOrder(
  bytes32 orderId,
  uint256 quantity,
  uint256[] calldata additionalFees,
  address[] calldata additionalFeeReceivers
) external nonReentrant;
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
  bytes32[] calldata orderIds,
  uint256[] calldata quantities,
  uint256[] calldata additionalFees,
  address[] calldata additionalFeeReceivers
) external nonReentrant;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`orderIds`|`bytes32[]`|The IDs of the orders.|
|`quantities`|`uint256[]`|The quantities of tokens to accept.|
|`additionalFees`|`uint256[]`|The additional fees to pay.|
|`additionalFeeReceivers`|`address[]`|The addresses to send the additional fees to.|


### _acceptOrder

Performs acceptance of an order.


```solidity
function _acceptOrder(
  bytes32 orderId,
  uint256 quantity,
  uint256[] calldata additionalFees,
  address[] calldata additionalFeeReceivers
) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`orderId`|`bytes32`|The ID of the order.|
|`quantity`|`uint256`|The quantity of tokens to accept.|
|`additionalFees`|`uint256[]`|The additional fees to pay.|
|`additionalFeeReceivers`|`address[]`|The addresses to send the additional fees to.|


### cancelOrder

Cancels an order.


```solidity
function cancelOrder(bytes32 orderId) external nonReentrant;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`orderId`|`bytes32`|The ID of the order.|


### cancelOrderBatch

Cancels orders.


```solidity
function cancelOrderBatch(bytes32[] calldata orderIds) external nonReentrant;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`orderIds`|`bytes32[]`|The IDs of the orders.|


### _cancelOrder

Performs cancellation of an order.


```solidity
function _cancelOrder(bytes32 orderId) internal;
```
**Parameters**

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
function getOrderBatch(bytes32[] calldata orderIds) external view returns (Order[] memory orders);
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

An order is valid if it is active, has not expired and give amount of tokens (currency for offers, tokens for listings) are transferrable.


```solidity
function isOrderValid(bytes32 orderId, uint256 quantity) public view returns (bool valid, Order memory order);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`orderId`|`bytes32`|The ID of the order.|
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
function isOrderValidBatch(bytes32[] calldata orderIds, uint256[] calldata quantities)
  external
  view
  returns (bool[] memory valid, Order[] memory orders);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`orderIds`|`bytes32[]`|The IDs of the orders.|
|`quantities`|`uint256[]`|The amount of tokens to exchange per order. 0 is assumed to be the order's available quantity.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`valid`|`bool[]`|The validities of the orders.|
|`orders`|`Order[]`|The orders.|


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


### setRoyaltyInfo

Will set the royalties fees and recipient for contracts that don't support ERC-2981.

This can be called even when the contract supports ERC-2891, but will be ignored if it does.

*Can only be called by the owner.*


```solidity
function setRoyaltyInfo(address tokenContract, address recipient, uint96 fee) public onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenContract`|`address`|The contract the custom royalties apply to.|
|`recipient`|`address`|Address to send the royalties to.|
|`fee`|`uint96`|Fee percentage with a 10000 basis (e.g. 0.3% is 30 and 1% is 100 and 100% is 10000).|


### getRoyaltyInfo

Returns the royalty details for the given token and cost.


```solidity
function getRoyaltyInfo(address tokenContract, uint256 tokenId, uint256 cost)
  public
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


### _hasApprovedCurrency

Checks if the amount of currency is approved for transfer exceeds the given amount.


```solidity
function _hasApprovedCurrency(address currency, uint256 amount, address who) internal view returns (bool isValid);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`currency`|`address`|The address of the currency.|
|`amount`|`uint256`|The amount of currency.|
|`who`|`address`|The address of the owner of the currency.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`isValid`|`bool`|True if the amount of currency is sufficient and approved for transfer.|


### _hasApprovedTokens

Checks if a token contract is ERC1155 or ERC721 and if the token is owned and approved for transfer.

*Returns false if the token contract is not ERC1155 or ERC721.*


```solidity
function _hasApprovedTokens(bool isERC1155, address tokenContract, uint256 tokenId, uint256 quantity, address who)
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
|`who`|`address`|The address of the owner of the token.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`isValid`|`bool`|True if the token is owned and approved for transfer.|


### _requireInterface

Checks if a contract implements an interface.

*Reverts if the contract does not implement the interface.*


```solidity
function _requireInterface(address contractAddress, bytes4 interfaceId) internal view;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`contractAddress`|`address`|The address of the contract.|
|`interfaceId`|`bytes4`|The interface ID.|


