// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

interface IPasselNFT {
    function totalSupply() external view returns (uint256 totalSupply);
    function ownerOf(uint256 tokenId) external view returns (address owner);
}
