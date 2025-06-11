// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

contract MockSequencerFeed {
    constructor() {}

    uint8 _decimals = 8;

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        roundId = 100;
        answer = 0; // active
        startedAt = 100; // long before the current time
        updatedAt = block.timestamp;
        answeredInRound = 100;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }
}
