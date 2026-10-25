// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {BitesToken} from "../src/BitesToken.sol";

/// @dev Drives successful and failing calls in random order. Every failing call must revert with the
/// exact error and leave balances, allowances and supply untouched, which the invariants then check
/// against an independent model.
contract BitesAdversarialHandler is Test {
    BitesToken private immutable token;
    address[5] private actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    uint256 public successfulCalls;
    uint256 public rejectedCalls;
    uint256 public movedVolume;

    constructor(BitesToken token_, address[5] memory actors_, uint256 supply) {
        token = token_;
        actors = actors_;
        expectedBalance[actors_[0]] = supply;
    }

    function actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actor(fromSeed);
        address to = actor(toSeed);
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
        movedVolume += amount;
        ++successfulCalls;
    }

    function transferTooMuch(uint256 fromSeed, uint256 toSeed, uint256 excess) external {
        address from = actor(fromSeed);
        address to = actor(toSeed);
        uint256 balance = expectedBalance[from];
        uint256 amount = balance + bound(excess, 1, type(uint256).max - balance);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(from);
        token.transfer(to, amount);
        ++rejectedCalls;
    }

    function transferToZero(uint256 fromSeed, uint256 amount) external {
        address from = actor(fromSeed);
        amount = bound(amount, 0, expectedBalance[from]);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(from);
        token.transfer(address(0), amount);
        ++rejectedCalls;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool unlimited) external {
        address owner = actor(ownerSeed);
        address spender = actor(spenderSeed);
        if (unlimited) amount = type(uint256).max;
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
        ++successfulCalls;
    }

    function approveZeroSpender(uint256 ownerSeed, uint256 amount) external {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(actor(ownerSeed));
        token.approve(address(0), amount);
        ++rejectedCalls;
    }

    function transferFrom(uint256 fromSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address from = actor(fromSeed);
        address spender = actor(spenderSeed);
        address to = actor(toSeed);
        uint256 approved = expectedAllowance[from][spender];
        uint256 balance = expectedBalance[from];
        amount = bound(amount, 0, approved < balance ? approved : balance);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
        if (approved != type(uint256).max) expectedAllowance[from][spender] -= amount;
        movedVolume += amount;
        ++successfulCalls;
    }

    function transferFromBeyondAllowance(uint256 fromSeed, uint256 spenderSeed, uint256 toSeed, uint256 excess)
        external
    {
        address from = actor(fromSeed);
        address spender = actor(spenderSeed);
        uint256 approved = expectedAllowance[from][spender];
        if (approved == type(uint256).max) return;
        uint256 amount = approved + bound(excess, 1, type(uint256).max - approved);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount)
        );
        vm.prank(spender);
        token.transferFrom(from, actor(toSeed), amount);
        ++rejectedCalls;
    }

    function transferFromBeyondBalance(uint256 fromSeed, uint256 spenderSeed, uint256 toSeed, uint256 excess) external {
        address from = actor(fromSeed);
        address spender = actor(spenderSeed);
        uint256 balance = expectedBalance[from];
        uint256 amount = balance + bound(excess, 1, type(uint256).max - balance);
        // Give exactly enough allowance so the balance check is the one that fails.
        vm.prank(from);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[from][spender] = amount;
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(spender);
        token.transferFrom(from, actor(toSeed), amount);
        ++rejectedCalls;
    }

    function transferFromToZero(uint256 fromSeed, uint256 spenderSeed, uint256 amount) external {
        address from = actor(fromSeed);
        address spender = actor(spenderSeed);
        uint256 approved = expectedAllowance[from][spender];
        uint256 balance = expectedBalance[from];
        amount = bound(amount, 0, approved < balance ? approved : balance);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(from, address(0), amount);
        ++rejectedCalls;
    }
}

contract BitesAdversarialInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    BitesToken private token;
    BitesAdversarialHandler private handler;
    address[5] private actors;

    function setUp() public {
        token = new BitesToken();
        actors = [makeAddr("holder"), makeAddr("trader"), makeAddr("spender"), makeAddr("pool"), address(this)];
        handler = new BitesAdversarialHandler(token, actors, SUPPLY);
        // The deployer (this test) keeps nothing; the whole supply starts with actors[0].
        assertTrue(token.transfer(actors[0], SUPPLY));

        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = BitesAdversarialHandler.transfer.selector;
        selectors[1] = BitesAdversarialHandler.transferTooMuch.selector;
        selectors[2] = BitesAdversarialHandler.transferToZero.selector;
        selectors[3] = BitesAdversarialHandler.approve.selector;
        selectors[4] = BitesAdversarialHandler.approveZeroSpender.selector;
        selectors[5] = BitesAdversarialHandler.transferFrom.selector;
        selectors[6] = BitesAdversarialHandler.transferFromBeyondAllowance.selector;
        selectors[7] = BitesAdversarialHandler.transferFromBeyondBalance.selector;
        selectors[8] = BitesAdversarialHandler.transferFromToZero.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_balancesMatchModelAndSumToFixedSupply() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            uint256 balance = token.balanceOf(actors[i]);
            assertEq(balance, handler.expectedBalance(actors[i]));
            sum += balance;
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_allowancesMatchModel() public view {
        for (uint256 i; i < actors.length; ++i) {
            for (uint256 j; j < actors.length; ++j) {
                assertEq(token.allowance(actors[i], actors[j]), handler.expectedAllowance(actors[i], actors[j]));
            }
            assertEq(token.allowance(actors[i], address(0)), 0);
        }
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_metadataNeverChanges() public view {
        assertEq(token.name(), "bites");
        assertEq(token.symbol(), "BIT");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
    }
}
