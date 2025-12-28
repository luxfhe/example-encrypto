// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {FHERC20} from "./FHERC20_Harness.sol";
import {ERC20_Harness, WETH_Harness} from "./ERC20_Harness.sol";
import {ConfidentialERC20} from "../src/ConfidentialERC20.sol";
import {ConfidentialETH} from "../src/ConfidentialETH.sol";
import {RedactedCore} from "../src/RedactedCore.sol";
import {TestSetup} from "./TestSetup.sol";
import {IWETH} from "../src/interfaces/IWETH.sol";

contract RedactedCoreTest is TestSetup {
    IWETH public wETH;
    ConfidentialETH public eETH;

    address owner = address(129);
    RedactedCore public redactedCore;

    function setUp() public override {
        super.setUp();

        wETH = new WETH_Harness();
        vm.label(address(wETH), "wETH");

        eETH = new ConfidentialETH(wETH);
        vm.label(address(eETH), "eETH");

        vm.prank(owner);
        redactedCore = new RedactedCore(wETH, eETH);
        vm.label(address(redactedCore), "RedactedCore");
    }

    // REDACTED CORE TESTS

    function test_Constructor() public view {
        assertEq(address(redactedCore.wETH()), address(wETH), "wETH correct");
        assertEq(address(redactedCore.eETH()), address(eETH), "eETH correct");
        assertEq(redactedCore.getIsWETH(address(wETH)), true);
    }

    error OwnableUnauthorizedAccount(address account);

    function test_updateStablecoin() public {
        ERC20_Harness USDC = new ERC20_Harness("Circle USD", "USDC", 6);

        // onlyOwner

        address unauthorized = address(130);

        vm.expectRevert(
            abi.encodeWithSelector(
                OwnableUnauthorizedAccount.selector,
                unauthorized
            )
        );
        vm.prank(unauthorized);
        redactedCore.updateStablecoin(address(USDC), true);

        // success

        assertEq(
            redactedCore.getIsStablecoin(address(USDC)),
            false,
            "USDC is not stablecoin"
        );
        vm.prank(owner);
        redactedCore.updateStablecoin(address(USDC), true);
        assertEq(
            redactedCore.getIsStablecoin(address(USDC)),
            true,
            "USDC is a stablecoin"
        );
    }

    function test_deployFherc20() public {
        ERC20_Harness USDC = new ERC20_Harness("Circle USD", "USDC", 6);
        vm.prank(owner);
        redactedCore.updateStablecoin(address(USDC), true);

        RedactedCore.MappedERC20[] memory deployedFherc20s = redactedCore
            .getDeployedFherc20s();
        assertEq(deployedFherc20s.length, 0, "No FHERC20s deployed");

        // revert - stablecoin

        vm.expectRevert(
            abi.encodeWithSelector(RedactedCore.Invalid_Stablecoin.selector)
        );
        redactedCore.deployFherc20(USDC);

        // revert - wETH

        vm.expectRevert(
            abi.encodeWithSelector(RedactedCore.Invalid_WETH.selector)
        );
        redactedCore.deployFherc20(wETH);

        deployedFherc20s = redactedCore.getDeployedFherc20s();
        assertEq(deployedFherc20s.length, 0, "No FHERC20s deployed");

        // success

        ERC20_Harness wBTC = new ERC20_Harness("Wrapped BTC", "wBTC", 8);

        vm.expectEmit(true, false, false, false);
        // Address of ewBTC unknown at this point
        emit RedactedCore.Fherc20Deployed(address(wBTC), address(0));
        redactedCore.deployFherc20(wBTC);

        // Expectations after deploy

        address deployedFherc20 = redactedCore.getFherc20(address(wBTC));
        assertNotEq(deployedFherc20, address(0), "ewBTC deployed");

        deployedFherc20s = redactedCore.getDeployedFherc20s();
        assertEq(deployedFherc20s.length, 1, "1 FHERC20 deployed");
        assertEq(deployedFherc20s[0].erc20, address(wBTC), "wBTC deployed");
        assertEq(
            deployedFherc20s[0].fherc20,
            deployedFherc20,
            "deployed ewBTC matches"
        );

        // revert - already deployed

        vm.expectRevert(
            abi.encodeWithSelector(
                RedactedCore.Invalid_AlreadyDeployed.selector
            )
        );
        redactedCore.deployFherc20(wBTC);
    }

    function test_updateFherc20Symbol() public {
        ERC20_Harness wBTC = new ERC20_Harness("Wrapped BTC", "wBTC", 8);

        // init

        redactedCore.deployFherc20(wBTC);
        ConfidentialERC20 eBTC = ConfidentialERC20(
            redactedCore.getFherc20(address(wBTC))
        );
        assertEq(eBTC.symbol(), "ewBTC", "ewBTC initial symbol");

        // onlyOwner

        address unauthorized = address(130);

        vm.expectRevert(
            abi.encodeWithSelector(
                OwnableUnauthorizedAccount.selector,
                unauthorized
            )
        );
        vm.prank(unauthorized);
        redactedCore.updateFherc20Symbol(eBTC, "eBTC");

        // success

        vm.prank(owner);
        redactedCore.updateFherc20Symbol(eBTC, "eBTC");
        assertEq(eBTC.symbol(), "eBTC", "ewBTC symbol updated to eBTC");
    }

    function test_EncryptFromCore() public {
        ERC20_Harness wBTC = new ERC20_Harness("Wrapped BTC", "wBTC", 8);
        redactedCore.deployFherc20(wBTC);

        ConfidentialERC20 eBTC = ConfidentialERC20(
            redactedCore.getFherc20(address(wBTC))
        );
        assertEq(eBTC.isFherc20(), true, "eBTC is FHERC20");

        // Setup

        uint256 value = 1e8;

        wBTC.mint(bob, 10e8);
        vm.prank(bob);
        wBTC.approve(address(eBTC), value);

        // success

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
    }
}
