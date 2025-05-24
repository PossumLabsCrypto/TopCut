// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

interface ITopCutNFT {
    function mint() external payable returns (uint256);

    function totalSupply() external view returns (uint256 totalSupply);
    function ownerOf(uint256 tokenId) external view returns (address owner);

    function TOPCUT_VAULT() external view returns (address);
    function metadataURI() external view returns (string memory);
    function mintPriceETH() external view returns (uint256);
}
