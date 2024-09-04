//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {Raffle} from "../../src/Raffle.sol";
import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts@1.2.0/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {CodeConstants} from "../../script/HelperConfig.s.sol";


contract RaffleTest is CodeConstants, Test {
    Raffle public raffle;
    HelperConfig public helperConfig;

    uint256 entranceFee;
    uint256 interval;
    bytes32 gasLane;
    uint256 subscriptionId;
    uint32 callbackGasLimit;
    address vrfCoordinator;

    address public PLAYER = makeAddr("Player");
    uint256 public constant STARTING_BALANCE = 10 ether;

    event RaffleEntered(address indexed player);
    event WinnerPicked(address indexed winner);

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.deployContract();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        entranceFee = config.entranceFee;
        interval = config.interval;
        vrfCoordinator = config.vrfCoordinator;
        gasLane = config.gasLane;
        callbackGasLimit = config.callbackGasLimit;
        subscriptionId = config.subscriptionId;
        
    }

    modifier fundedPlayer() {
        vm.deal(PLAYER, STARTING_BALANCE);
        vm.prank(PLAYER);
        _;
    }

    modifier enterRaffle() {
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    modifier skipFork(){
        if (block.chainid != LOCAL_CHAIN_ID) {
            return;
        }
        _;
    }

    function testRaffleInitializesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    function testConstructorSetsRaffleStateTimeStampAndCallBackGasLimit()
        public
        fundedPlayer
    {
        raffle.enterRaffle{value: entranceFee}();

        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
        assert(raffle.getLastTimeStamp() == block.timestamp);

        assert(raffle.getCallbackGasLimit() == callbackGasLimit);
    }

    function testConstructorSetsEntranceFeeIntervalKeyHashAndSubId()
        public
        fundedPlayer
    {
        raffle.enterRaffle{value: entranceFee}();

        assert(raffle.getEntranceFee() == entranceFee);
        assert(raffle.getInterval() == interval);
        assert(raffle.getKeyHash() == gasLane);
        // assert(raffle.getSubscriptionId() == subscriptionId);
    }

    function testRaffleRevertsWhenYouDontPayEnough() public {
        vm.prank(PLAYER);

        vm.expectRevert(Raffle.Raffle__SendMoreToEnterRaffle.selector);
        raffle.enterRaffle();
    }

    function testRaffleTracksPlayerEntries() public fundedPlayer {
        // ARRANGE IS EXECUTED IN MODIFIER
        // ACT
        raffle.enterRaffle{value: entranceFee}();

        // ASSERT
        address playerRecorded = raffle.getPlayer(0);
        assert(playerRecorded == PLAYER);
    }

    function testEnteringRaffleEmitsEvent() public fundedPlayer {
        vm.expectEmit(true, false, false, false, address(raffle));
        emit RaffleEntered(PLAYER);

        // ASSERT
        raffle.enterRaffle{value: entranceFee}();
    }

    function testPlayersCantEnterWhileCalculating() public fundedPlayer {
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        raffle.performUpkeep("");

        // Act/Assert
        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        raffle.enterRaffle{value: entranceFee}();
    }

    /**
     * CHECK UPKEEP
     */

    function testUpkeepReturnsFalseIfItHasNoBalance() public {
        // ARRANGE
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        // ACT
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        // ASSERT
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfRaffleIsntOpen() public fundedPlayer {
        // ARRANGE
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");

        // ACT
        (bool upKeepNeeded, ) = raffle.checkUpkeep("");

        // ASSERT
        assert(!upKeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfTimeHasNotPassed()
        public
        fundedPlayer
    {
        raffle.enterRaffle{value: entranceFee}();

        // ACT
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        // ASSERT

        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfRaffleHasNoPlayers()
        public
        fundedPlayer
    {
        // raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        // raffle.performUpkeep("");

        // ACT

        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        // ASSERT
        assert(address(PLAYER).balance > 0);
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
        // assert(raffle.getLastTimeStamp() - block.timestamp >= interval);
        assert(!upkeepNeeded);
    }

    /**
     * PERFORM UPKEEP
     */

    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue()
        public
        fundedPlayer
        enterRaffle
    {
        raffle.performUpkeep("");
    }

    function testPerformUpkeepRevertsWhenCheckUpkeepIsFalse()
        public
        fundedPlayer
    {
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        Raffle.RaffleState rState = raffle.getRaffleState();

        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        currentBalance = currentBalance + entranceFee;
        numPlayers = 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__UpKeepNotNeeded.selector,
                currentBalance,
                numPlayers,
                rState
            )
        );

        raffle.performUpkeep("");
    }

    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestTd()
        public
        fundedPlayer
        enterRaffle
    {
        // ACT
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        Raffle.RaffleState raffleState = raffle.getRaffleState();
        assert(uint256(requestId) > 0);
        assert(uint256(raffleState) == 1);
    }

    /**
     *  FULFILLRANDOMWORDS
     */

    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(
        uint256 randomRequestId
    ) public fundedPlayer enterRaffle skipFork {
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(
            randomRequestId,
            address(raffle)
        );
    }

    function testFulfillRandomWordsPicksWinnerResetsAndSendsMoney() public fundedPlayer enterRaffle skipFork{
            // ARRANGE
        uint256 additionalEntrants = 4;
        uint256 startingIndex = 1;
        address expectedWinner = address(1);

        for (uint256 i = startingIndex; i < startingIndex + additionalEntrants; i++) {
            address newPlayer = address(uint160(i));
            hoax(newPlayer, 1 ether);
            raffle.enterRaffle{value: entranceFee}();
        }
        uint256 startingTimeStamp = raffle.getLastTimeStamp();
        uint256 winnerStartingBalance = expectedWinner.balance;
            // ACT
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle));
        
        // ASSERT
        address recentWinner = raffle.getRecentWinner();
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        uint256 winnerBalance = recentWinner.balance;
        uint256 endingTimeStamp = raffle.getLastTimeStamp();
        uint256 prize = entranceFee + (additionalEntrants + 1);

        assert(recentWinner == expectedWinner);
        assert(uint256(raffleState) == 0);
        console.log("The winner's starting balance is: ", winnerStartingBalance);
        console.log("The Winner's new balance is: ", winnerBalance);
        console.log("The prize is: ", prize);
        console.log("Winner starting balance + Prize is: ", winnerStartingBalance + prize);
        assert(winnerBalance > winnerStartingBalance);
        assert(endingTimeStamp > startingTimeStamp);

    }
}
