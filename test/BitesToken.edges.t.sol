// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {BitesToken} from "../src/BitesToken.sol";

/// @dev Deploys the token and moves it within one transaction, as a launch factory would.
contract OneTxLauncher {
    function launch(address[] calldata recipients, uint256[] calldata amounts)
        external
        returns (BitesToken token, uint256 left)
    {
        token = new BitesToken();
        for (uint256 i; i < recipients.length; ++i) {
            require(token.transfer(recipients[i], amounts[i]), "transfer failed");
        }
        left = token.balanceOf(address(this));
    }
}

contract BitesTokenEdgesTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;

    BitesToken private token;
    address private alice;
    address private bob;
    address private spender;

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
        token = new BitesToken();
    }

    function test_supplyConstantIsExactlyOneBillionWholeTokens() public view {
        assertEq(token.INITIAL_SUPPLY(), 1e27);
        assertEq(token.totalSupply(), token.INITIAL_SUPPLY());
        assertEq(token.totalSupply() / 10 ** token.decimals(), 1_000_000_000);
        assertEq(token.totalSupply() % 10 ** token.decimals(), 0);
    }

    function test_eachDeploymentMintsItsOwnSupplyOnly() public {
        BitesToken second = new BitesToken();
        assertEq(second.totalSupply(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertTrue(second.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_launchInOneTransactionDistributesExactly() public {
        OneTxLauncher launcher = new OneTxLauncher();
        address[] memory recipients = new address[](3);
        uint256[] memory amounts = new uint256[](3);
        recipients[0] = makeAddr("distributor");
        recipients[1] = makeAddr("pool manager");
        recipients[2] = makeAddr("requester");
        amounts[0] = SUPPLY / 10;
        amounts[1] = SUPPLY * 45 / 100;
        amounts[2] = SUPPLY - amounts[0] - amounts[1];
        (BitesToken launched, uint256 left) = launcher.launch(recipients, amounts);
        assertEq(left, 0);
        for (uint256 i; i < recipients.length; ++i) {
            assertEq(launched.balanceOf(recipients[i]), amounts[i]);
        }
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function test_launchOverspendRevertsWholeDeployment() public {
        OneTxLauncher launcher = new OneTxLauncher();
        address[] memory recipients = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        recipients[0] = alice;
        recipients[1] = bob;
        amounts[0] = SUPPLY;
        amounts[1] = 1;
        vm.expectRevert();
        launcher.launch(recipients, amounts);
    }

    function test_transferOneWeiMoreThanSupplyReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transfer(alice, SUPPLY + 1);
    }

    function test_transferMaxUintReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(alice, type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_oneWeiTransfer() public {
        assertTrue(token.transfer(alice, 1));
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 1));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 1);
    }

    function test_unlimitedAllowanceStillCannotExceedBalance() public {
        assertTrue(token.transfer(alice, 5));
        vm.prank(alice);
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 5, 6));
        vm.prank(spender);
        token.transferFrom(alice, bob, 6);
        assertEq(token.allowance(alice, spender), type(uint256).max);
        assertEq(token.balanceOf(alice), 5);
    }

    function test_allowanceOneBelowMaxIsDecremented() public {
        uint256 approved = type(uint256).max - 1;
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), approved - 1);
    }

    function test_spenderCanSendToThemselves() public {
        assertTrue(token.approve(spender, 7));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), spender, 7));
        assertEq(token.balanceOf(spender), 7);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_selfApprovalStillRequiredForOwnTransferFrom() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), alice, 1);
        assertTrue(token.approve(address(this), 1));
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), address(this)), 0);
        assertEq(token.balanceOf(alice), 1);
    }

    function test_allowanceToAddressZeroOwnerCannotBeSpent() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(0), alice, 1);
    }

    function test_approvalsArePerOwner() public {
        assertTrue(token.transfer(alice, 100));
        assertTrue(token.approve(spender, 100));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.balanceOf(alice), 100);
    }

    function test_unknownSelectorReverts() public {
        (bool ok,) = address(token).call(abi.encodeWithSignature("increaseAllowance(address,uint256)", spender, 1));
        assertFalse(ok);
        (ok,) = address(token).call(hex"deadbeef");
        assertFalse(ok);
        assertEq(token.allowance(address(this), spender), 0);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_approveSetsExactValue(address owner, address to, uint256 first, uint256 second) public {
        vm.assume(owner != address(0) && to != address(0));
        vm.startPrank(owner);
        assertTrue(token.approve(to, first));
        assertEq(token.allowance(owner, to), first);
        assertTrue(token.approve(to, second));
        vm.stopPrank();
        assertEq(token.allowance(owner, to), second);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_transferFromBeyondBalanceRevertsAndKeepsAllowance(uint256 held, uint256 amount, bool unlimited)
        public
    {
        held = bound(held, 0, SUPPLY);
        amount = bound(amount, held + 1, type(uint256).max);
        uint256 approved = unlimited ? type(uint256).max : amount;
        assertTrue(token.transfer(alice, held));
        vm.prank(alice);
        assertTrue(token.approve(spender, approved));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, held, amount));
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), approved);
        assertEq(token.balanceOf(alice), held);
        assertEq(token.balanceOf(bob), 0);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_strangerCannotMoveHolderFunds(address stranger, uint256 held, uint256 amount) public {
        vm.assume(stranger != alice);
        held = bound(held, 1, SUPPLY);
        amount = bound(amount, 1, held);
        assertTrue(token.transfer(alice, held));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, stranger, 0, amount));
        vm.prank(stranger);
        token.transferFrom(alice, stranger, amount);
        assertEq(token.balanceOf(alice), held);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_chainOfTransfersConservesSupply(uint256 a, uint256 b, uint256 c) public {
        a = bound(a, 0, SUPPLY);
        assertTrue(token.transfer(alice, a));
        b = bound(b, 0, a);
        vm.prank(alice);
        assertTrue(token.transfer(bob, b));
        c = bound(c, 0, b);
        vm.prank(bob);
        assertTrue(token.transfer(address(this), c));
        assertEq(token.balanceOf(address(this)), SUPPLY - a + c);
        assertEq(token.balanceOf(alice), a - b);
        assertEq(token.balanceOf(bob), b - c);
        assertEq(token.balanceOf(address(this)) + token.balanceOf(alice) + token.balanceOf(bob), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_selfTransferNeverChangesBalance(uint256 held, uint256 amount) public {
        held = bound(held, 0, SUPPLY);
        amount = bound(amount, 0, held);
        assertTrue(token.transfer(alice, held));
        vm.prank(alice);
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(alice), held);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
