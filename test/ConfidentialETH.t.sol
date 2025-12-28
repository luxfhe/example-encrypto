// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {FHERC20} from "./FHERC20_Harness.sol";
import {ERC20_Harness, WETH_Harness} from "./ERC20_Harness.sol";
import {ConfidentialETH} from "../src/ConfidentialETH.sol";
import {TestSetup} from "./TestSetup.sol";
import {IWETH} from "../src/interfaces/IWETH.sol";
import {inEuint128, euint128} from "@fhenixprotocol/cofhe-foundry-mocks/FHE.sol";

contract ConfidentialETHTest is TestSetup {
    WETH_Harness public wETH;
    ConfidentialETH public eETH;

    function setUp() public override {
        super.setUp();

        wETH = new WETH_Harness();
        vm.deal(address(wETH), 100e8);
        vm.label(address(wETH), "wETH");

        eETH = new ConfidentialETH(wETH);
        vm.label(address(eETH), "eETH");
    }

    // TESTS

    function test_Constructor() public view {
        assertEq(
            eETH.name(),
            "Confidential Wrapped ETHER",
            "ConfidentialETH name correct"
        );
        assertEq(eETH.symbol(), "eETH", "ConfidentialETH symbol correct");
        assertEq(eETH.decimals(), 18, "ConfidentialETH decimals correct");
        assertEq(
            address(eETH.wETH()),
            address(wETH),
            "ConfidentialETH underlying wETH correct"
        );
    }

    function test_isFherc20() public {
        assertEq(eETH.isFherc20(), true, "eETH is FHERC20");
    }

    function test_encryptWETH() public {
        assertEq(eETH.totalSupply(), 0, "Total supply init 0");

        // Setup

        vm.deal(bob, 100e8);

        vm.prank(bob);
        wETH.deposit{value: 10e8}();

        vm.prank(bob);
        wETH.approve(address(eETH), 10e8);

        // 1st TX, indicated + 5001, true + 1e8

        uint256 value = 1e8;

        _prepExpectERC20BalancesChange(wETH, bob);
        _prepExpectFHERC20BalancesChange(eETH, bob);

        _expectERC20Transfer(wETH, bob, address(eETH), value);
        _expectFHERC20Transfer(eETH, address(0), bob);

        vm.prank(bob);
        eETH.encryptWETH(bob, uint128(value));

        _expectERC20BalancesChange(wETH, bob, -1 * int256(value));
        _expectFHERC20BalancesChange(
            eETH,
            bob,
            _ticksToIndicated(eETH, 5001),
            int256(value)
        );

        assertEq(
            eETH.totalSupply(),
            uint256(_ticksToIndicated(eETH, 5001)),
            "Total indicated supply increases"
        );
        CFT.assertHashValue(
            eETH.encTotalSupply(),
            uint128(value),
            "Total supply 1e8"
        );
    }

    function test_encryptETH() public {
        assertEq(eETH.totalSupply(), 0, "Total supply init 0");

        // Setup

        vm.deal(bob, 100e8);

        // 1st TX, indicated + 5001, true + 1e8

        uint256 value = 1e8;

        uint256 bobEthInit = address(bob).balance;
        _prepExpectFHERC20BalancesChange(eETH, bob);

        _expectFHERC20Transfer(eETH, address(0), bob);

        vm.prank(bob);
        eETH.encryptETH{value: value}(bob);

        uint256 bobEthFinal = address(bob).balance;
        _expectFHERC20BalancesChange(
            eETH,
            bob,
            _ticksToIndicated(eETH, 5001),
            int256(value)
        );

        assertEq(bobEthFinal, bobEthInit - value, "Bob ETH balance decreases");

        assertEq(
            eETH.totalSupply(),
            uint256(_ticksToIndicated(eETH, 5001)),
            "Total indicated supply increases"
        );
        CFT.assertHashValue(
            eETH.encTotalSupply(),
            uint128(value),
            "Total supply 1e8"
        );
    }

    function test_decrypt() public {
        assertEq(
            euint128.unwrap(eETH.encTotalSupply()),
            0,
            "Total supply not initialized (hash is 0)"
        );
        assertEq(eETH.totalSupply(), 0, "Total indicated supply init 0");

        // Setup

        vm.deal(bob, 100e8);

        vm.prank(bob);
        wETH.deposit{value: 10e8}();

        vm.prank(bob);
        wETH.approve(address(eETH), 10e8);

        vm.prank(bob);
        eETH.encryptWETH(bob, 10e8);

        uint256 value = 1e8;

        // Revert if eth call fails

        ERC20_Harness nonReceiverToken = new ERC20_Harness(
            "NON RECEIVER",
            "NON",
            18
        );

        // Call Decrypt (REVERT)
        // NOTE: I can't get this to actually revert :/

        // vm.prank(bob);
        // eETH.decrypt(address(nonReceiverToken), 1e7);

        // // Wait for Decrypt to be resolved

        // vm.warp(block.timestamp + 11);

        // // Expect Revert on withdrawal of claim

        // vm.expectRevert(
        //     abi.encodeWithSelector(ConfidentialETH.ETHTransferFailed.selector)
        // );

        // vm.prank(address(nonReceiverToken));
        // uint256[] memory claimableCtHashes = eETH.userClaimable(
        //     address(nonReceiverToken)
        // );
        // eETH.claimDecrypted(claimableCtHashes[0]);

        // TX (SUCCEED)

        uint256 bobEthInit = address(bob).balance;
        _prepExpectFHERC20BalancesChange(eETH, bob);

        _expectFHERC20Transfer(eETH, bob, address(0));

        vm.prank(bob);
        eETH.decrypt(bob, uint128(value));

        // Decrypt inserts a claimable amount into the user's claimable set

        ConfidentialETH.Claim[] memory claimable = eETH.getUserClaims(bob);
        assertEq(claimable.length, 1, "Bob has 1 claimable amount");
        uint256 claimableCtHash = claimable[0].ctHash;
        assertEq(claimable[0].claimed, false, "Claimable amount not claimed");
        assertEq(
            claimable[0].requestedAmount,
            value,
            "Claimable amount requested"
        );
        assertEq(claimable[0].to, bob, "Claimable amount to bob");
        CFT.assertHashValue(claimableCtHash, value);

        // - On decrypt, the amount is not decrypted yet
        assertEq(
            claimable[0].decryptedAmount,
            0,
            "Decrypted claimable amount not populated yet"
        );
        assertEq(
            claimable[0].decrypted,
            false,
            "Claimable amount has not been decrypted"
        );

        // - after delay, the amount is decrypted successfully
        vm.warp(block.timestamp + 11);
        claimable = eETH.getUserClaims(bob);
        assertEq(
            claimable[0].decryptedAmount,
            value,
            "Decrypted claimable amount correct"
        );
        assertEq(
            claimable[0].decrypted,
            true,
            "Claimable amount has been decrypted"
        );

        // Claiming the amount will remove it from the user's claimable set

        eETH.claimDecrypted(claimableCtHash);

        uint256 bobEthFinal = address(bob).balance;
        _expectFHERC20BalancesChange(
            eETH,
            bob,
            -1 * _ticksToIndicated(eETH, 1),
            -1 * int256(value)
        );

        assertEq(bobEthFinal, bobEthInit + value, "Bob ETH balance increases");

        assertEq(
            eETH.totalSupply(),
            uint256(_ticksToIndicated(eETH, 5000)),
            "Total indicated supply decreases"
        );
        CFT.assertHashValue(
            eETH.encTotalSupply(),
            uint128(10e8 - value),
            "Total supply decreases"
        );
    }
}
