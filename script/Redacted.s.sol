// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {BaseERC20} from "./BaseERC20.sol";
import {ConfidentialERC20} from "../src/ConfidentialERC20.sol";
import {ChainJsonUtils} from "./ChainJsonUtils.sol";

contract Redacted is Script, ChainJsonUtils {
    modifier broadcast() {
        // `--account` is set in script call
        vm.startBroadcast();
        _;
        vm.stopBroadcast();
    }

    function deployConfidentialERC20(
        string memory name,
        string memory symbol,
        uint8 decimals
    ) public broadcast loadChain {
        BaseERC20 erc20 = new BaseERC20(name, symbol, decimals);
        ConfidentialERC20 fherc20 = new ConfidentialERC20(erc20, "");

        writeContractAddress(string.concat(name, " ERC20"), address(erc20));
        writeContractAddress(
            string.concat(name, " ConfidentialERC20"),
            address(fherc20)
        );
    }
}
