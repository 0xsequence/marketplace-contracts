// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import {IERC165} from "@0xsequence/erc-1155/contracts/interfaces/IERC165.sol";

/**
 * @dev Interface for the NFT Royalty Standard
 */
interface IERC2981 is IERC165 {
  /**
   * @notice Called with the sale price to determine how much royalty
   * is owed and to whom.
   * @param _tokenId - the NFT asset queried for royalty information
   * @param _salePrice - the sale price of the NFT asset specified by _tokenId
   * @return receipient - address of who should be sent the royalty payment
   * @return royaltyAmount - the royalty payment amount for _salePrice
   */
  function royaltyInfo(uint256 _tokenId, uint256 _salePrice)
    external
    view
    returns (address receipient, uint256 royaltyAmount);
}
