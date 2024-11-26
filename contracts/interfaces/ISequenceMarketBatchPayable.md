# ISequenceMarketBatchPayable

Inherits [ISequenceMarket](./ISequenceMarket.md).

## Functions
### acceptRequestBatchPayable

Accepts requests.

*Additional fees are applied to each request.*


```solidity
function acceptRequestBatchPayable(
  uint256[] calldata requestIds,
  uint256[] calldata quantities,
  address[] calldata recipients,
  uint256[] calldata additionalFees,
  address[] calldata additionalFeeRecipients
) external payable;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`requestIds`|`uint256[]`|The IDs of the requests.|
|`quantities`|`uint256[]`|The quantities of tokens to accept.|
|`recipients`|`address[]`|The recipients of the accepted tokens.|
|`additionalFees`|`uint256[]`|The additional fees to pay.|
|`additionalFeeRecipients`|`address[]`|The addresses to send the additional fees to.|


