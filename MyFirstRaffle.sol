pragma solidity ^0.4.19;

contract MyFirstRaffle
{
   //address constant private ADMIN = 0xCA35b7d915458EF540aDe6068dFe2F44E8fa733c; //LOCAL JS
   address constant private ADMIN = 0x501732BEff02B15E33461e5344FBfa0B0a7DB03F; //ROPSTEN
   //address constant private ADMIN = ; //MAINNET

   uint constant private ADMIN_SHARE = 3; //percent of balance
   bool private adminDonationPaid = false;
   uint constant public PAYOUT_AFTER = 1546300740; //20181231235900 UTC
   uint constant public LATEST_PARTICIPATION_AT = 1517443200; //20180201000000 UTC
   uint constant public MIN_PARTICIPATION_FEE = 0.001 ether;

   mapping (address => uint) private addressToContestant;
   Contestant[] private contestants;
   uint public winningValue = 0;
   Contestant[] private winners;
   uint totalPrizeMoney = 0;

   event NewContestant(address owner, uint memberId, string memberName, uint guess);
   event GuessUpdated(address owner, uint memberId, string memberName, uint guess);
   event WinnerKnown(address owner, uint memberId, string memberName, uint guess, uint winningValue);

   function() external payable { } //Anybody can donate funds

   modifier adminOnly
   {
     require(msg.sender == ADMIN);
     _;
   }

   modifier canBePaid
   {
     require (now >= PAYOUT_AFTER);
     _;
   }

   struct Contestant
   {
      address owner;
      uint memberId;
      string memberName;
      uint valueOfGuess;
      uint timeOfGuess;
      address payOutAddress;
      bool hasBeenPaid;
   }

   function getNumberOfContestants() public view returns (uint)
   {
        return contestants.length;
   }

   function getContestant(uint index) canBePaid public view returns (address owner, uint memberId, string memberName, uint guess)
   {
       require(contestants.length > 0);
       require(index < contestants.length);
       Contestant memory c = contestants[index];
       return (c.owner, c.memberId, c.memberName, c.valueOfGuess);
   }

   function getBalanceInWei() public view returns (uint)
   {
        return this.balance;
   }

   function getNumberOfWinners() canBePaid public view returns (uint)
   {
       return winners.length;
   }

   function getWinner(uint index) canBePaid public view returns (address owner, uint memberId, string memberName, uint guess, bool hasBeenPaid)
   {
       require(winners.length > 0);
       require(index < winners.length);
       Contestant memory winner = winners[index];
       return (winner.owner, winner.memberId, winner.memberName, winner.valueOfGuess, winner.hasBeenPaid);
   }

   function participate(uint _memberId, string _memberName, uint _valueOfGuess, address _payOutAddress) public payable
   {
     require(msg.sender != 0);
     require(now < LATEST_PARTICIPATION_AT);
     require(msg.value >= MIN_PARTICIPATION_FEE);

     uint contestantId = addressToContestant[msg.sender];

     if (contestantId == 0)
     {
        Contestant memory newContestant = Contestant({
         owner: msg.sender,
         memberId: _memberId,
         memberName: _memberName,
         valueOfGuess: uint(uint32(_valueOfGuess)), //Just to make sure we don't overflow... A value over 4 billion is not very likely :v
         timeOfGuess: now, //This is actually block.timestamp
         payOutAddress: _payOutAddress,
         hasBeenPaid: false
       });

       //Push to storage
       addContestant(newContestant);

       contestant = contestants[addressToContestant[msg.sender]];

       NewContestant(msg.sender, _memberId, _memberName, _valueOfGuess);
     }
     else
     {
       //Update directly on storage
       Contestant storage contestant = contestants[contestantId];

       require (contestant.owner == msg.sender);

       contestant.memberId = _memberId;
       contestant.memberName = _memberName;
       contestant.valueOfGuess = _valueOfGuess;
       contestant.payOutAddress = _payOutAddress;

       GuessUpdated(msg.sender, _memberId, _memberName, _valueOfGuess);
     }
   }

   function setWinningValue(uint val) canBePaid adminOnly public
   {
      require(winners.length == 0);

      winningValue = val;
      uint distance = ~uint256(0);

      //Find the smallest distance
      for (uint i = 0; i < contestants.length; i++)
      {
          Contestant memory c = contestants[i];
          uint cd = getDistance(winningValue, c.valueOfGuess);

          if (cd < distance) distance = cd;
      }

      //Find contestants closest to winning value
      for (i = 0; i < contestants.length; i++)
      {
          c = contestants[i];
          cd = getDistance(winningValue, c.valueOfGuess);

          if (cd == distance) winners.push(c);
      }
   }

   function getDistance(uint x, uint y) private pure returns (uint)
   {
        if (x > y) return x - y;
        else return y - x;
   }

   function addContestant(Contestant c) private returns (uint)
   {
       uint newId = contestants.push(c) - 1;
       addressToContestant[msg.sender] = newId;

       return newId;
   }

   function executePayment() canBePaid adminOnly public //public, so we can re-attempt payment in case a previous payment failed
   {
       require(winningValue > 0);
       require(winners.length > 0);

      uint adminDonation = this.balance * (ADMIN_SHARE / 100);
      if (winners.length == 0) adminDonation = this.balance;

      //Transfer funds - transfer throws on error
      ADMIN.transfer(adminDonation);
      adminDonationPaid = true;

      totalPrizeMoney = this.balance;
      uint sharePerWinner = totalPrizeMoney / winners.length;

      for (uint i = 0; i < winners.length; i++)
      {
          Contestant storage winner = winners[i];

          //Transfer share with send (returns bool, does not throw)
          if (!winner.hasBeenPaid)
          {
              winner.hasBeenPaid = winner.payOutAddress.send(sharePerWinner);
              if (winner.hasBeenPaid) WinnerKnown(winner.owner, winner.memberId, winner.memberName, winner.valueOfGuess, winningValue);
          }
      }
   }

}
