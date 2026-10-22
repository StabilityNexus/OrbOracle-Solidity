// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "lib/forge-std/src/Test.sol";
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {
    Oracle,
    OnlyDev,
    OnlyProposedDev,
    DevFeeExceedsMax,
    ZeroAddress,
    DevFeeTransferFailed
} from "../src/Oracle.sol";
import {
    OracleFactory,
    InvalidWeightToken,
    OnlyDev as FactoryOnlyDev,
    OnlyProposedDev as FactoryOnlyProposedDev,
    DevFeeExceedsMax as FactoryDevFeeExceedsMax,
    ZeroAddress as FactoryZeroAddress
} from "../src/OracleFactory.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Mock Token", "MTK") {
        _mint(msg.sender, 1_000_000 ether);
    }
}

contract RejectEther {
    // Rejects any incoming ETH
}

contract OracleDevFeeTest is Test {
    MockToken public token;
    Oracle public oracle;
    OracleFactory public factory;

    address public owner = address(0x1111);
    address public dev = address(0x2222);
    address public newDev = address(0x3333);
    address public feeReceiver = address(0x4444);
    address public user = address(0x5555);

    uint256 public constant DEFAULT_DEV_FEE = 10_000; // 10% (10,000 / 1e5)
    uint256 public constant MAX_DEV_FEE = 30_000;     // 30%

    event DevProposed(address indexed proposedDev);
    event DevTransferred(address indexed oldDev, address indexed newDev);
    event DevFeeReceiverUpdated(address indexed newReceiver);
    event DevFeePaid(address indexed receiver, uint256 amount);
    event Funded(address indexed from, uint256 amount);

    function setUp() public {
        token = new MockToken();

        oracle = new Oracle(
            owner,
            dev,
            DEFAULT_DEV_FEE,
            "Test Feed",
            "Test Description",
            address(token),
            3600,   // halfLifeSeconds
            50000,  // q
            300,    // depositLockingPeriod
            300,    // withdrawalLockingPeriod
            500,    // rewardBps
            60,     // gamma
            5       // defaultSampleSize
        );

        factory = new OracleFactory(owner, dev, DEFAULT_DEV_FEE);
        vm.deal(user, 100 ether);
    }

    // --- Constructor Validations ---

    function test_Constructor_SetsDevAndDevFee() public view {
        assertEq(oracle.dev(), dev);
        assertEq(oracle.devFeeReceiver(), dev);
        assertEq(oracle.devFee(), DEFAULT_DEV_FEE);
        assertEq(oracle.proposedDev(), address(0));
        assertEq(oracle.MAX_DEV_FEE(), MAX_DEV_FEE);
    }

    function test_Constructor_RevertsOnZeroDevAddress() public {
        vm.expectRevert(ZeroAddress.selector);
        new Oracle(
            owner,
            address(0),
            DEFAULT_DEV_FEE,
            "Test",
            "Desc",
            address(token),
            3600,
            50000,
            300,
            300,
            500,
            60,
            5
        );
    }

    function test_Constructor_RevertsIfFeeExceedsMax() public {
        uint256 excessiveFee = MAX_DEV_FEE + 1; // 30.001%
        vm.expectRevert(abi.encodeWithSelector(DevFeeExceedsMax.selector, excessiveFee, MAX_DEV_FEE));
        new Oracle(
            owner,
            dev,
            excessiveFee,
            "Test",
            "Desc",
            address(token),
            3600,
            50000,
            300,
            300,
            500,
            60,
            5
        );
    }

    function test_Constructor_AllowsMaxFee() public {
        Oracle maxFeeOracle = new Oracle(
            owner,
            dev,
            MAX_DEV_FEE,
            "Test",
            "Desc",
            address(token),
            3600,
            50000,
            300,
            300,
            500,
            60,
            5
        );
        assertEq(maxFeeOracle.devFee(), MAX_DEV_FEE);
    }

    // --- Fee Deductions on deposit() and receive() ---

    function test_Deposit_DeductsFeeAndSendsToReceiver() public {
        uint256 depositAmount = 10 ether;
        uint256 expectedFee = (depositAmount * DEFAULT_DEV_FEE) / 100_000; // 1 ether
        uint256 expectedRemainder = depositAmount - expectedFee;           // 9 ether

        uint256 devBalanceBefore = dev.balance;
        uint256 oracleBalanceBefore = address(oracle).balance;

        vm.prank(user);
        vm.expectEmit(true, false, false, true);
        emit DevFeePaid(dev, expectedFee);
        vm.expectEmit(true, false, false, true);
        emit Funded(user, depositAmount);
        oracle.deposit{value: depositAmount}();

        assertEq(dev.balance, devBalanceBefore + expectedFee);
        assertEq(address(oracle).balance, oracleBalanceBefore + expectedRemainder);
    }

    function test_Receive_DeductsFeeAndSendsToReceiver() public {
        uint256 sendAmount = 5 ether;
        uint256 expectedFee = (sendAmount * DEFAULT_DEV_FEE) / 100_000; // 0.5 ether
        uint256 expectedRemainder = sendAmount - expectedFee;           // 4.5 ether

        uint256 devBalanceBefore = dev.balance;
        uint256 oracleBalanceBefore = address(oracle).balance;

        vm.prank(user);
        vm.expectEmit(true, false, false, true);
        emit DevFeePaid(dev, expectedFee);
        (bool ok, ) = address(oracle).call{value: sendAmount}("");
        assertTrue(ok);

        assertEq(dev.balance, devBalanceBefore + expectedFee);
        assertEq(address(oracle).balance, oracleBalanceBefore + expectedRemainder);
    }

    function test_Deposit_ZeroFeeOracleKeepsAllBalance() public {
        Oracle zeroFeeOracle = new Oracle(
            owner,
            dev,
            0,
            "Zero Fee",
            "Desc",
            address(token),
            3600,
            50000,
            300,
            300,
            500,
            60,
            5
        );

        uint256 depositAmount = 2 ether;
        uint256 devBalanceBefore = dev.balance;

        vm.prank(user);
        zeroFeeOracle.deposit{value: depositAmount}();

        assertEq(dev.balance, devBalanceBefore);
        assertEq(address(zeroFeeOracle).balance, depositAmount);
    }

    function test_Deposit_RevertsIfDevFeeReceiverRejectsEther() public {
        RejectEther rejecter = new RejectEther();

        vm.prank(dev);
        oracle.setDevFeeReceiver(address(rejecter));

        vm.prank(user);
        vm.expectRevert(DevFeeTransferFailed.selector);
        oracle.deposit{value: 1 ether}();
    }

    // --- Updating devFeeReceiver ---

    function test_SetDevFeeReceiver_Success() public {
        vm.prank(dev);
        vm.expectEmit(true, false, false, false);
        emit DevFeeReceiverUpdated(feeReceiver);
        oracle.setDevFeeReceiver(feeReceiver);

        assertEq(oracle.devFeeReceiver(), feeReceiver);

        // Next deposit routes to new feeReceiver
        uint256 depositAmount = 1 ether;
        uint256 expectedFee = (depositAmount * DEFAULT_DEV_FEE) / 100_000;
        uint256 receiverBalanceBefore = feeReceiver.balance;

        vm.prank(user);
        oracle.deposit{value: depositAmount}();

        assertEq(feeReceiver.balance, receiverBalanceBefore + expectedFee);
    }

    function test_SetDevFeeReceiver_RevertsIfNotDev() public {
        vm.prank(user);
        vm.expectRevert(OnlyDev.selector);
        oracle.setDevFeeReceiver(feeReceiver);
    }

    function test_SetDevFeeReceiver_RevertsOnZeroAddress() public {
        vm.prank(dev);
        vm.expectRevert(ZeroAddress.selector);
        oracle.setDevFeeReceiver(address(0));
    }

    // --- 2-Step Dev Transfer ---

    function test_TwoStepDevTransfer_Success() public {
        // Step 1: Current dev proposes newDev
        vm.prank(dev);
        vm.expectEmit(true, false, false, false);
        emit DevProposed(newDev);
        oracle.proposeDev(newDev);

        assertEq(oracle.dev(), dev);
        assertEq(oracle.proposedDev(), newDev);

        // Step 2: newDev accepts role
        vm.prank(newDev);
        vm.expectEmit(true, true, false, false);
        emit DevTransferred(dev, newDev);
        oracle.acceptDev();

        assertEq(oracle.dev(), newDev);
        assertEq(oracle.proposedDev(), address(0));

        // Former dev can no longer call dev functions
        vm.prank(dev);
        vm.expectRevert(OnlyDev.selector);
        oracle.setDevFeeReceiver(address(0x9999));

        // New dev can call dev functions
        vm.prank(newDev);
        oracle.setDevFeeReceiver(address(0x9999));
        assertEq(oracle.devFeeReceiver(), address(0x9999));
    }

    function test_ProposeDev_RevertsIfNotDev() public {
        vm.prank(user);
        vm.expectRevert(OnlyDev.selector);
        oracle.proposeDev(newDev);
    }

    function test_ProposeDev_RevertsOnZeroAddress() public {
        vm.prank(dev);
        vm.expectRevert(ZeroAddress.selector);
        oracle.proposeDev(address(0));
    }

    function test_AcceptDev_RevertsIfNotProposedDev() public {
        vm.prank(dev);
        oracle.proposeDev(newDev);

        vm.prank(user);
        vm.expectRevert(OnlyProposedDev.selector);
        oracle.acceptDev();
    }

    // --- OracleFactory Tests ---

    function test_Factory_ConstructorAndGetters() public view {
        assertEq(factory.dev(), dev);
        assertEq(factory.devFee(), DEFAULT_DEV_FEE);
        assertEq(factory.MAX_DEV_FEE(), MAX_DEV_FEE);
    }

    function test_Factory_Constructor_RevertsOnZeroDev() public {
        vm.expectRevert(FactoryZeroAddress.selector);
        new OracleFactory(owner, address(0), DEFAULT_DEV_FEE);
    }

    function test_Factory_Constructor_RevertsIfFeeExceedsMax() public {
        uint256 excessive = MAX_DEV_FEE + 1;
        vm.expectRevert(abi.encodeWithSelector(FactoryDevFeeExceedsMax.selector, excessive, MAX_DEV_FEE));
        new OracleFactory(owner, dev, excessive);
    }

    function test_Factory_TwoStepDevTransfer() public {
        vm.prank(dev);
        factory.proposeDev(newDev);
        assertEq(factory.proposedDev(), newDev);

        vm.prank(user);
        vm.expectRevert(FactoryOnlyProposedDev.selector);
        factory.acceptDev();

        vm.prank(newDev);
        factory.acceptDev();
        assertEq(factory.dev(), newDev);
        assertEq(factory.proposedDev(), address(0));
    }

    function test_Factory_CreateOracle_PropagatesDevAndFee() public {
        vm.prank(user);
        (address oracleAddr, ) = factory.createOracle(
            "Created Feed",
            "Created Desc",
            address(token),
            3600,
            50000,
            300,
            300,
            500,
            60,
            5
        );

        Oracle createdOracle = Oracle(payable(oracleAddr));
        assertEq(createdOracle.dev(), dev);
        assertEq(createdOracle.devFeeReceiver(), dev);
        assertEq(createdOracle.devFee(), DEFAULT_DEV_FEE);
    }
}
