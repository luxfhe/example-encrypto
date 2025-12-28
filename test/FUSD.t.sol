// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {FUSD, IFUSDVault} from "../src/FUSD.sol";
import {TestSetup} from "./TestSetup.sol";
import {FHERC20} from "../src/FHERC20.sol";
import {inEuint128, euint128, FHE} from "@fhenixprotocol/cofhe-foundry-mocks/FHE.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/console.sol";

// Mock vault for testing
contract MockFUSDVault is IFUSDVault {
    FUSD public fusd;
    mapping(address => uint256) public redeemed;

    constructor(address _fusd) {
        fusd = FUSD(_fusd);
    }

    function mint(address to, uint128 amount) external {
        fusd.mint(to, amount);
    }

    function redeem(address to, uint128 amount) external override {
        redeemed[to] += amount;
    }

    function getRedeemed(address user) external view returns (uint256) {
        return redeemed[user];
    }
}

contract FUSDTest is TestSetup {
    FUSD public fusdImplementation;
    FUSD public fusd;
    MockFUSDVault public vault;

    function setUp() public override {
        super.setUp();

        // Deploy implementation
        fusdImplementation = new FUSD();

        // Deploy proxy with implementation
        bytes memory initData = abi.encodeWithSelector(
            FUSD.initialize.selector,
            address(0)
        ); // Temp address
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(fusdImplementation),
            initData
        );
        fusd = FUSD(address(proxy));

        // Deploy mock vault
        vault = new MockFUSDVault(address(fusd));

        // Update vault address in FUSD
        vm.startPrank(address(this));
        fusd.updateFUSDVault(address(vault));
        vm.stopPrank();

        // Label addresses for better traces
        vm.label(address(fusd), "FUSD");
        vm.label(address(vault), "FUSDVault");
    }

    // TESTS

    function test_Constructor() public view {
        assertEq(fusd.name(), "FHE US Dollar", "FUSD name correct");
        assertEq(fusd.symbol(), "FUSD", "FUSD symbol correct");
        assertEq(fusd.decimals(), 6, "FUSD decimals correct");
        assertEq(fusd.isFherc20(), true, "FUSD is FHERC20");
    }

    function test_Mint_only() public {
        assertEq(fusd.totalSupply(), 0, "Total supply init 0");

        uint128 mintAmount = 1000000; // 1 FUSD with 6 decimals

        _prepExpectFHERC20BalancesChange(FHERC20(address(fusd)), bob);
        _expectFHERC20Transfer(FHERC20(address(fusd)), address(0), bob);

        vm.prank(address(vault));
        vault.mint(bob, mintAmount);

        _expectFHERC20BalancesChange(
            FHERC20(address(fusd)),
            bob,
            _ticksToIndicated(FHERC20(address(fusd)), 5001),
            int256(uint256(mintAmount))
        );

        assertEq(
            fusd.totalSupply(),
            uint256(_ticksToIndicated(FHERC20(address(fusd)), 5001)),
            "Total indicated supply increases"
        );

        CFT.assertHashValue(
            fusd.encTotalSupply(),
            mintAmount,
            "Total supply matches minted amount"
        );
    }

    function test_MintRevertsIfNotMinter() public {
        uint128 mintAmount = 1000000; // 1 FUSD

        vm.expectRevert(
            abi.encodeWithSelector(FUSD.CallerNotMinter.selector, bob)
        );
        vm.prank(bob);
        fusd.mint(alice, mintAmount);
    }

    function test_MintRevertsIfInvalidRecipient() public {
        uint128 mintAmount = 1000000; // 1 FUSD

        vm.expectRevert(FUSD.InvalidRecipient.selector);
        vm.prank(address(vault));
        fusd.mint(address(0), mintAmount);
    }

    function test_Redeem() public {
        // First mint some tokens to bob
        uint128 mintAmount = 10000000; // 10 FUSD
        vm.prank(address(vault));
        vault.mint(bob, mintAmount);

        // Now redeem some tokens
        uint128 redeemAmount = 1000000; // 1 FUSD

        _prepExpectFHERC20BalancesChange(FHERC20(address(fusd)), bob);
        _expectFHERC20Transfer(FHERC20(address(fusd)), bob, address(0));

        vm.prank(bob);
        fusd.redeem(bob, redeemAmount);

        _expectFHERC20BalancesChange(
            FHERC20(address(fusd)),
            bob,
            -1 * _ticksToIndicated(FHERC20(address(fusd)), 1),
            -1 * int256(uint256(redeemAmount))
        );

        // Check the claim was created
        FUSD.Claim[] memory claims = fusd.getUserClaims(bob);
        assertEq(claims.length, 1, "Bob has 1 claim");
        assertEq(
            claims[0].requestedAmount,
            redeemAmount,
            "Claim amount matches redeemed amount"
        );
        assertEq(claims[0].to, bob, "Claim recipient is bob");
        assertEq(claims[0].claimed, false, "Claim is not yet claimed");
    }

    function test_RedeemRevertsIfInvalidRecipient() public {
        // First mint some tokens to bob
        uint128 mintAmount = 10000000; // 10 FUSD
        vm.prank(address(vault));
        vault.mint(bob, mintAmount);

        // Try to redeem with invalid recipient
        uint128 redeemAmount = 1000000; // 1 FUSD

        vm.expectRevert(FUSD.InvalidRecipient.selector);
        vm.prank(bob);
        fusd.redeem(address(0), redeemAmount);
    }

    function test_ClaimRedeemed() public {
        // First mint some tokens to bob
        uint128 mintAmount = 10000000; // 10 FUSD
        vm.prank(address(vault));
        vault.mint(bob, mintAmount);

        // Redeem some tokens
        uint128 redeemAmount = 1000000; // 1 FUSD
        vm.prank(bob);
        fusd.redeem(bob, redeemAmount);

        // Wait for the decryption to complete
        vm.warp(block.timestamp + 11);

        // Get the claim details
        FUSD.Claim[] memory claims = fusd.getUserClaims(bob);
        uint256 claimCtHash = claims[0].ctHash;

        // Claim the redeemed tokens
        fusd.claimRedeemed(claimCtHash);

        // Verify the claim was processed
        assertEq(
            vault.getRedeemed(bob),
            redeemAmount,
            "Vault received redemption request"
        );

        // Verify claim no longer exists
        FUSD.Claim[] memory claimsAfter = fusd.getUserClaims(bob);
        assertEq(claimsAfter.length, 0, "Claim was removed after processing");
    }

    function test_ClaimRedeemedRevertsIfClaimNotFound() public {
        uint256 nonExistentClaimHash = 12345;

        vm.expectRevert(FUSD.ClaimNotFound.selector);
        fusd.claimRedeemed(nonExistentClaimHash);
    }

    function test_ClaimRedeemedRevertsIfAlreadyClaimed() public {
        // First mint some tokens to bob
        uint128 mintAmount = 10000000; // 10 FUSD
        vm.prank(address(vault));
        vault.mint(bob, mintAmount);

        // Redeem some tokens
        uint128 redeemAmount = 1000000; // 1 FUSD
        vm.prank(bob);
        fusd.redeem(bob, redeemAmount);

        // Wait for the decryption to complete
        vm.warp(block.timestamp + 11);

        // Get the claim details
        FUSD.Claim[] memory claims = fusd.getUserClaims(bob);
        uint256 claimCtHash = claims[0].ctHash;

        // Claim the redeemed tokens
        fusd.claimRedeemed(claimCtHash);

        // Try to claim again
        vm.expectRevert(FUSD.AlreadyClaimed.selector);
        fusd.claimRedeemed(claimCtHash);
    }

    function test_UpdateFUSDVault() public {
        address newVault = address(0x123);

        vm.prank(address(this)); // Default admin
        fusd.updateFUSDVault(newVault);

        MockFUSDVault vault2 = new MockFUSDVault(address(fusd));

        vm.prank(address(this));
        fusd.updateFUSDVault(address(vault2));
    }

    function test_UpdateFUSDVaultRevertsIfNotAdmin() public {
        address newVault = address(0x123);

        vm.expectRevert(
            abi.encodeWithSelector(FUSD.CallerNotAdmin.selector, bob)
        );
        vm.prank(bob);
        fusd.updateFUSDVault(newVault);
    }

    function test_UpdateFUSDVaultRevertsIfInvalidVault() public {
        vm.expectRevert(FUSD.InvalidFUSDVault.selector);
        vm.prank(address(this));
        fusd.updateFUSDVault(address(0));
    }

    function test_GetClaim() public {
        // First mint some tokens to bob
        uint128 mintAmount = 10000000; // 10 FUSD
        vm.prank(address(vault));
        vault.mint(bob, mintAmount);

        // Redeem some tokens
        uint128 redeemAmount = 1000000; // 1 FUSD
        vm.prank(bob);
        fusd.redeem(bob, redeemAmount);

        // Get the claim
        FUSD.Claim[] memory claims = fusd.getUserClaims(bob);
        uint256 claimCtHash = claims[0].ctHash;

        FUSD.Claim memory claim = fusd.getClaim(claimCtHash);
        assertEq(
            claim.requestedAmount,
            redeemAmount,
            "Claim amount matches redeemed amount"
        );
        assertEq(claim.to, bob, "Claim recipient is bob");
        assertEq(claim.claimed, false, "Claim is not yet claimed");

        // Wait for decryption to complete
        vm.warp(block.timestamp + 11);

        // Get updated claim
        claim = fusd.getClaim(claimCtHash);
        assertEq(
            claim.decryptedAmount,
            redeemAmount,
            "Decrypted amount matches requested amount"
        );
        assertEq(claim.decrypted, true, "Claim is marked as decrypted");
    }

    function test_GetUserClaims() public {
        // Initially no claims
        FUSD.Claim[] memory initialClaims = fusd.getUserClaims(bob);
        assertEq(initialClaims.length, 0, "No initial claims");

        // Mint tokens to bob
        uint128 mintAmount = 10000000; // 10 FUSD
        vm.prank(address(vault));
        vault.mint(bob, mintAmount);

        // Redeem some tokens twice
        uint128 redeemAmount1 = 1000000; // 1 FUSD
        vm.prank(bob);
        fusd.redeem(bob, redeemAmount1);

        uint128 redeemAmount2 = 2000000; // 2 FUSD
        vm.prank(bob);
        fusd.redeem(bob, redeemAmount2);

        // Check user claims
        FUSD.Claim[] memory claims = fusd.getUserClaims(bob);
        assertEq(claims.length, 2, "Bob has 2 claims");
        assertEq(
            claims[0].requestedAmount,
            redeemAmount1,
            "First claim amount correct"
        );
        assertEq(
            claims[1].requestedAmount,
            redeemAmount2,
            "Second claim amount correct"
        );
    }

    function test_Upgrade() public {
        // First test that non-admin can't upgrade
        vm.expectRevert();
        vm.prank(bob);
        fusd.upgradeToAndCall(address(123), "");

        // Verify new implementation has correct admin role
        assertTrue(fusd.hasRole(fusd.DEFAULT_ADMIN_ROLE(), address(this)));

        // Deploy new implementation
        FUSD newImplementation = new FUSD();

        // Upgrade to new implementation
        vm.prank(address(this)); // Default admin role
        fusd.upgradeToAndCall(address(newImplementation), "");

        // Verify functionality still works after upgrade
        uint128 mintAmount = 1000000; // 1 FUSD
        vm.prank(address(vault));
        vault.mint(alice, mintAmount);

        uint256 aliceBalance = fusd.balanceOf(alice);
        assertTrue(aliceBalance > 0, "Alice balance updated after upgrade");

        // Verify new implementation has correct admin role
        assertTrue(fusd.hasRole(fusd.DEFAULT_ADMIN_ROLE(), address(this)));
    }

    function test_MintWithOldVaultRevertsAfterUpdate() public {
        address charlie = makeAddr("charlie");
        // First mint some tokens to verify the vault works
        uint128 mintAmount = 1000000;
        vm.prank(address(vault));
        vault.mint(bob, mintAmount);

        // Create a new vault
        MockFUSDVault newVault = new MockFUSDVault(address(fusd));

        // Update to the new vault
        vm.prank(address(this));
        fusd.updateFUSDVault(address(newVault));

        // The old vault cannot mint tokens
        vm.expectRevert(
            abi.encodeWithSelector(
                FUSD.CallerNotMinter.selector,
                address(vault)
            )
        );
        vm.prank(address(vault));
        vault.mint(alice, mintAmount);

        // The new vault can mint tokens (but should be able to)
        vm.prank(address(newVault));
        newVault.mint(charlie, mintAmount);

        // Verify roles
        assertFalse(
            fusd.hasRole(keccak256("MINTER_ROLE"), address(vault)),
            "Old vault no longer has minter role"
        );
        assertTrue(
            fusd.hasRole(keccak256("MINTER_ROLE"), address(newVault)),
            "New vault has minter role"
        );
    }
}
