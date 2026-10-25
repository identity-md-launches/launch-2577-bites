// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {BitesToken} from "../src/BitesToken.sol";

/// @dev Test-only CREATE2 deployment, matching the launch's immediate-deployer semantics.
contract TokenFactoryProbe {
    function deploy(bytes32 salt) external returns (BitesToken) {
        return new BitesToken{salt: salt}();
    }

    function distribute(BitesToken token, address recipient, uint256 amount) external {
        require(token.transfer(recipient, amount), "transfer failed");
    }
}

contract BitesTokenTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;

    BitesToken private token;
    address private alice;
    address private bob;
    address private spender;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
        token = new BitesToken();
    }

    function test_metadataAndInitialSupply() public view {
        assertEq(token.name(), "bites");
        assertEq(token.symbol(), "BIT");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_constructorEmitsExactlyOneMint() public {
        vm.recordLogs();
        BitesToken deployed = new BitesToken();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(deployed));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(address(this)))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
    }

    function test_constructorMintsToDirectDeployer() public {
        vm.prank(alice);
        BitesToken deployed = new BitesToken();
        assertEq(deployed.balanceOf(alice), SUPPLY);
        assertEq(deployed.balanceOf(address(this)), 0);
        assertEq(deployed.totalSupply(), SUPPLY);
    }

    function test_factoryReceivesEntireSupplyAndLaunchTransfersAreExact() public {
        TokenFactoryProbe factory = new TokenFactoryProbe();
        address distributor = makeAddr("distributor");
        address poolManager = makeAddr("pool manager");
        address remainderRecipient = makeAddr("remainder recipient");
        address claimant = makeAddr("claimant");

        // The external caller and transaction origin are deliberately distinct from the factory.
        vm.prank(alice, bob);
        BitesToken launched = factory.deploy(keccak256("bites launch test"));
        assertEq(launched.balanceOf(address(factory)), SUPPLY);
        assertEq(launched.balanceOf(alice), 0);
        assertEq(launched.balanceOf(bob), 0);

        factory.distribute(launched, distributor, SUPPLY / 10);
        factory.distribute(launched, poolManager, SUPPLY * 7 / 10);
        factory.distribute(launched, remainderRecipient, SUPPLY / 5);
        assertEq(launched.balanceOf(address(factory)), 0);
        assertEq(launched.balanceOf(distributor), SUPPLY / 10);
        assertEq(launched.balanceOf(poolManager), SUPPLY * 7 / 10);
        assertEq(launched.balanceOf(remainderRecipient), SUPPLY / 5);

        vm.prank(distributor);
        assertTrue(launched.transfer(claimant, SUPPLY / 10));
        assertEq(launched.balanceOf(distributor), 0);
        assertEq(launched.balanceOf(claimant), SUPPLY / 10);

        // Check token movements in each direction; this is not a DEX pricing or liquidity test.
        vm.prank(poolManager);
        assertTrue(launched.transfer(alice, 50 ether));
        assertEq(launched.balanceOf(alice), 50 ether);
        vm.prank(alice);
        assertTrue(launched.transfer(poolManager, 50 ether));
        assertEq(launched.balanceOf(alice), 0);
        assertEq(launched.balanceOf(poolManager), SUPPLY * 7 / 10);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function test_transferEmitsEventAndMovesExactAmount() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 123 ether);
        assertTrue(token.transfer(alice, 123 ether));
        assertEq(token.balanceOf(address(this)), SUPPLY - 123 ether);
        assertEq(token.balanceOf(alice), 123 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferEntireBalance() public {
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
    }

    function test_transferZeroFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_selfTransferPreservesBalance() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferToContractRequiresNoReceiverCallback() public {
        TokenFactoryProbe recipient = new TokenFactoryProbe();
        assertTrue(token.transfer(address(recipient), 1));
        assertEq(token.balanceOf(address(recipient)), 1);
    }

    function test_transferRevertsForInsufficientBalance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transfer(bob, 1);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_selfTransferStillRequiresSufficientBalance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transfer(alice, 1);
    }

    function test_transferToZeroRevertsWithoutBurning() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransferToZeroAlsoReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
    }

    function test_approveEmitsEventAndDoesNotMoveTokens() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 100 ether);
        assertTrue(token.approve(spender, 100 ether));
        assertEq(token.allowance(address(this), spender), 100 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(spender), 0);
    }

    function test_approvalOverwritesThenRevokes() public {
        assertTrue(token.approve(spender, 100));
        assertTrue(token.approve(spender, 40));
        assertEq(token.allowance(address(this), spender), 40);
        assertTrue(token.approve(spender, 0));
        assertEq(token.allowance(address(this), spender), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_emptyHolderCanApproveMoreThanTheirBalance() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, type(uint256).max));
        assertEq(token.allowance(alice, spender), type(uint256).max);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_approveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function test_transferFromEmitsEventAndConsumesAllowance() public {
        assertTrue(token.approve(spender, 100 ether));
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 40 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 40 ether));
        assertEq(token.allowance(address(this), spender), 60 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 40 ether);
        assertEq(token.balanceOf(alice), 40 ether);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromCanExhaustAllowance() public {
        assertTrue(token.approve(spender, 10));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 10));
        assertEq(token.allowance(address(this), spender), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
    }

    function test_infiniteAllowanceIsNotDecremented() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), alice, 100));
        assertTrue(token.transferFrom(address(this), bob, 200));
        vm.stopPrank();
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY - 300);
        assertEq(token.balanceOf(alice), 100);
        assertEq(token.balanceOf(bob), 200);
    }

    function test_transferFromSelfConsumesAllowanceWithoutMovingBalance() public {
        assertTrue(token.approve(spender, 10));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), 4));
        assertEq(token.allowance(address(this), spender), 6);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_zeroTransferFromNeedsNoAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferFromWithoutAllowanceReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_anotherSpenderCannotUseAnApproval() public {
        assertTrue(token.approve(spender, 100));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.allowance(address(this), spender), 100);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_deployerCannotSpendHolderTokensWithoutApproval() public {
        assertTrue(token.transfer(alice, 100));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(alice, address(this), 1);
        assertEq(token.balanceOf(alice), 100);
    }

    function test_failedTransferFromRestoresAllowanceAndBalances() public {
        assertTrue(token.transfer(alice, 10));
        vm.prank(alice);
        assertTrue(token.approve(spender, 11));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 10, 11));
        vm.prank(spender);
        token.transferFrom(alice, bob, 11);
        assertEq(token.allowance(alice, spender), 11);
        assertEq(token.balanceOf(alice), 10);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromToZeroRestoresAllowance() public {
        assertTrue(token.approve(spender, 10));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 10);
        assertEq(token.allowance(address(this), spender), 10);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransferFromZeroSenderReverts() public {
        // Spending a zero allowance validates its owner before validating the transfer sender.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.transferFrom(address(0), alice, 0);
    }

    function test_runtimeFitsDeploymentLimitAndHasNoDelegationOrDestruction() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        bool reachable = true;
        for (uint256 i; i < runtime.length; ++i) {
            uint8 opcode = uint8(runtime[i]);
            if (opcode == 0x5B) reachable = true;
            // PUSH immediate values are data, not executable instructions.
            if (opcode >= 0x60 && opcode <= 0x7F) {
                i += opcode - 0x5F;
                continue;
            }
            if (reachable) {
                assertTrue(opcode != 0xF4, "DELEGATECALL");
                assertTrue(opcode != 0xF2, "CALLCODE");
                assertTrue(opcode != 0xFF, "SELFDESTRUCT");
            }
            if (
                opcode == 0x00 || opcode == 0x56 || opcode == 0xF3 || opcode == 0xFD || opcode == 0xFE || opcode == 0xFF
            ) {
                reachable = false;
            }
        }
    }

    function test_noMintBurnAdminOrUpgradeEntryPoints() public {
        bytes[] memory calls = new bytes[](16);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", bob, 1);
        calls[1] = abi.encodeWithSignature("mint(uint256)", 1);
        calls[2] = abi.encodeWithSignature("mint()");
        calls[3] = abi.encodeWithSignature("burn(uint256)", 1);
        calls[4] = abi.encodeWithSignature("burnFrom(address,uint256)", alice, 1);
        calls[5] = abi.encodeWithSignature("pause()");
        calls[6] = abi.encodeWithSignature("blacklist(address)", alice);
        calls[7] = abi.encodeWithSignature("freeze(address)", alice);
        calls[8] = abi.encodeWithSignature("seize(address)", alice);
        calls[9] = abi.encodeWithSignature("transferOwnership(address)", bob);
        calls[10] = abi.encodeWithSignature("setMinter(address)", bob);
        calls[11] = abi.encodeWithSignature("initialize(address)", bob);
        calls[12] = abi.encodeWithSignature("upgradeTo(address)", bob);
        calls[13] = abi.encodeWithSignature("owner()");
        calls[14] = abi.encodeWithSignature("setTransfersEnabled(bool)", false);
        calls[15] = abi.encodeWithSignature("setBlacklist(address,bool)", alice, true);

        assertTrue(token.transfer(alice, 100));
        for (uint256 i; i < calls.length; ++i) {
            (bool deployerSuccess,) = address(token).call(calls[i]);
            assertFalse(deployerSuccess);
            vm.prank(bob);
            (bool strangerSuccess,) = address(token).call(calls[i]);
            assertFalse(strangerSuccess);
            assertEq(token.totalSupply(), SUPPLY);
            assertEq(token.balanceOf(alice), 100);
            assertEq(token.balanceOf(bob), 0);
        }
        vm.prank(alice);
        assertTrue(token.transfer(bob, 100));
        assertEq(token.balanceOf(bob), 100);
    }

    function test_nativeCurrencyTransferReverts() public {
        vm.deal(address(this), 1 ether);
        (bool success,) = address(token).call{value: 1 wei}("");
        assertFalse(success);
        assertEq(address(token).balance, 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferConservesSupply(address recipient, uint256 amount) public {
        vm.assume(recipient != address(0) && recipient != address(this));
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferAboveBalanceReverts(uint256 amount) public {
        amount = bound(amount, SUPPLY + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount)
        );
        token.transfer(alice, amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferFromAccountsForAllowance(uint256 approved, uint256 amount) public {
        amount = bound(amount, 0, approved < SUPPLY ? approved : SUPPLY);
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.allowance(address(this), spender), approved == type(uint256).max ? approved : approved - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferAboveAllowanceReverts(uint256 approved, uint256 amount) public {
        approved = bound(approved, 0, SUPPLY - 1);
        amount = bound(amount, approved + 1, SUPPLY);
        assertTrue(token.approve(spender, approved));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, amount);
        assertEq(token.allowance(address(this), spender), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }
}

