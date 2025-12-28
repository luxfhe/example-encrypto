// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {FHERC20, FHERC20_Harness} from "./FHERC20_Harness.sol";
import {IFHERC20} from "../src/interfaces/IFHERC20.sol";
import {ERC20, ERC20_Harness} from "./ERC20_Harness.sol";
import {ConfidentialERC20} from "../src/ConfidentialERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import {FHERC20SigUtils} from "./FHERC20SigUtils.sol";
import {CoFheTest} from "@fhenixprotocol/cofhe-foundry-mocks/CoFheTest.sol";
import {euint128} from "@fhenixprotocol/cofhe-foundry-mocks/FHE.sol";

abstract contract TestSetup is Test, IERC20Errors {
    CoFheTest public CFT;
    // USERS

    address public deployer = 0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84;
    address public sender = 0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496;
    address public dead = 0x000000000000000000000000000000000000dEaD;

    address payable public bob;
    uint256 public bobPK;
    address payable public alice;
    uint256 public alicePK;
    address payable public carol = payable(address(102));
    address payable public eve = payable(address(103));
    address payable[4] public users;

    FHERC20SigUtils internal sigUtils;

    function initUsers() public {
        (address bobTemp, uint256 bobPKTemp) = makeAddrAndKey("bob");
        (address aliceTemp, uint256 alicePKTemp) = makeAddrAndKey("alice");
        bob = payable(bobTemp);
        bobPK = bobPKTemp;
        alice = payable(aliceTemp);
        alicePK = alicePKTemp;
        users = [bob, alice, carol, eve];
    }

    // LABELS

    function label() public {
        vm.label(deployer, "deployer");
        vm.label(sender, "sender");
        vm.label(dead, "dead");

        vm.label(bob, "bob");
        vm.label(alice, "alice");
        vm.label(carol, "carol");
        vm.label(eve, "eve");

        vm.label(address(sigUtils), "sigUtils");

        vm.label(address(XXX), "XXX");
    }

    // FHERC20 TESTS

    FHERC20_Harness public XXX;
    string public xxxName = "Test FHERC20 XXX";
    string public xxxSymbol = "eXXX";
    uint8 public xxxDecimals = 18;

    // SETUP

    function setUp() public virtual {
        CFT = new CoFheTest(false);

        initUsers();

        sigUtils = new FHERC20SigUtils();

        XXX = new FHERC20_Harness(xxxName, xxxSymbol, xxxDecimals);

        label();
    }

    // UTILS

    function formatWithDecimals(
        int256 value,
        uint8 decimals,
        uint8 decimalsToShow
    ) public pure returns (string memory) {
        require(decimalsToShow <= decimals, "Too many decimals to show");

        // Handle sign
        bool isNegative = value < 0;
        uint256 absValue = isNegative ? uint256(-value) : uint256(value);

        // Factor for rounding (10^(decimals - decimalsToShow))
        uint256 roundFactor = 10 ** (decimals - decimalsToShow);
        uint256 roundedValue = (absValue + roundFactor / 2) / roundFactor; // Apply rounding

        // Convert rounded value to string
        string memory strValue = Strings.toString(roundedValue);
        bytes memory strBytes = bytes(strValue);
        uint256 len = strBytes.length;

        if (decimalsToShow == 0) {
            return
                isNegative ? string(abi.encodePacked("-", strValue)) : strValue; // No decimal places required
        }

        if (len <= decimalsToShow) {
            // Add leading zeros for small values
            string memory leadingZeros = new string(decimalsToShow - len + 2); // "0."
            bytes memory leadingBytes = bytes(leadingZeros);
            leadingBytes[0] = "0";
            leadingBytes[1] = ".";
            for (uint256 i = 2; i < leadingBytes.length; i++) {
                leadingBytes[i] = "0";
            }
            return
                isNegative
                    ? string(
                        abi.encodePacked("-", string(leadingBytes), strValue)
                    )
                    : string(abi.encodePacked(string(leadingBytes), strValue));
        } else {
            uint256 integerPartLength = len - decimalsToShow;
            bytes memory result = new bytes(len + 1);

            for (uint256 i = 0; i < integerPartLength; i++) {
                result[i] = strBytes[i];
            }

            result[integerPartLength] = ".";

            for (uint256 i = integerPartLength; i < len; i++) {
                result[i + 1] = strBytes[i];
            }

            return
                isNegative
                    ? string(abi.encodePacked("-", string(result)))
                    : string(result);
        }
    }

    function formatIndicatedValue(
        FHERC20 token,
        int256 value
    ) public view returns (string memory) {
        return formatWithDecimals(value, token.decimals(), 4);
    }

    event Transfer(address indexed from, address indexed to, uint256 value);

    function _expectERC20Transfer(
        ERC20 token,
        address from,
        address to,
        uint256 value
    ) public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(from, to, value);
    }
    function _expectFHERC20Transfer(
        FHERC20 token,
        address from,
        address to
    ) public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(from, to, token.indicatorTick());
    }

    function _ticksToIndicated(
        FHERC20 token,
        int256 ticks
    ) public view returns (int256) {
        return ticks * int256(token.indicatorTick());
    }

    mapping(address user => uint256 balance) public indicatedBalances;
    mapping(address user => uint256 balance) public encBalances;

    function _prepExpectFHERC20BalancesChange(
        FHERC20 token,
        address account
    ) public {
        indicatedBalances[account] = token.balanceOf(account);
        euint128 encBalance = token.encBalanceOf(account);
        encBalances[account] = CFT.mockStorage(euint128.unwrap(encBalance));
    }
    function _expectFHERC20BalancesChange(
        FHERC20 token,
        address account,
        int256 expectedIndicatedChange,
        int256 expectedEncChange
    ) public view {
        uint256 currIndicated = token.balanceOf(account);
        int256 indicatedChange = int256(currIndicated) -
            int256(indicatedBalances[account]);

        assertEq(
            expectedIndicatedChange,
            indicatedChange,
            string.concat(
                token.symbol(),
                " expected INDICATED balance change incorrect. Expected: ",
                formatIndicatedValue(token, expectedIndicatedChange),
                ", received: ",
                formatIndicatedValue(token, indicatedChange)
            )
        );

        euint128 encBalance = token.encBalanceOf(account);
        uint256 currEncBalance = CFT.mockStorage(euint128.unwrap(encBalance));
        int256 encChange = int256(currEncBalance) -
            int256(encBalances[account]);

        assertEq(
            expectedEncChange,
            encChange,
            string.concat(
                token.symbol(),
                " expected ENC balance change incorrect. Expected: ",
                Strings.toStringSigned(expectedEncChange),
                ", received: ",
                Strings.toStringSigned(encChange)
            )
        );
    }

    mapping(address user => uint256 balance) public erc20Balances;

    function _prepExpectERC20BalancesChange(
        ERC20 token,
        address account
    ) public {
        erc20Balances[account] = token.balanceOf(account);
    }
    function _expectERC20BalancesChange(
        ERC20 token,
        address account,
        int256 expectedChange
    ) public view {
        uint256 currTrue = token.balanceOf(account);
        int256 encChange = int256(currTrue) - int256(erc20Balances[account]);

        assertEq(
            expectedChange,
            encChange,
            string.concat(
                token.symbol(),
                " expected ERC20 balance change incorrect. Expected: ",
                Strings.toStringSigned(expectedChange),
                ", received: ",
                Strings.toStringSigned(encChange)
            )
        );
    }

    function generateTransferFromPermit(
        FHERC20 token,
        uint256 privateKey,
        address owner,
        address spender,
        uint256 value_hash,
        uint256 nonce,
        uint256 deadline
    ) public view returns (IFHERC20.FHERC20_EIP712_Permit memory permit) {
        FHERC20SigUtils.Permit memory sigUtilsPermit = FHERC20SigUtils.Permit({
            owner: owner,
            spender: spender,
            value_hash: value_hash,
            nonce: nonce,
            deadline: block.timestamp + deadline
        });

        bytes32 digest = sigUtils.getTypedDataHash(
            token.DOMAIN_SEPARATOR(),
            sigUtilsPermit
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        permit = IFHERC20.FHERC20_EIP712_Permit({
            owner: owner,
            spender: spender,
            value_hash: value_hash,
            deadline: block.timestamp + deadline,
            v: v,
            r: r,
            s: s
        });
    }

    function generateTransferFromPermit(
        FHERC20 token,
        uint256 privateKey,
        address owner,
        address spender,
        uint256 value_hash
    ) public view returns (IFHERC20.FHERC20_EIP712_Permit memory permit) {
        permit = generateTransferFromPermit(
            token,
            privateKey,
            owner,
            spender,
            value_hash,
            token.nonces(owner),
            1 days
        );
    }
}
