# SequenceMarket

Interface and struct definitions can be found at [ISequenceMarket.md](./interfaces/ISequenceMarket.md).

## State Variables
### _requests

```solidity
mapping(uint256 => Request) internal _requests;
```


### invalidBeforeId

```solidity
mapping(address => uint256) public invalidBeforeId;
```


### invalidTokenBeforeId

```solidity
mapping(address => mapping(address => uint256)) public invalidTokenBeforeId;
```


### customRoyalties

```solidity
mapping(address => CustomRoyalty) public customRoyalties;
```


### _nextRequestId

```solidity
uint256 private _nextRequestId;
```


## Functions
### constructor


```solidity
constructor();
```

### initialize


```solidity
function initialize(address _owner) external initializer;
```

### _authorizeUpgrade


```solidity
function _authorizeUpgrade(address) internal override onlyOwner;
```

### createRequest

Creates a request.


```solidity
function createRequest(RequestParams calldata request) external nonReentrant returns (uint256 requestId);
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
function createRequestBatch(RequestParams[] calldata requests)
  external
  nonReentrant
  returns (uint256[] memory requestIds);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`requests`|`RequestParams[]`|The requests' details.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`requestIds`|`uint256[]`|The IDs of the requests.|


### _createRequest

Performs creation of a request.


```solidity
function _createRequest(RequestParams calldata params) internal returns (uint256 requestId);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`params`|`RequestParams`|The request's params.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`requestId`|`uint256`|The ID of the request.|


### acceptRequest

Accepts a request.


```solidity
function acceptRequest(
  uint256 requestId,
  uint256 quantity,
  address recipient,
  uint256[] calldata additionalFees,
  address[] calldata additionalFeeRecipients
) external payable nonReentrant;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`requestId`|`uint256`|The ID of the request.|
|`quantity`|`uint256`|The quantity of tokens to accept.|
|`recipient`|`address`|The recipient of the accepted tokens.|
|`additionalFees`|`uint256[]`|The additional fees to pay.|
|`additionalFeeRecipients`|`address[]`|The addresses to send the additional fees to.|


### acceptRequestBatch

Accepts requests.

*Additional fees are applied to each request.*


```solidity
function acceptRequestBatch(
  uint256[] calldata requestIds,
  uint256[] calldata quantities,
  address[] calldata recipients,
  uint256[] calldata additionalFees,
  address[] calldata additionalFeeRecipients
) external nonReentrant;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`requestIds`|`uint256[]`|The IDs of the requests.|
|`quantities`|`uint256[]`|The quantities of tokens to accept.|
|`recipients`|`address[]`|The recipients of the accepted tokens.|
|`additionalFees`|`uint256[]`|The additional fees to pay.|
|`additionalFeeRecipients`|`address[]`|The addresses to send the additional fees to.|


### _acceptRequest

Performs acceptance of a request.


```solidity
function _acceptRequest(
  uint256 requestId,
  uint256 quantity,
  address recipient,
  uint256[] calldata additionalFees,
  address[] calldata additionalFeeRecipients
) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`requestId`|`uint256`|The ID of the request.|
|`quantity`|`uint256`|The quantity of tokens to accept.|
|`recipient`|`address`|The recipient of the accepted tokens.|
|`additionalFees`|`uint256[]`|The additional fees to pay.|
|`additionalFeeRecipients`|`address[]`|The addresses to send the additional fees to.|


### cancelRequest

Cancels a request.


```solidity
function cancelRequest(uint256 requestId) external nonReentrant;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`requestId`|`uint256`|The ID of the request.|


### cancelRequestBatch

Cancels requests.


```solidity
function cancelRequestBatch(uint256[] calldata requestIds) external nonReentrant;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`requestIds`|`uint256[]`|The IDs of the requests.|


### _cancelRequest

Performs cancellation of a request.


```solidity
function _cancelRequest(uint256 requestId) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`requestId`|`uint256`|The ID of the request.|


### invalidateRequests

Invalidates all current requests for the msg.sender.


```solidity
function invalidateRequests() external;
```

### invalidateRequests

Invalidates all current requests for the msg.sender.


```solidity
function invalidateRequests(address tokenContract) external;
```

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


```solidity
function isRequestValid(uint256 requestId, uint256 quantity) public view returns (bool valid, Request memory request);
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


### _isExpired

Checks if a request has expired.


```solidity
function _isExpired(Request memory request) internal view returns (bool isExpired);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`request`|`Request`|The request to check.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`isExpired`|`bool`|True if the request has expired.|


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


