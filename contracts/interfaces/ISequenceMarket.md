# ISequenceMarket


## Structs
### RequestParams
Request parameters.


```solidity
struct RequestParams {
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
|`isListing`|`bool`|True if the request is a listing, false if it is an offer.|
|`isERC1155`|`bool`|True if the token is an ERC1155 token, false if it is an ERC721 token.|
|`tokenContract`|`address`|The address of the token contract.|
|`tokenId`|`uint256`|The ID of the token.|
|`quantity`|`uint256`|The quantity of tokens.|
|`expiry`|`uint96`|The expiry of the request.|
|`currency`|`address`|The address of the currency.|
|`pricePerToken`|`uint256`|The price per token, including royalty fees.|

### Request
Request storage.


```solidity
struct Request {
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
|`creator`|`address`|The address of the request creator.|
|`isListing`|`bool`|True if the request is a listing, false if it is an offer.|
|`isERC1155`|`bool`|True if the token is an ERC1155 token, false if it is an ERC721 token.|
|`tokenContract`|`address`|The address of the token contract.|
|`tokenId`|`uint256`|The ID of the token.|
|`quantity`|`uint256`|The quantity of tokens.|
|`expiry`|`uint96`|The expiry of the request.|
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
### createRequest

Creates a request.

A listing is when the maker is selling tokens for currency.

An offer is when the maker is buying tokens with currency.


```solidity
function createRequest(RequestParams calldata request) external returns (uint256 requestId);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`request`|`RequestParams`|The request's details.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`requestId`|`uint256`|The ID of the request.|


### createRequestBatch

Creates requests.


```solidity
function createRequestBatch(RequestParams[] calldata requests) external returns (uint256[] memory requestIds);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`requests`|`RequestParams[]`|The requests' details.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`requestIds`|`uint256[]`|The IDs of the requests.|


### acceptRequest

Accepts a request.


```solidity
function acceptRequest(
  uint256 requestId,
  uint256 quantity,
  uint256[] calldata additionalFees,
  address[] calldata additionalFeeReceivers
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`requestId`|`uint256`|The ID of the request.|
|`quantity`|`uint256`|The quantity of tokens to accept.|
|`additionalFees`|`uint256[]`|The additional fees to pay.|
|`additionalFeeReceivers`|`address[]`|The addresses to send the additional fees to.|


### acceptRequestBatch

Accepts requests.


```solidity
function acceptRequestBatch(
  uint256[] calldata requestIds,
  uint256[] calldata quantities,
  uint256[] calldata additionalFees,
  address[] calldata additionalFeeReceivers
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`requestIds`|`uint256[]`|The IDs of the requests.|
|`quantities`|`uint256[]`|The quantities of tokens to accept.|
|`additionalFees`|`uint256[]`|The additional fees to pay.|
|`additionalFeeReceivers`|`address[]`|The addresses to send the additional fees to.|


### cancelRequest

Cancels a request.


```solidity
function cancelRequest(uint256 requestId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`requestId`|`uint256`|The ID of the request.|


### cancelRequestBatch

Cancels requests.


```solidity
function cancelRequestBatch(uint256[] calldata requestIds) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`requestIds`|`uint256[]`|The IDs of the requests.|


### getRequest

Gets a request.


```solidity
function getRequest(uint256 requestId) external view returns (Request memory request);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`requestId`|`uint256`|The ID of the request.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`request`|`Request`|The request.|


### getRequestBatch

Gets requests.


```solidity
function getRequestBatch(uint256[] calldata requestIds) external view returns (Request[] memory requests);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`requestIds`|`uint256[]`|The IDs of the requests.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`requests`|`Request[]`|The requests.|


### isRequestValid

Checks if a request is valid.

A request is valid if it is active, has not expired and give amount of tokens (currency for offers, tokens for listings) are transferrable.


```solidity
function isRequestValid(uint256 requestId, uint256 quantity) external view returns (bool valid, Request memory request);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`requestId`|`uint256`|The ID of the request.|
|`quantity`|`uint256`|The amount of tokens to exchange. 0 is assumed to be the request's available quantity.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`valid`|`bool`|The validity of the request.|
|`request`|`Request`|The request.|


### isRequestValidBatch

Checks if requests are valid.

A request is valid if it is active, has not expired and give amount of tokens (currency for offers, tokens for listings) are transferrable.


```solidity
function isRequestValidBatch(uint256[] calldata requestIds, uint256[] calldata quantities)
  external
  view
  returns (bool[] memory valid, Request[] memory requests);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`requestIds`|`uint256[]`|The IDs of the requests.|
|`quantities`|`uint256[]`|The amount of tokens to exchange per request. 0 is assumed to be the request's available quantity.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`valid`|`bool[]`|The validities of the requests.|
|`requests`|`Request[]`|The requests.|


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
### RequestCreated
Emitted when a request is created.


```solidity
event RequestCreated(
  uint256 indexed requestId,
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

### RequestAccepted
Emitted when a request is accepted.


```solidity
event RequestAccepted(
  uint256 indexed requestId,
  address indexed buyer,
  address indexed tokenContract,
  uint256 quantity,
  uint256 quantityRemaining
);
```

### RequestCancelled
Emitted when a request is cancelled.


```solidity
event RequestCancelled(uint256 indexed requestId, address indexed tokenContract);
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

### InvalidCurrencyApproval
Thrown when the currency approval is invalid.


```solidity
error InvalidCurrencyApproval(address currency, uint256 quantity, address owner);
```

### InvalidRequestId
Thrown when request id is invalid.


```solidity
error InvalidRequestId(uint256 requestId);
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

