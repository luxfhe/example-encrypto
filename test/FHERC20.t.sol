// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console} from "forge-std/Test.sol";
import {FHERC20} from "./FHERC20_Harness.sol";
import {TestSetup} from "./TestSetup.sol";
import {IFHERC20} from "../src/interfaces/IFHERC20.sol";
import {IFHERC20Errors} from "../src/interfaces/IFHERC20Errors.sol";
import {inEuint128, euint128} from "@fhenixprotocol/cofhe-foundry-mocks/FHE.sol";

contract FHERC20Test is TestSetup {
    function setUp() public override {
        super.setUp();
    }

    // TESTS

    function test_Constructor() public view {
        assertEq(XXX.name(), xxxName, "FHERC20 name correct");
        assertEq(XXX.symbol(), xxxSymbol, "FHERC20 symbol correct");
        assertEq(XXX.decimals(), xxxDecimals, "FHERC20 decimals correct");
        assertEq(
            XXX.balanceOfIsIndicator(),
            true,
            "FHERC20 balanceOfIsIndicator is true"
        );
        assertEq(
            XXX.indicatorTick(),
            10 ** (xxxDecimals - 4),
            "FHERC20 indicatorTick correct"
        );
        assertEq(XXX.isFherc20(), true, "FHERC20 isFherc20 is true");
    }

    function test_indicatedAmountWraparound() public {
        // Balance 9999 -> wraparound -> 5001
        XXX.setUserIndicatedBalance(bob, 9999);
        XXX.mint(bob, 10e18);
        assertEq(
            int256(XXX.balanceOf(bob)),
            _ticksToIndicated(XXX, 5001),
            "Indicated balance overflow wraparound"
        );

        // Balance 1 -> wraparound -> 4999
        XXX.setUserIndicatedBalance(bob, 1);
        XXX.burn(bob, 1e18);
        assertEq(
            int256(XXX.balanceOf(bob)),
            _ticksToIndicated(XXX, 4999),
            "Indicated balance underflow wraparound"
        );

        // Total supply 9999 -> wraparound -> 5001
        XXX.setTotalIndicatedSupply(9999);
        XXX.mint(bob, 10e18);
        assertEq(
            int256(XXX.totalSupply()),
            _ticksToIndicated(XXX, 5001),
            "Total supply overflow wraparound"
        );

        // Total supply 1 -> wraparound -> 4999
        XXX.setTotalIndicatedSupply(1);
        XXX.burn(bob, 1e18);
        assertEq(
            int256(XXX.totalSupply()),
            _ticksToIndicated(XXX, 4999),
            "Total supply underflow wraparound"
        );
    }

    function test_Mint() public {
        assertEq(
            XXX.totalSupply(),
            uint256(_ticksToIndicated(XXX, 0)),
            "Total indicated supply init 0"
        );
        assertEq(
            euint128.unwrap(XXX.encTotalSupply()),
            0,
            "Total supply not initialized (hash is 0)"
        );

        // 1st TX, indicated + 5001, true + 1e18

        uint128 value = 1e18;

        _prepExpectFHERC20BalancesChange(XXX, bob);

        _expectFHERC20Transfer(XXX, address(0), bob);
        XXX.mint(bob, value);

        _expectFHERC20BalancesChange(
            XXX,
            bob,
            _ticksToIndicated(XXX, 5001),
            int128(value)
        );

        assertEq(
            XXX.totalSupply(),
            uint256(_ticksToIndicated(XXX, 5001)),
            "Total indicated supply increases"
        );
        CFT.assertHashValue(XXX.encTotalSupply(), value, "Total supply 1e18");

        // 2nd TX, indicated + 1, true + 1e18

        _prepExpectFHERC20BalancesChange(XXX, bob);

        _expectFHERC20Transfer(XXX, address(0), bob);
        XXX.mint(bob, value);

        _expectFHERC20BalancesChange(
            XXX,
            bob,
            _ticksToIndicated(XXX, 1),
            int128(value)
        );

        // Revert

        vm.expectPartialRevert(ERC20InvalidReceiver.selector);
        XXX.mint(address(0), value);
    }

    function test_Burn() public {
        XXX.mint(bob, 10e18);

        // 1st TX, indicated - 1, true - 1e18

        assertEq(
            XXX.totalSupply(),
            uint256(_ticksToIndicated(XXX, 5001)),
            "Total indicated supply init .5001"
        );
        CFT.assertHashValue(XXX.encTotalSupply(), 10e18);

        _prepExpectFHERC20BalancesChange(XXX, bob);

        _expectFHERC20Transfer(XXX, bob, address(0));
        XXX.burn(bob, 1e18);

        _expectFHERC20BalancesChange(
            XXX,
            bob,
            -1 * _ticksToIndicated(XXX, 1),
            -1 * 1e18
        );
        CFT.assertHashValue(XXX.encTotalSupply(), 9e18);

        assertEq(
            XXX.totalSupply(),
            uint256(_ticksToIndicated(XXX, 5000)),
            "Total indicated supply reduced to .5000"
        );

        // Revert

        vm.expectPartialRevert(ERC20InvalidSender.selector);
        XXX.burn(address(0), 1e18);
    }

    function test_ERC20FunctionsRevert() public {
        XXX.mint(bob, 10e18);
        XXX.mint(alice, 10e18);

        // Transfer

        vm.expectRevert(IFHERC20Errors.FHERC20IncompatibleFunction.selector);
        vm.prank(bob);
        XXX.transfer(alice, 1e18);

        // TransferFrom

        vm.expectRevert(IFHERC20Errors.FHERC20IncompatibleFunction.selector);
        vm.prank(bob);
        XXX.transferFrom(alice, bob, 1e18);

        // Approve

        vm.expectRevert(IFHERC20Errors.FHERC20IncompatibleFunction.selector);
        vm.prank(bob);
        XXX.approve(alice, 1e18);

        // Allowance

        vm.expectRevert(IFHERC20Errors.FHERC20IncompatibleFunction.selector);
        XXX.allowance(bob, alice);
    }

    function test_EncTransfer() public {
        XXX.mint(bob, 10e18);
        XXX.mint(alice, 10e18);
        inEuint128 memory inValue = CFT.createInEuint128(1e18, 0);

        // Reversion - Transfer to 0 address

        vm.expectRevert(
            abi.encodeWithSelector(ERC20InvalidReceiver.selector, address(0))
        );
        vm.prank(bob);
        XXX.encTransfer(address(0), inValue);

        // Success

        _prepExpectFHERC20BalancesChange(XXX, bob);
        _prepExpectFHERC20BalancesChange(XXX, alice);

        _expectFHERC20Transfer(XXX, bob, alice);
        vm.prank(bob);
        XXX.encTransfer(alice, inValue);

        _expectFHERC20BalancesChange(
            XXX,
            bob,
            -1 * _ticksToIndicated(XXX, 1),
            -1 * 1e18
        );
        _expectFHERC20BalancesChange(
            XXX,
            alice,
            _ticksToIndicated(XXX, 1),
            1e18
        );
    }

    function test_EncTransferFrom_Success_BobToAliceViaAlice() public {
        XXX.mint(bob, 10e18);
        XXX.mint(alice, 10e18);
        IFHERC20.FHERC20_EIP712_Permit memory permit;
        inEuint128 memory inValue;

        // Success - Bob -> Alice (called by Alice, nonce = 0)

        inValue = CFT.createInEuint128(1e18, 0);
        permit = generateTransferFromPermit(
            XXX,
            bobPK,
            bob,
            alice,
            inValue.hash
        );

        _prepExpectFHERC20BalancesChange(XXX, bob);
        _prepExpectFHERC20BalancesChange(XXX, alice);

        _expectFHERC20Transfer(XXX, bob, alice);
        vm.prank(alice);
        XXX.encTransferFrom(bob, alice, inValue, permit);

        _expectFHERC20BalancesChange(
            XXX,
            bob,
            -1 * _ticksToIndicated(XXX, 1),
            -1 * 1e18
        );
        _expectFHERC20BalancesChange(
            XXX,
            alice,
            _ticksToIndicated(XXX, 1),
            1e18
        );

        // Success - Bob -> Alice (called by Alice, nonce = 1)

        inValue = CFT.createInEuint128(1e18, 0);
        permit = generateTransferFromPermit(
            XXX,
            bobPK,
            bob,
            alice,
            inValue.hash
        );

        _prepExpectFHERC20BalancesChange(XXX, bob);
        _prepExpectFHERC20BalancesChange(XXX, alice);

        _expectFHERC20Transfer(XXX, bob, alice);
        vm.prank(alice);
        XXX.encTransferFrom(bob, alice, inValue, permit);

        _expectFHERC20BalancesChange(
            XXX,
            bob,
            -1 * _ticksToIndicated(XXX, 1),
            -1 * 1e18
        );
        _expectFHERC20BalancesChange(
            XXX,
            alice,
            _ticksToIndicated(XXX, 1),
            1e18
        );
    }

    function test_EncTransferFrom_Success_BobToAliceViaEve() public {
        XXX.mint(bob, 10e18);
        XXX.mint(alice, 10e18);
        IFHERC20.FHERC20_EIP712_Permit memory permit;

        inEuint128 memory inValue = CFT.createInEuint128(1e18, 0);

        // Valid

        permit = generateTransferFromPermit(XXX, bobPK, bob, eve, inValue.hash);

        _prepExpectFHERC20BalancesChange(XXX, bob);
        _prepExpectFHERC20BalancesChange(XXX, alice);
        _prepExpectFHERC20BalancesChange(XXX, eve);

        _expectFHERC20Transfer(XXX, bob, alice);

        vm.prank(eve);
        XXX.encTransferFrom(bob, alice, inValue, permit);

        _expectFHERC20BalancesChange(
            XXX,
            bob,
            -1 * _ticksToIndicated(XXX, 1),
            -1 * 1e18
        );
        _expectFHERC20BalancesChange(
            XXX,
            alice,
            _ticksToIndicated(XXX, 1),
            1e18
        );
        _expectFHERC20BalancesChange(XXX, eve, _ticksToIndicated(XXX, 0), 0);
    }

    function test_EncTransferFrom_Revert_ERC20InvalidReceiver() public {
        XXX.mint(bob, 10e18);
        XXX.mint(alice, 10e18);
        IFHERC20.FHERC20_EIP712_Permit memory permit;

        // Reversion - Transfer from 0 address

        inEuint128 memory inValue = CFT.createInEuint128(1e18, 0);
        permit = generateTransferFromPermit(
            XXX,
            bobPK,
            bob,
            alice,
            inValue.hash
        );

        vm.expectRevert(
            abi.encodeWithSelector(ERC20InvalidReceiver.selector, address(0))
        );
        vm.prank(alice);
        XXX.encTransferFrom(bob, address(0), inValue, permit);
    }

    function test_EncTransferFrom_Revert_Expired() public {
        XXX.mint(bob, 10e18);
        XXX.mint(alice, 10e18);
        IFHERC20.FHERC20_EIP712_Permit memory permit;

        inEuint128 memory inValue = CFT.createInEuint128(1e18, 0);

        // Valid

        permit = generateTransferFromPermit(
            XXX,
            bobPK,
            bob,
            alice,
            inValue.hash
        );
        vm.prank(alice);
        XXX.encTransferFrom(bob, alice, inValue, permit);

        // Deadline passed - ERC2612ExpiredSignature

        permit = generateTransferFromPermit(
            XXX,
            bobPK,
            bob,
            alice,
            inValue.hash,
            XXX.nonces(bob),
            0
        );
        vm.warp(block.timestamp + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IFHERC20Errors.ERC2612ExpiredSignature.selector,
                permit.deadline
            )
        );
        vm.prank(alice);
        XXX.encTransferFrom(bob, alice, inValue, permit);
    }

    function test_EncTransferFrom_Revert_OwnerMismatch_BobToEve() public {
        XXX.mint(bob, 10e18);
        XXX.mint(alice, 10e18);
        IFHERC20.FHERC20_EIP712_Permit memory permit;

        inEuint128 memory inValue = CFT.createInEuint128(1e18, 0);

        // FHERC20EncTransferFromOwnerMismatch bob -> eve

        inValue = CFT.createInEuint128(1e18, 0);
        permit = generateTransferFromPermit(
            XXX,
            bobPK,
            eve,
            alice,
            inValue.hash
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IFHERC20Errors.FHERC20EncTransferFromOwnerMismatch.selector,
                bob,
                eve
            )
        );
        XXX.encTransferFrom(bob, alice, inValue, permit);
    }

    function test_EncTransferFrom_Revert_OwnerMismatch_EveToBob() public {
        XXX.mint(bob, 10e18);
        XXX.mint(alice, 10e18);
        IFHERC20.FHERC20_EIP712_Permit memory permit;

        inEuint128 memory inValue = CFT.createInEuint128(1e18, 0);

        // FHERC20EncTransferFromOwnerMismatch eve -> bob

        inValue = CFT.createInEuint128(1e18, 0);
        permit = generateTransferFromPermit(
            XXX,
            bobPK,
            bob,
            alice,
            inValue.hash
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IFHERC20Errors.FHERC20EncTransferFromOwnerMismatch.selector,
                eve,
                bob
            )
        );
        XXX.encTransferFrom(eve, alice, inValue, permit);
    }

    function test_EncTransferFrom_Revert_SpenderMismatch() public {
        XXX.mint(bob, 10e18);
        XXX.mint(alice, 10e18);
        IFHERC20.FHERC20_EIP712_Permit memory permit;

        inEuint128 memory inValue = CFT.createInEuint128(1e18, 0);

        // FHERC20EncTransferFromSpenderMismatch

        inValue = CFT.createInEuint128(1e18, 0);
        permit = generateTransferFromPermit(
            XXX,
            bobPK,
            bob,
            alice,
            inValue.hash
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IFHERC20Errors.FHERC20EncTransferFromSpenderMismatch.selector,
                eve,
                alice
            )
        );
        vm.prank(eve);
        XXX.encTransferFrom(bob, eve, inValue, permit);
    }

    function test_EncTransferFrom_Revert_ValueHashMismatch() public {
        XXX.mint(bob, 10e18);
        XXX.mint(alice, 10e18);
        IFHERC20.FHERC20_EIP712_Permit memory permit;

        inEuint128 memory inValue = CFT.createInEuint128(1e18, 0);

        // FHERC20EncTransferFromValueHashMismatch

        inValue = CFT.createInEuint128(2e18, 0);
        inEuint128 memory inValueMismatch = CFT.createInEuint128(2.1e18, 0);
        permit = generateTransferFromPermit(
            XXX,
            bobPK,
            bob,
            alice,
            inValue.hash
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IFHERC20Errors.FHERC20EncTransferFromValueHashMismatch.selector,
                inValueMismatch.hash,
                inValue.hash
            )
        );
        vm.prank(alice);
        XXX.encTransferFrom(bob, alice, inValueMismatch, permit);
    }

    function test_EncTransferFrom_Revert_ERC2612InvalidSigner_SignerNotOwner()
        public
    {
        XXX.mint(bob, 10e18);
        XXX.mint(alice, 10e18);
        IFHERC20.FHERC20_EIP712_Permit memory permit;

        inEuint128 memory inValue = CFT.createInEuint128(1e18, 0);

        // Signer != owner - ERC2612InvalidSigner

        inValue = CFT.createInEuint128(1e18, 0);
        permit = generateTransferFromPermit(
            XXX,
            alicePK,
            bob,
            alice,
            inValue.hash
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IFHERC20Errors.ERC2612InvalidSigner.selector,
                alice,
                bob
            )
        );
        vm.prank(alice);
        XXX.encTransferFrom(bob, alice, inValue, permit);
    }

    function test_EncTransferFrom_Revert_ERC2612InvalidSigner_InvalidNonce()
        public
    {
        XXX.mint(bob, 10e18);
        XXX.mint(alice, 10e18);
        IFHERC20.FHERC20_EIP712_Permit memory permit;

        inEuint128 memory inValue = CFT.createInEuint128(1e18, 0);

        // Invalid nonce - ERC2612InvalidSigner

        permit = generateTransferFromPermit(
            XXX,
            bobPK,
            bob,
            alice,
            inValue.hash,
            XXX.nonces(bob) + 1,
            1 days
        );
        vm.expectPartialRevert(IFHERC20Errors.ERC2612InvalidSigner.selector);
        vm.prank(alice);
        XXX.encTransferFrom(bob, alice, inValue, permit);
    }
}
