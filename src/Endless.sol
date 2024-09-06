// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

// REMOVE BEFORE FLIGHT
// import {console} from "forge-std/console.sol";

contract Endless {

    uint256 public devFee = 1; // 0.01% in perpetuity
    address public devAddr = 0x1a7dC1E2A5d695d2Dda143855c9F3030F6038bAA;

    uint256 public gameId;
    mapping(uint256 => GameResults) public gameIdToGameResults;

    struct GameResults {
        uint256 ticketId; // also total ticket count
        uint256 totalNumber;
        uint256 currentAverage;
        uint256 winnersPot;
        uint256 playersPot;
        uint256 winnersSplit;
        uint256 playersPayoutFactor;
    }


    mapping(uint256 => GameSettings) public gameIdToGameSettings;

    struct GameSettings {
        uint256 ticketPrice;
        uint256 winnersShare;
        uint256 playersShare;
        uint256 minAllowedNumber;
        uint256 maxAllowedNumber;
        uint256 gameTime;
        uint256 timeAddon;
    }

    GameBoundaries public gameBoundaries;

    struct GameBoundaries {
        uint256 minTicketPrice;
        uint256 maxTicketPrice;
        uint256 minWinnersShare;
        uint256 maxWinnersShare;
        uint256 minAllowedNumber;
        uint256 maxAllowedNumber;
        uint256 minGameTime;
        uint256 maxGameTime;
        uint256 minTimeAddon;
        uint256 maxTimeAddon;
    }

    function setGameBoundaries(
        uint256 _minTicketPrice,
        uint256 _maxTicketPrice,
        uint256 _minWinnersShare,
        uint256 _maxWinnersShare,
        uint256 _minAllowedNumber,
        uint256 _maxAllowedNumber,
        uint256 _minGameTime,
        uint256 _maxGameTime,
        uint256 _minTimeAddon,
        uint256 _maxTimeAddon
    ) external  {
        require(msg.sender == devAddr, "Caller is not the dev");
        
        gameBoundaries = GameBoundaries({
            minTicketPrice: _minTicketPrice,
            maxTicketPrice: _maxTicketPrice,
            minWinnersShare: _minWinnersShare,
            maxWinnersShare: _maxWinnersShare,
            minAllowedNumber: _minAllowedNumber,
            maxAllowedNumber: _maxAllowedNumber,
            minGameTime: _minGameTime,
            maxGameTime: _maxGameTime,
            minTimeAddon: _minTimeAddon,
            maxTimeAddon: _maxTimeAddon
        });
    }

    struct Ticket {
        uint256 gameId;
        uint256 ticketId;
        address player;
        uint256 number;
        bool isWinner;
        bool isClaimed;
    }

    /*================================================== Global Variables ==================================================*/
    // This 3 variables determine the game flow
    uint256 public startGameFlag; // assigned at game starts
    uint256 public endGameFlag; // assigned at game ends
    bool public canBuyTicket;

    // a control variable - determines some flow too
    bool public nonReentrancy;

    // Owner variables
    uint256 public closeTime; // time from end to close

    function setCloseTime(uint256 _newCloseTime) external {
        require(msg.sender == devAddr, "Caller is not the dev");
        
        closeTime = _newCloseTime;
    }

    /*================================================== TRACKERS ==================================================*/
    // Variables that never stop counting?
    uint256 public potAmount;

    //------------------------------------------------ CALCULATED THROUGHOUT THE GAME --------------------------------------------------- //
    uint256 public ticketId; // also total ticket count
    uint256 public totalNumber;
    uint256 public currentAverage;
    //------------------------------------------------ CALCULATED AT THE END --------------------------------------------------- //
    uint256 public winnersPot;
    uint256 public playersPot;
    uint256 public winnersSplit;
    uint256 public playersPayoutFactor;

    function _resetVariables() private {


        gameIdToGameResults[gameId] = GameResults({
            ticketId: ticketId,
            totalNumber: totalNumber,
            currentAverage: currentAverage,
            winnersPot: winnersPot,
            playersPot: playersPot,
            winnersSplit: winnersSplit,
            playersPayoutFactor: playersPayoutFactor
        });


        ticketId = 0;
        totalNumber = 0;
        currentAverage = 0;
        winnersPot = 0;
        playersPot = 0;
        winnersSplit = 0;
        playersPayoutFactor = 0;
    }

    /*================================================== MAPPINGS ==================================================*/
    mapping(uint256 => mapping(uint256 => Ticket)) public gameIdToTicketIdToTicket;
    mapping(uint256 => mapping(address => uint256[])) public gameIdToPlayerToIdArray;

    function getPlayerToIdArray(uint256 _gameId, address _playerAddress) external view returns(uint256[] memory) {
        return gameIdToPlayerToIdArray[_gameId][_playerAddress];
    }

    event TicketCreated(
        uint256 indexed gameId,
        uint256 indexed ticketId,
        uint256 number,
        uint256 time
    );

    event GameStart(uint256 indexed gameId, uint256 time);

    event GameEnd(uint256 indexed gameId, uint256 time);

    event TicketClaimed(uint256 indexed ticketId, uint256 indexed amount, uint256 time);

    /*================================================== CONSTRUCTOR ==================================================*/
    constructor() {}

    function createGame(
      uint256 _ticketPrice,
      uint256 _winnersShare,
      uint256 _minAllowedNumber,
      uint256 _maxAllowedNumber,
      uint256 _gameTime,
      uint256 _timeAddon,
      uint256 _firstNumber
    ) external  {

        require(endGameFlag + closeTime < block.timestamp, "Game is still going on");
        require(gameBoundaries.minTicketPrice <= _ticketPrice && _ticketPrice  <= gameBoundaries.maxTicketPrice, "Ticket price must be between min and max ticket price");
        require(gameBoundaries.minWinnersShare <= _winnersShare && _winnersShare <= gameBoundaries.maxWinnersShare, "Winners share must be between min and max winners share");
        require(gameBoundaries.minAllowedNumber <= _minAllowedNumber && _minAllowedNumber < _maxAllowedNumber && _maxAllowedNumber < gameBoundaries.maxAllowedNumber, "Allowed numbers must be within game boundaries");
        require(gameBoundaries.minGameTime <= _gameTime && _gameTime <= gameBoundaries.maxGameTime, "Game time must be between min and max game time");
        require(gameBoundaries.minTimeAddon <= _timeAddon && _timeAddon <= gameBoundaries.maxTimeAddon, "Time addon must be between min and max time addon");
        require(_minAllowedNumber <= _firstNumber && _firstNumber <= _maxAllowedNumber, "First number must be within allowed range");

        _resetVariables();

        gameId++;

        gameIdToGameSettings[gameId] = GameSettings({
            ticketPrice: _ticketPrice,
            winnersShare: _winnersShare,
            playersShare: 1 - _winnersShare,
            minAllowedNumber: _minAllowedNumber,
            maxAllowedNumber: _maxAllowedNumber,
            gameTime: _gameTime,
            timeAddon: _timeAddon
        });

        canBuyTicket = true;
        startGameFlag = block.timestamp;

        _createTicket(_firstNumber);

        emit GameStart(gameId, block.timestamp);
    }



    function _createTicket(uint256 _number) private {
        ticketId++; // increase tickets bought by 1
        totalNumber += _number; // increase total number
        currentAverage = totalNumber / ticketId; // compute new average

        Ticket memory newTicket = Ticket({
            gameId: gameId,
            ticketId: ticketId,
            player: msg.sender,
            number: _number,
            isWinner: false,
            isClaimed: false
        });

        // assign to mapping
        gameIdToTicketIdToTicket[gameId][ticketId] = newTicket;
        gameIdToPlayerToIdArray[gameId][msg.sender].push(ticketId); // player can have many tickets


        emit TicketCreated(
            gameId,
            ticketId,
            _number,
            block.timestamp
        );
    }

    function buyTicket(uint256 _selectedNumber) external payable {
        require(canBuyTicket, "No tickets can be bought for now");

        require(msg.value == gameIdToGameSettings[gameId].ticketPrice, "Please send right amount of ETH");

        require(
            _selectedNumber >= gameIdToGameSettings[gameId].minAllowedNumber &&
                _selectedNumber <= gameIdToGameSettings[gameId].maxAllowedNumber,
            "Number is out of range"
        );

        potAmount += msg.value;

        _createTicket(_selectedNumber);
    }

    function computeLeaderboard(uint256 _gameId) public view returns (uint256[] memory) {
        require(_gameId > 0 && _gameId <= gameId, "Game ID is out of bounds");

        uint256[] memory winningIds; // dynamic array to track which ticket won

        uint256 count = 0;

        for (uint256 i = 0; i <= ticketId; i++) {
            if (gameIdToTicketIdToTicket[_gameId][i].number == currentAverage) {
                count++;

                uint256[] memory temp = new uint256[](count);

                for (uint256 j = 0; j < count - 1; j++) {
                    temp[j] = winningIds[j];
                }
                temp[count - 1] = i;
                winningIds = temp;
            }
        }
        return winningIds;
    }

    function endGame() external {
        require(
            startGameFlag + gameIdToGameSettings[gameId].gameTime + (gameIdToGameSettings[gameId].timeAddon * ticketId) < block.timestamp,
            "Not time to end yet"
        );
        require(canBuyTicket == true, "The game has ended"); // require so endGame runs once only

        canBuyTicket = false; // change to stop ticket buying
        endGameFlag = block.timestamp;

        // CREATE --> ASSIGN --> COMPUTE --> SEND
        // create local variables
        uint256[] memory finalLeaderboard = computeLeaderboard(gameId);

        // assign to winning tickets via isWinner
        for (uint256 i = 0; i < finalLeaderboard.length; i++) {
            gameIdToTicketIdToTicket[gameId][finalLeaderboard[i]].isWinner = true;
        }

        // dev fee
        uint256 devFeeAmount = (potAmount * devFee) / 10000;
        (bool success, ) = devAddr.call{value: devFeeAmount}("");
        require(success, "Failed to send");

        potAmount -= devFeeAmount;

        // Players take it all if no one wins
        if (finalLeaderboard.length == 0) {
          winnersPot = 0;
          playersPot = potAmount;
          winnersSplit = 0;
        } else {
          winnersPot = (gameIdToGameSettings[gameId].winnersShare * potAmount) / 100;
          playersPot = (gameIdToGameSettings[gameId].playersShare * potAmount) / 100;
          winnersSplit = winnersPot / finalLeaderboard.length;
        }

        // compute payoutFactor
        // compute reciprocal
        uint256 sumReciprocal = 0;
        for (uint256 i = 1; i <= ticketId; i++) {
            sumReciprocal += (1e18 / i); // add 18 more decimals just in case
        }
        playersPayoutFactor = (playersPot * 1e18) / sumReciprocal; // remove the 18 decimals that were added above

        emit GameEnd(
            gameId,
            block.timestamp
        );
    }

    function claimTicket(uint256 _ticketId) public {
        require(nonReentrancy == false, "someone trying to re=enter");

        nonReentrancy = true;

        // canBuyTicket starts from false => to true once constructor => false when game ends. false here refers to when game ends
        require(canBuyTicket == false, "The game is still going on");

        require(
            gameIdToTicketIdToTicket[gameId][_ticketId].player == msg.sender,
            "You are not the key owner"
        );
        require(
            gameIdToTicketIdToTicket[gameId][_ticketId].isClaimed == false,
            "This key has been claimed"
        );

        gameIdToTicketIdToTicket[gameId][_ticketId].isClaimed = true;


        // compute payout from playerPot
        uint256 ticketPayout = playersPayoutFactor / _ticketId;

        if (gameIdToTicketIdToTicket[gameId][_ticketId].isWinner == true) {
            ticketPayout += winnersSplit;
        }

        (bool success, ) = gameIdToTicketIdToTicket[gameId][_ticketId].player.call{
            value: ticketPayout
        }("");
        require(success, "Failed to send");

         nonReentrancy = false;

        emit TicketClaimed(gameId, _ticketId, block.timestamp);
    }
}
