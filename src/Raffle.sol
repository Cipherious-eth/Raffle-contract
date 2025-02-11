// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

//SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
//imports
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/**
 * @title A simple raffle contract
 * @author cipherious.xyz
 * @notice This contract is for creating a simple raffle
 * @dev Implements chainlink-VRFv2.5
 */
contract Raffle is VRFConsumerBaseV2Plus {
    /**erros */
    error Raffle__SendMoreToEnterRaffle();
    error Raffle__transferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__upKeepNotNeeded(
        uint256 balance,
        uint256 players,
        uint256 state
    );
    //Type declarations
    enum RaffleState {
        OPEN,
        CALCULATING
    }

    //state variables
    address payable[] private s_players;
    uint256 private s_lastTimeStamp;
    address private s_recentWinner;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;
    uint256 private immutable i_entranceFee;
    uint256 private immutable i_interval;
    bytes32 private immutable i_keyHash;
    uint256 private immutable i_subscriptionId;
    uint32 private immutable i_callBackGasLimit;
    RaffleState private s_raffleState;
    //Events
    event RaffleEntered(address indexed player);
    event winnerPicked(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint256 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        s_lastTimeStamp = block.timestamp;
        i_keyHash = gasLane;
        i_subscriptionId = subscriptionId;
        i_callBackGasLimit = callbackGasLimit;
        s_raffleState = RaffleState.OPEN;
    }

    function enterRaffle() external payable {
        // require(msg.value >= i_entranceFee, "Not enough ETH sent");
        if (msg.value < i_entranceFee) {
            revert Raffle__SendMoreToEnterRaffle();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }
        //require(msg.value >= i_entranceFee, SendMoreToEtherRaffle());
        s_players.push(payable(msg.sender));
        emit RaffleEntered(msg.sender);
    }

    /**
     * @dev this is the function the chainlink nodes will called to
     * see if the lottery is ready to pick a winner
     * The following has to be true for upKeepNeeded to be true
     * 1.The time interval has passed between Raffle runs
     * 2.The lottery is in the open state
     * 3.The contract has ETH
     * 4.implicitly your subscription has link
     * @param -ignored
     * @return upKeepNeeded true if it is time to restart the lottery
     * @return -ignored
     */
    //checkUpKeep= decision maker
    function checkUpKeep(
        bytes memory /*checkData*/
    ) public view returns (bool upKeepNeeded, bytes memory /*performData*/) {
        bool timeHasPassed = block.timestamp - s_lastTimeStamp >= i_interval;
        bool isOpen = s_raffleState == RaffleState.OPEN;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upKeepNeeded = timeHasPassed && isOpen && hasBalance && hasPlayers;
        return (upKeepNeeded, "");
    }

    //Get a random number
    //Use the random number to pick a player
    // Be automatically called
    //performUpKeep= Action taker
    function performUpKeep(bytes calldata /*performData*/) external {
        (bool upKeepNeeded, ) = checkUpKeep("");
        if (!upKeepNeeded) {
            revert Raffle__upKeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            );
        }

        s_raffleState = RaffleState.CALCULATING;
        /**
         * Interacting with the chainlink vrf involes two steps
         * a request to the RNG
         * a callback from RNG
         */
        /**
         *
         * @dev Here we are calling an external contract with a function requestRandomWords
         * @param VRFV2PlusClient.RandomWordsRequest  is a struct object
         */
        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient
            .RandomWordsRequest({
                keyHash: i_keyHash,
                subId: i_subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: i_callBackGasLimit,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            });
        uint256 requestId = s_vrfCoordinator.requestRandomWords(request);
        emit RequestedRaffleWinner(requestId);
    }

    function fulfillRandomWords(
        uint256 /*requestId*/,
        uint256[] calldata randomWords
    ) internal override {
        //checks

        //Effect
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable recentWinner = s_players[indexOfWinner];
        s_recentWinner = recentWinner;

        s_raffleState = RaffleState.OPEN;
        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp;
        emit winnerPicked(s_recentWinner);
        //interactions
        (bool success, ) = recentWinner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__transferFailed();
        }
    }

    /**Getter functions*/
    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns (address) {
        return s_players[indexOfPlayer];
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }
}
