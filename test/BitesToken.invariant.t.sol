// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {BitesToken} from "../src/BitesToken.sol";

/// @dev Independent accounting model for random sequences over a closed set of holders.
contract BitesTokenHandler is Test {
    BitesToken private immutable token;
    address[4] private actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(BitesToken token_, address[4] memory actors_, uint256 supply) {
        token = token_;
        actors = actors_;
        expectedBalance[actors_[0]] = supply;
    }

    function move(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function spend(uint256 fromSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 approved = expectedAllowance[from][spender];
        uint256 balance = expectedBalance[from];
        amount = bound(amount, 0, approved < balance ? approved : balance);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
        if (approved != type(uint256).max) {
            expectedAllowance[from][spender] -= amount;
        }
    }
}

contract BitesTokenInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    BitesToken private token;
    BitesTokenHandler private handler;
    address[4] private actors;

    function setUp() public {
        token = new BitesToken();
        actors = [makeAddr("alice"), makeAddr("bob"), makeAddr("carol"), makeAddr("dave")];
        assertTrue(token.transfer(actors[0], SUPPLY));
        handler = new BitesTokenHandler(token, actors, SUPPLY);

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = BitesTokenHandler.move.selector;
        selectors[1] = BitesTokenHandler.approve.selector;
        selectors[2] = BitesTokenHandler.spend.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_supplyAndBalancesRemainConserved() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            uint256 balance = token.balanceOf(actors[i]);
            assertEq(balance, handler.expectedBalance(actors[i]));
            sum += balance;
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
    }

    function invariant_allowancesMatchModel() public view {
        for (uint256 i; i < actors.length; ++i) {
            for (uint256 j; j < actors.length; ++j) {
                assertEq(token.allowance(actors[i], actors[j]), handler.expectedAllowance(actors[i], actors[j]));
            }
        }
    }
}
