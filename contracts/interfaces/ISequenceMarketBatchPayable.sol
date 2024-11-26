// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import {ISequenceMarket} from "./ISequenceMarket.sol";

interface ISequenceMarketBatchPayableFunctions {

  /**
   * Accepts requests.
   * @param requestIds The IDs of the requests.
   * @param quantities The quantities of tokens to accept.
   * @param recipients The recipients of the accepted tokens.
   * @param additionalFees The additional fees to pay.
   * @param additionalFeeRecipients The addresses to send the additional fees to.
   * @dev Additional fees are applied to each request.
   */
  function acceptRequestBatchPayable(
    uint256[] calldata requestIds,
    uint256[] calldata quantities,
    address[] calldata recipients,
    uint256[] calldata additionalFees,
    address[] calldata additionalFeeRecipients
  )
    external payable;
}

// solhint-disable-next-line no-empty-blocks
interface ISequenceMarketBatchPayable is ISequenceMarket, ISequenceMarketBatchPayableFunctions {}
