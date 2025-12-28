// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20_Harness} from "./ERC20_Harness.sol";
import {ConfidentialERC20} from "../src/ConfidentialERC20.sol";
import {TestSetup} from "./TestSetup.sol";
import {inEuint128, euint128} from "@fhenixprotocol/cofhe-foundry-mocks/FHE.sol";

contract ConfidentialERC20Test is TestSetup {
    ERC20_Harness public wBTC;
    ConfidentialERC20 eBTC;

    function setUp() public override {
        super.setUp();

        wBTC = new ERC20_Harness("Wrapped BTC", "wBTC", 8);
        vm.label(address(wBTC), "wBTC");

        eBTC = new ConfidentialERC20(wBTC, "eBTC");
        vm.label(address(eBTC), "eBTC");
    }

    // TESTS

    function test_Constructor() public view {
        assertEq(
            eBTC.name(),
            "Confidential Wrapped BTC",
            "ConfidentialERC20 name correct"
        );
        assertEq(eBTC.symbol(), "eBTC", "ConfidentialERC20 symbol correct");
        assertEq(eBTC.decimals(), 8, "ConfidentialERC20 decimals correct");
        assertEq(
            address(eBTC.erc20()),
            address(wBTC),
            "ConfidentialERC20 underlying ERC20 correct"
        );
    }

    function test_FHERC20InvalidErc20() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ConfidentialERC20.FHERC20InvalidErc20.selector,
                address(eBTC)
            )
        );
        new ConfidentialERC20(eBTC, "eBTC");
    }

    function test_isFherc20() public {
        assertEq(eBTC.isFherc20(), true, "eBTC is FHERC20");
    }

    function test_Symbol() public {
        ERC20_Harness TEST = new ERC20_Harness("Test Token", "TEST", 18);
        ConfidentialERC20 eTEST = new ConfidentialERC20(TEST, "");

        assertEq(eTEST.name(), "Confidential Test Token", "eTEST name correct");
        assertEq(eTEST.symbol(), "eTEST", "eTEST symbol correct");
        assertEq(eTEST.decimals(), TEST.decimals(), "eTEST decimals correct");
        assertEq(
            address(eTEST.erc20()),
            address(TEST),
            "eTEST underlying ERC20 correct"
        );

        eTEST.updateSymbol("encTEST");
        assertEq(eTEST.symbol(), "encTEST", "eTEST symbol updated correct");
    }

    function test_encrypt() public {
        assertEq(eBTC.totalSupply(), 0, "Total indicated supply init 0");
        assertEq(
            euint128.unwrap(eBTC.encTotalSupply()),
            0,
            "Total supply not initialized (hash is 0)"
        );

        // Mint wBTC
        wBTC.mint(bob, 10e8);
        vm.prank(bob);
        wBTC.approve(address(eBTC), 10e8);

        // 1st TX, indicated + 5001, true + 1e8

        uint256 value = 1e8;

        _prepExpectERC20BalancesChange(wBTC, bob);
        _prepExpectFHERC20BalancesChange(eBTC, bob);

        _expectERC20Transfer(wBTC, bob, address(eBTC), value);
        _expectFHERC20Transfer(eBTC, address(0), bob);

        vm.prank(bob);
        eBTC.encrypt(bob, uint128(value));

        _expectERC20BalancesChange(wBTC, bob, -1 * int256(value));
        _expectFHERC20BalancesChange(
            eBTC,
            bob,
            _ticksToIndicated(eBTC, 5001),
            int256(value)
        );

        assertEq(
            eBTC.totalSupply(),
            uint256(_ticksToIndicated(eBTC, 5001)),
            "Total indicated supply increases"
        );
        CFT.assertHashValue(
            eBTC.encTotalSupply(),
            uint128(value),
            "Total supply 1e8"
        );

        // 2nd TX, indicated + 1, true + 1e8

        _prepExpectERC20BalancesChange(wBTC, bob);
        _prepExpectFHERC20BalancesChange(eBTC, bob);

        _expectERC20Transfer(wBTC, bob, address(eBTC), value);
        _expectFHERC20Transfer(eBTC, address(0), bob);

        vm.prank(bob);
        eBTC.encrypt(bob, uint128(value));

        _expectERC20BalancesChange(wBTC, bob, -1 * int256(value));
        _expectFHERC20BalancesChange(
            eBTC,
            bob,
            _ticksToIndicated(eBTC, 1),
            int256(value)
        );
    }

    function test_decrypt() public {
        assertEq(eBTC.totalSupply(), 0, "Total supply init 0");

        // Mint and encrypt wBTC
        wBTC.mint(bob, 10e8);

        vm.prank(bob);
        wBTC.approve(address(eBTC), 10e8);

        vm.prank(bob);
        eBTC.encrypt(bob, 10e8);

        // TX

        uint256 value = 1e8;

        _prepExpectERC20BalancesChange(wBTC, bob);
        _prepExpectFHERC20BalancesChange(eBTC, bob);

        _expectFHERC20Transfer(eBTC, bob, address(0));

        vm.prank(bob);
        eBTC.decrypt(bob, uint128(value));

        // Decrypt inserts a claimable amount into the user's claimable set

        ConfidentialERC20.Claim[] memory claims = eBTC.getUserClaims(bob);
        assertEq(claims.length, 1, "Bob has 1 claimable amount");
        uint256 claimableCtHash = claims[0].ctHash;
        assertEq(
            eBTC.getClaim(claimableCtHash).claimed,
            false,
            "Claimable amount not claimed"
        );
        CFT.assertHashValue(
            claimableCtHash,
            uint128(value),
            "Claimable amount 1e8"
        );

        // Claiming the amount will remove it from the user's claimable set

        vm.warp(block.timestamp + 11);

        _expectERC20Transfer(wBTC, address(eBTC), bob, value);
        eBTC.claimDecrypted(claimableCtHash);

        _expectERC20BalancesChange(wBTC, bob, int256(value));
        _expectFHERC20BalancesChange(
            eBTC,
            bob,
            -1 * _ticksToIndicated(eBTC, 1),
            -1 * int256(value)
        );

        assertEq(
            eBTC.totalSupply(),
            uint256(_ticksToIndicated(eBTC, 5000)),
            "Total indicated supply decreases"
        );
        CFT.assertHashValue(
            eBTC.encTotalSupply(),
            uint128(10e8 - value),
            "Total supply decreases"
        );
    }
}
