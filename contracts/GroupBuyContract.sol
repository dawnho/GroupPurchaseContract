pragma solidity ^0.4.18;
import "zeppelin-solidity/contracts/math/SafeMath.sol"; // solhint-disable-line
import "./CelebrityToken.sol";


contract GroupBuyContract {
  /*** CONSTANTS ***/
  bool public isGroupBuy = true;
  uint256 public constant MAX_CONTRIBUTION_SLOTS = 20;
  uint256 private firstStepLimit =  0.053613 ether;
  uint256 private secondStepLimit = 0.564957 ether;

  /*** DATATYPES ***/
  // @dev A Group is created for all the contributors who want to contribute
  //  to the purchase of a particular token.
  struct Group {
    // Array of addresses of contributors in group
    address[] contributorArr;
    // Maps address to an address's position (+ 1) in the contributorArr;
    // 1 is added to the position because zero is the default value in the mapping
    mapping(address => uint256) addressToContributorArrIndex;
    mapping(address => uint256) addressToContribution; // user address to amount contributed
    bool exists; // For tracking whether a group has been initialized or not
    uint256 contributedBalance; // Total amount contributed
    uint256 purchasePrice; // Price of purchased token
  }

  // @dev A Contributor record is created for each user participating in
  //  this group buy contract. It stores the group ids the user contributed to
  //  and a record of their sale proceeds.
  struct Contributor {
    // Maps tokenId to an tokenId's position (+ 1) in the groupArr;
    // 1 is added to the position because zero is the default value in the mapping
    mapping(uint256 => uint) tokenIdToGroupArrIndex;
    // Array of tokenIds contributed to by a contributor
    uint256[] groupArr;
    bool exists;
    uint256 withdrawableBalance; // ledger for proceeds from group sale
  }

  /*** EVENTS ***/
  // @notice Event signifiying that contract received funds via fallback fn
  event FundsReceived(address _from, uint256 amount);

  // @notice Event for notifying user that proceeds from a token have been distributed
  event FundsRedistributed(uint256 _tokenId, address _to, uint256 amount);

  // @notice Event for whenever funds were withdrawn from contract
  event FundsWithdrawn(address _to, uint256 amount);

  // @notice Event for when a contributor joins a token group
  event JoinGroup(
    uint256 _tokenId,
    address contributor,
    uint256 groupBalance,
    uint256 contributionAdded
  );

  // @notice Event for when a contributor leaves a token group
  event LeaveGroup(
    uint256 _tokenId,
    address contributor,
    uint256 groupBalance,
    uint256 contributionSubtracted
  );

  // @notice Event for when a token group purchases a token
  event TokenPurchased(uint256 _tokenId, uint256 balance);

  /*** STORAGE ***/
  /// @dev A mapping from token IDs to the group associated with that token.
  mapping(uint256 => Group) private tokenIndexToGroup;

  // @dev A mapping from owner address to available balance not held by a Group.
  mapping(address => Contributor) private userAddressToContributor;

  uint256 public groupCount;
  uint256 public commissionBalance;
  uint256 public usersBalance;

  CelebrityToken public linkedContract;

  // The addresses of the accounts (or contracts) that can execute actions within each roles.
  address public ceoAddress;
  address public cooAddress;
  address public cfoAddress;

  /*** ACCESS MODIFIERS ***/
  /// @dev Access modifier for CEO-only functionality
  modifier onlyCEO() {
    require(msg.sender == ceoAddress);
    _;
  }

  /// @dev Access modifier for COO-only functionality
  modifier onlyCOO() {
    require(msg.sender == cooAddress);
    _;
  }

  /// @dev Access modifier for CFO-only functionality
  modifier onlyCFO() {
    require(msg.sender == cfoAddress);
    _;
  }

  /// @dev Access modifier for contract managers only functionality
  modifier onlyCLevel() {
    require(
      msg.sender == ceoAddress ||
      msg.sender == cooAddress ||
      msg.sender == cfoAddress
    );
    _;
  }

  /*** CONSTRUCTOR ***/
  function GroupBuyContract(address contractAddress) public {
    ceoAddress = msg.sender;
    cooAddress = msg.sender;
    cfoAddress = msg.sender;
    linkedContract = CelebrityToken(contractAddress);
  }

  /*** PUBLIC FUNCTIONS ***/
  /// @notice Fallback fn for receiving ether
  function () public payable {
    FundsReceived(msg.sender, msg.value);
  }

  /** Contract Verification Fns **/
  /// @notice Get address of connected contract
  function getLinkedContractAddress() public view returns (address) {
    return linkedContract;
  }

  /** Information Query Fns **/
  /// @notice Get contributed balance in a particular token
  /// @param _tokenId The ID of the token to be queried
  function getContributionBalanceForTokenGroup(uint256 _tokenId) public view returns (uint balance) {
    var group = tokenIndexToGroup[_tokenId];
    require(group.exists);
    balance = group.addressToContribution[msg.sender];
  }

  /// @notice Get no. of contributors in a Group
  /// @param _tokenId The ID of the token to be queried
  function getContributorsInTokenGroupCount(uint256 _tokenId) public view returns (uint count) {
    var group = tokenIndexToGroup[_tokenId];
    require(group.exists);
    count = group.contributorArr.length;
  }

  /// @notice Get list of tokenIds of the groups user contributed to
  function getGroupsContributedTo() public view returns (uint256[] groupIds) {
    // Safety check to prevent against an unexpected 0x0 default.
    require(_addressNotNull(msg.sender));

    var contributor = userAddressToContributor[msg.sender];
    require(contributor.exists);

    groupIds = contributor.groupArr;
  }

  /// @notice Retrieve price at which token group purchased token at
  function getGroupPurchasedPrice(uint256 _tokenId) public view returns (uint256 price) {
    var group = tokenIndexToGroup[_tokenId];
    require(group.exists);
    require(group.purchasePrice > 0);
    price = group.purchasePrice;
  }

  /// @notice Get withdrawable balance from sale proceeds
  function getWithdrawableBalance() public view returns (uint256 balance) {
    // Safety check to prevent against an unexpected 0x0 default.
    require(_addressNotNull(msg.sender));

    var contributor = userAddressToContributor[msg.sender];
    require(contributor.exists);

    balance = contributor.withdrawableBalance;
  }

  /// @notice Get contributed balance
  /// @param _tokenId The ID of the token to be queried
  function getTokenGroupTotalBalance(uint256 _tokenId) public view returns (uint balance) {
    var group = tokenIndexToGroup[_tokenId];
    require(group.exists);
    balance = group.contributedBalance;
  }

  /** Action Fns **/
  function activatePurchase(uint256 _tokenId) public {
    var group = tokenIndexToGroup[_tokenId];
    require(group.addressToContribution[msg.sender] > 0 ||
            msg.sender == ceoAddress ||
            msg.sender == cooAddress ||
            msg.sender == cfoAddress);
    var price = linkedContract.priceOf(_tokenId);
    require(group.contributedBalance >= price);

    group.contributedBalance -= price;

    _purchase(_tokenId, price);
  }

  /// @notice Allow user to join purchase group
  /// @param _tokenId The ID of the Token purchase group to be joined
  function contributeToTokenGroup(uint256 _tokenId) public payable {
    address userAdd = msg.sender;
    var group = tokenIndexToGroup[_tokenId];
    var contributor = userAddressToContributor[userAdd];

    // Safety check to prevent against an unexpected 0x0 default.
    require(_addressNotNull(userAdd));

    /// Safety check to make sure contributor has not already joined this group buy
    if (!group.exists) {
      group.exists = true;
    } else {
      require(group.addressToContributorArrIndex[userAdd] == 0);
    }

    if (!contributor.exists) {
      userAddressToContributor[userAdd].exists = true;
    } else {
      require(userAddressToContributor[userAdd].tokenIdToGroupArrIndex[_tokenId] == 0);
    }

    // Safety check to make sure group hasn't purchased token already
    require(group.purchasePrice == 0);

    uint256 tokenPrice = linkedContract.priceOf(_tokenId);

    /// Safety check to ensure amount contributed is higher than min portion of the
    ///  purchase price
    require(msg.value >= SafeMath.div(tokenPrice, MAX_CONTRIBUTION_SLOTS));

    // Index saved is 1 + the array's index, b/c 0 is the default value in a mapping,
    //  so as stored on the mapping, array index will begin at 1
    uint256 cIndex = tokenIndexToGroup[_tokenId].contributorArr.push(userAdd);
    tokenIndexToGroup[_tokenId].addressToContributorArrIndex[userAdd] = cIndex;

    uint256 amountNeeded = SafeMath.sub(tokenPrice, group.contributedBalance);
    if (msg.value > amountNeeded) {
      tokenIndexToGroup[_tokenId].addressToContribution[userAdd] = amountNeeded;
      tokenIndexToGroup[_tokenId].contributedBalance += amountNeeded;
      // refund excess paid
      userAddressToContributor[userAdd].withdrawableBalance += SafeMath.sub(msg.value, amountNeeded);
    } else {
      tokenIndexToGroup[_tokenId].addressToContribution[userAdd] = msg.value;
      tokenIndexToGroup[_tokenId].contributedBalance += msg.value;
    }

    // Index saved is 1 + the array's index, b/c 0 is the default value in a mapping,
    //  so as stored on the mapping, array index will begin at 1
    uint256 gIndex = userAddressToContributor[userAdd].groupArr.push(_tokenId);
    userAddressToContributor[userAdd].tokenIdToGroupArrIndex[_tokenId] = gIndex;

    usersBalance += msg.value;

    JoinGroup(
      _tokenId,
      userAdd,
      tokenIndexToGroup[_tokenId].contributedBalance,
      tokenIndexToGroup[_tokenId].addressToContribution[userAdd]
    );

    if (tokenIndexToGroup[_tokenId].contributedBalance >= tokenPrice) {
      _purchase(_tokenId, tokenPrice);
    }
  }

  /// @notice Allow redistribution of funds after sale
  /// @param _tokenId The ID of the Token purchase group
  function redistributeSaleProceeds(uint256 _tokenId) public onlyCOO {
    var group = tokenIndexToGroup[_tokenId];

    // Safety check to make sure group exists and had purchased the token
    require(group.exists);
    require(group.purchasePrice > 0);

    // Safety check to make sure token had been sold
    uint256 currPrice = linkedContract.priceOf(_tokenId);
    uint256 soldPrice = _newPrice(group.purchasePrice);
    require(currPrice > soldPrice);

    uint256 paymentIntoContract = uint256(SafeMath.div(SafeMath.mul(soldPrice, 94), 100));
    uint256 fundsForDistribution = uint256(SafeMath.div(SafeMath.mul(paymentIntoContract, 97), 100));

    commissionBalance += uint256(SafeMath.sub(paymentIntoContract, fundsForDistribution));

    for (uint i = 0; i < group.contributorArr.length; i++) {
      address userAdd = group.contributorArr[i];

      // calculate contributor's sale proceeds and add to their withdrawable balance
      uint256 userProceeds = uint256(SafeMath.div(SafeMath.mul(fundsForDistribution,
        group.addressToContribution[userAdd]), group.contributedBalance));
      userAddressToContributor[userAdd].withdrawableBalance += userProceeds;

      _clearGroupRecordInContributor(_tokenId, userAdd);

      // clear contributor record on group
      tokenIndexToGroup[_tokenId].addressToContribution[userAdd] = 0;
      tokenIndexToGroup[_tokenId].addressToContributorArrIndex[userAdd] = 0;
      FundsRedistributed(_tokenId, userAdd, userProceeds);
    }
    tokenIndexToGroup[_tokenId].contributorArr.length = 0;
    tokenIndexToGroup[_tokenId].contributedBalance = 0;
    tokenIndexToGroup[_tokenId].purchasePrice = 0;
  }

  /// @notice Allow user to leave purchase group; note that their contribution
  ///  will be added to their withdrawable balance, and not directly refunded
  /// @param _tokenId The ID of the Token purchase group to be left
  function leaveTokenGroup(uint256 _tokenId) public {
    address userAdd = msg.sender;

    var group = tokenIndexToGroup[_tokenId];
    var contributor = userAddressToContributor[userAdd];

    // Safety check to prevent against an unexpected 0x0 default.
    require(_addressNotNull(userAdd));

    // Safety check to make sure group hasn't purchased token already
    require(group.purchasePrice == 0);

    // Safety checks to ensure contributor has contributed to group
    require(group.addressToContributorArrIndex[userAdd] > 0);
    require(contributor.tokenIdToGroupArrIndex[_tokenId] > 0);

    // Index was saved is 1 + the array's index, b/c 0 is the default value
    //  in a mapping.
    uint cIndex = group.addressToContributorArrIndex[userAdd] - 1;
    uint lastCIndex = group.contributorArr.length - 1;
    uint refundBalance = group.addressToContribution[userAdd];

    // clear contribution record in group
    tokenIndexToGroup[_tokenId].addressToContributorArrIndex[userAdd] = 0;
    tokenIndexToGroup[_tokenId].addressToContribution[userAdd] = 0;

    // move address in last position to deleted contributor's spot
    if (lastCIndex > 0) {
      tokenIndexToGroup[_tokenId].addressToContributorArrIndex[group.contributorArr[lastCIndex]] = cIndex;
      tokenIndexToGroup[_tokenId].contributorArr[cIndex] = group.contributorArr[lastCIndex];
    }

    tokenIndexToGroup[_tokenId].contributorArr.length -= 1;
    tokenIndexToGroup[_tokenId].contributedBalance -= refundBalance;

    _clearGroupRecordInContributor(_tokenId, userAdd);

    userAddressToContributor[userAdd].withdrawableBalance += refundBalance;

    LeaveGroup(
      _tokenId,
      userAdd,
      tokenIndexToGroup[_tokenId].contributedBalance,
      refundBalance
    );
  }

  /// @notice Get withdrawable balance from sale proceeds
  function withdrawBalance() public {
    require(_addressNotNull(msg.sender));
    var contributor = userAddressToContributor[msg.sender];
    require(contributor.exists);

    uint256 balance = contributor.withdrawableBalance;
    usersBalance -= balance;
    contributor.withdrawableBalance = 0;

    if (balance > 0) {
      msg.sender.transfer(balance);
      FundsWithdrawn(msg.sender, balance);
    }
  }

  /// @dev Assigns a new address to act as the CEO. Only available to the current CEO.
  /// @param _newCEO The address of the new CEO
  function setCEO(address _newCEO) public onlyCEO {
    require(_newCEO != address(0));

    ceoAddress = _newCEO;
  }

  /// @dev Assigns a new address to act as the CFO. Only available to the current CEO.
  /// @param _newCFO The address of the new CFO
  function setCFO(address _newCFO) public onlyCEO {
    require(_newCFO != address(0));

    cfoAddress = _newCFO;
  }

  /// @dev Assigns a new address to act as the COO. Only available to the current CEO.
  /// @param _newCOO The address of the new COO
  function setCOO(address _newCOO) public onlyCEO {
    require(_newCOO != address(0));

    cooAddress = _newCOO;
  }

  /*** PRIVATE FUNCTIONS ***/
  /// Safety check on _to address to prevent against an unexpected 0x0 default.
  function _addressNotNull(address _to) private pure returns (bool) {
    return _to != address(0);
  }

  function _clearGroupRecordInContributor(uint256 _tokenId, address _userAdd) private {
    // Index saved is 1 + the array's index, b/c 0 is the default value
    //  in a mapping.
    uint gIndex = userAddressToContributor[_userAdd].tokenIdToGroupArrIndex[_tokenId] - 1;
    uint lastGIndex = userAddressToContributor[_userAdd].groupArr.length - 1;

    // clear group record in Contributor
    userAddressToContributor[_userAdd].tokenIdToGroupArrIndex[_tokenId] = 0;

    // move tokenId in last position to deleted group record's spot
    if (lastGIndex > 0) {
      userAddressToContributor[_userAdd].tokenIdToGroupArrIndex[userAddressToContributor[_userAdd].groupArr[lastGIndex]] = gIndex;
      userAddressToContributor[_userAdd].groupArr[gIndex] = userAddressToContributor[_userAdd].groupArr[lastGIndex];
    }

    userAddressToContributor[_userAdd].groupArr.length -= 1;
  }

  function _newPrice(uint256 oldPrice) private view returns (uint256 newPrice) {
    if (oldPrice < firstStepLimit) {
      // first stage
      newPrice = SafeMath.div(SafeMath.mul(oldPrice, 200), 94);
    } else if (oldPrice < secondStepLimit) {
      // second stage
      newPrice = SafeMath.div(SafeMath.mul(oldPrice, 120), 94);
    } else {
      // third stage
      newPrice = SafeMath.div(SafeMath.mul(oldPrice, 115), 94);
    }
  }

  function _purchase(uint256 _tokenId, uint256 amount) private {
    tokenIndexToGroup[_tokenId].purchasePrice = amount;
    usersBalance -= amount;
    linkedContract.purchase.value(amount)(_tokenId);
    TokenPurchased(_tokenId, amount);
  }
}
