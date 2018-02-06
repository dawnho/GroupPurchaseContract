pragma solidity ^0.4.18;
import "zeppelin-solidity/contracts/math/SafeMath.sol"; // solhint-disable-line
import "./CelebrityToken.sol";


contract GroupBuyContract {
  /*** CONSTANTS ***/
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
    // Ledger for withdrawable balance for this user.
    //  Funds can come from excess paid into a groupBuy,
    //  or from withdrawing from a group, or from
    //  sale proceeds from a token.
    uint256 withdrawableBalance;
  }

  /*** EVENTS ***/
  // @notice Event noting commission paid to contract
  event Commission(uint256 _tokenId, uint256 amount);

  // @notice Event signifiying that contract received funds via fallback fn
  event FundsReceived(address _from, uint256 amount);

  // @notice Event noting a fund distribution for user _to from sale of token _tokenId
  event FundsRedistributed(uint256 _tokenId, address _to, uint256 amount);

  // @notice Event marking a withdrawal of amount by user _to
  event FundsWithdrawn(address _to, uint256 amount);

  // @notice Event for when a contributor joins a token group _tokenId
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
  // The addresses of the accounts (or contracts) that can execute actions within each roles.
  address public ceoAddress;
  address public cfoAddress;
  address public cooAddress;

  uint256 public activeGroups;
  uint256 public commissionBalance;

  CelebrityToken public linkedContract;

  /// @dev A mapping from token IDs to the group associated with that token.
  mapping(uint256 => Group) private tokenIndexToGroup;

  // @dev A mapping from owner address to available balance not held by a Group.
  mapping(address => Contributor) private userAddressToContributor;

  /*** ACCESS MODIFIERS ***/
  /// @dev Access modifier for CEO-only functionality
  modifier onlyCEO() {
    require(msg.sender == ceoAddress);
    _;
  }

  /// @dev Access modifier for CFO-only functionality
  modifier onlyCFO() {
    require(msg.sender == cfoAddress);
    _;
  }

  /// @dev Access modifier for COO-only functionality
  modifier onlyCOO() {
    require(msg.sender == cooAddress);
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

  /** Information Query Fns **/
  /// @notice Get contributed balance in _tokenId token group for user
  /// @param _tokenId The ID of the token to be queried
  function getContributionBalanceForTokenGroup(uint256 _tokenId) public view returns (uint balance) {
    var group = tokenIndexToGroup[_tokenId];
    require(group.exists);
    balance = group.addressToContribution[msg.sender];
  }

  /// @notice Get no. of contributors in _tokenId token group
  /// @param _tokenId The ID of the token to be queried
  function getContributorsInTokenGroupCount(uint256 _tokenId) public view returns (uint count) {
    var group = tokenIndexToGroup[_tokenId];
    require(group.exists);
    count = group.contributorArr.length;
  }

  /// @notice Get list of tokenIds of token groups the user contributed to
  function getGroupsContributedTo() public view returns (uint256[] groupIds) {
    // Safety check to prevent against an unexpected 0x0 default.
    require(_addressNotNull(msg.sender));

    var contributor = userAddressToContributor[msg.sender];
    require(contributor.exists);

    groupIds = contributor.groupArr;
  }

  /// @notice Get price at which token group purchased _tokenId token
  function getGroupPurchasedPrice(uint256 _tokenId) public view returns (uint256 price) {
    var group = tokenIndexToGroup[_tokenId];
    require(group.exists);
    require(group.purchasePrice > 0);
    price = group.purchasePrice;
  }

  /// @notice Get withdrawable balance from sale proceeds for a user
  function getWithdrawableBalance() public view returns (uint256 balance) {
    // Safety check to prevent against an unexpected 0x0 default.
    require(_addressNotNull(msg.sender));

    var contributor = userAddressToContributor[msg.sender];
    require(contributor.exists);

    balance = contributor.withdrawableBalance;
  }

  /// @notice Get total contributed balance in _tokenId token group
  /// @param _tokenId The ID of the token group to be queried
  function getTokenGroupTotalBalance(uint256 _tokenId) public view returns (uint balance) {
    var group = tokenIndexToGroup[_tokenId];
    require(group.exists);
    balance = group.contributedBalance;
  }

  /** Action Fns **/
  /// @notice Backup function for activating token purchase
  ///  requires sender to be a member of the group or CLevel
  /// @param _tokenId The ID of the Token group
  function activatePurchase(uint256 _tokenId) public {
    var group = tokenIndexToGroup[_tokenId];
    require(group.addressToContribution[msg.sender] > 0 ||
            msg.sender == ceoAddress ||
            msg.sender == cooAddress ||
            msg.sender == cfoAddress);

    // Safety check that enough money has been contributed to group
    var price = linkedContract.priceOf(_tokenId);
    require(group.contributedBalance >= price);

    // Safety check that token had not be purchased yet
    require(group.purchasePrice == 0);

    _purchase(_tokenId, price);
  }

  /// @notice Allow user to contribute to _tokenId token group
  /// @param _tokenId The ID of the token group to be joined
  function contributeToTokenGroup(uint256 _tokenId) public payable {
    address userAdd = msg.sender;
    // Safety check to prevent against an unexpected 0x0 default.
    require(_addressNotNull(userAdd));

    /// Safety check to make sure contributor has not already joined this group
    var group = tokenIndexToGroup[_tokenId];
    var contributor = userAddressToContributor[userAdd];
    if (!group.exists) { // Create group if not exists
      group.exists = true;
      activeGroups += 1;
    } else {
      require(group.addressToContributorArrIndex[userAdd] == 0);
    }

    if (!contributor.exists) { // Create contributor if not exists
      userAddressToContributor[userAdd].exists = true;
    } else {
      require(contributor.tokenIdToGroupArrIndex[_tokenId] == 0);
    }

    // Safety check to make sure group isn't currently holding onto token
    //  or has a group record stored (for redistribution)
    require(group.purchasePrice == 0);

    /// Safety check to ensure amount contributed is higher than min required percentage
    ///  of purchase price
    uint256 tokenPrice = linkedContract.priceOf(_tokenId);
    require(msg.value >= uint256(SafeMath.div(tokenPrice, MAX_CONTRIBUTION_SLOTS)));

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

    JoinGroup(
      _tokenId,
      userAdd,
      tokenIndexToGroup[_tokenId].contributedBalance,
      tokenIndexToGroup[_tokenId].addressToContribution[userAdd]
    );

    // Purchase token if enough funds contributed
    if (tokenIndexToGroup[_tokenId].contributedBalance >= tokenPrice) {
      _purchase(_tokenId, tokenPrice);
    }
  }

  /// @notice Allow user to leave purchase group; note that their contribution
  ///  will be added to their withdrawable balance, and not directly refunded.
  ///  User can call withdrawBalance to retrieve funds.
  /// @param _tokenId The ID of the Token purchase group to be left
  function leaveTokenGroup(uint256 _tokenId) public {
    address userAdd = msg.sender;

    var group = tokenIndexToGroup[_tokenId];
    var contributor = userAddressToContributor[userAdd];

    // Safety check to prevent against an unexpected 0x0 default.
    require(_addressNotNull(userAdd));

    // Safety check to make sure group exists;
    require(group.exists);

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

  /// @dev Withdraw balance from own account
  function withdrawBalance() public {
    require(_addressNotNull(msg.sender));
    var contributor = userAddressToContributor[msg.sender];
    require(contributor.exists);

    uint256 balance = contributor.withdrawableBalance;
    contributor.withdrawableBalance = 0;

    if (balance > 0) {
      msg.sender.transfer(balance);
      FundsWithdrawn(msg.sender, balance);
    }
  }

  /** Admin Fns **/
  /// @notice Backup fn to allow redistribution of funds after sale,
  ///  for the special scenario where an alternate sale platform is used
  /// @param _tokenId The ID of the Token purchase group
  /// @param _amount Funds to be redistributed
  function redistributeCustomSaleProceeds(uint256 _tokenId, uint256 _amount) public onlyCOO {
    var group = tokenIndexToGroup[_tokenId];

    // Safety check to make sure group exists and had purchased the token
    require(group.exists);
    require(group.purchasePrice > 0);

    _redistributeProceeds(_tokenId, _amount);
  }

  /// @notice Allow redistribution of funds after a sale
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
    _redistributeProceeds(_tokenId, paymentIntoContract);
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

  /// @notice Backup fn to allow transfer of token out of
  ///  contract, for use where a purchase group wants to use an alternate
  ///  selling platform
  /// @param _tokenId The ID of the Token purchase group
  /// @param _to Address to transfer token to
  function transferToken(uint256 _tokenId, address _to) public onlyCOO {
    var group = tokenIndexToGroup[_tokenId];

    // Safety check to make sure group exists and had purchased the token
    require(group.exists);
    require(group.purchasePrice > 0);

    linkedContract.transfer(_to, _tokenId);
  }

  /// @dev Withdraws sale commission, CFO-only functionality
  /// @param _to Address for commission to be sent to
  function withdrawCommission(address _to) public onlyCFO {
    uint256 balance = commissionBalance;
    address transferee = (_to == address(0)) ? cfoAddress : _to;
    commissionBalance = 0;
    if (balance > 0) {
      transferee.transfer(balance);
    }
    FundsWithdrawn(transferee, balance);
  }

  /*** PRIVATE FUNCTIONS ***/
  /// @dev Safety check on _to address to prevent against an unexpected 0x0 default.
  /// @param _to Address to be checked
  function _addressNotNull(address _to) private pure returns (bool) {
    return _to != address(0);
  }

  /// @dev Clears record of a Group from a Contributor's record
  /// @param _tokenId Token ID of Group to be cleared
  /// @param _userAdd Address of Contributor
  function _clearGroupRecordInContributor(uint256 _tokenId, address _userAdd) private {
    // Index saved is 1 + the array's index, b/c 0 is the default value
    //  in a mapping.
    uint gIndex = userAddressToContributor[_userAdd].tokenIdToGroupArrIndex[_tokenId] - 1;
    uint lastGIndex = userAddressToContributor[_userAdd].groupArr.length - 1;

    // clear Group record in Contributor
    userAddressToContributor[_userAdd].tokenIdToGroupArrIndex[_tokenId] = 0;

    // move tokenId from end of array to deleted Group record's spot
    if (lastGIndex > 0) {
      userAddressToContributor[_userAdd].tokenIdToGroupArrIndex[userAddressToContributor[_userAdd].groupArr[lastGIndex]] = gIndex;
      userAddressToContributor[_userAdd].groupArr[gIndex] = userAddressToContributor[_userAdd].groupArr[lastGIndex];
    }

    userAddressToContributor[_userAdd].groupArr.length -= 1;
  }

  /// @dev Calculates next price of celebrity token
  /// @param _oldPrice Previous price
  function _newPrice(uint256 _oldPrice) private view returns (uint256 newPrice) {
    if (_oldPrice < firstStepLimit) {
      // first stage
      newPrice = SafeMath.div(SafeMath.mul(_oldPrice, 200), 94);
    } else if (_oldPrice < secondStepLimit) {
      // second stage
      newPrice = SafeMath.div(SafeMath.mul(_oldPrice, 120), 94);
    } else {
      // third stage
      newPrice = SafeMath.div(SafeMath.mul(_oldPrice, 115), 94);
    }
  }

  /// @dev Calls CelebrityToken purchase fn and updates records
  /// @param _tokenId Token ID of token to be purchased
  /// @param _amount Amount to be paid to CelebrityToken
  function _purchase(uint256 _tokenId, uint256 _amount) private {
    tokenIndexToGroup[_tokenId].purchasePrice = _amount;
    linkedContract.purchase.value(_amount)(_tokenId);
    TokenPurchased(_tokenId, _amount);
  }

  /// @dev Redistribute proceeds from token purchase
  /// @param _tokenId Token ID of token to be purchased
  /// @param _amount Amount paid into contract for token
  function _redistributeProceeds(uint256 _tokenId, uint256 _amount) private {
    uint256 fundsForDistribution = uint256(SafeMath.div(SafeMath.mul(_amount, 97), 100));
    uint256 commission = _amount;

    for (uint i = 0; i < tokenIndexToGroup[_tokenId].contributorArr.length; i++) {
      address userAdd = tokenIndexToGroup[_tokenId].contributorArr[i];

      // calculate contributor's sale proceeds and add to their withdrawable balance
      uint256 userProceeds = uint256(SafeMath.div(SafeMath.mul(fundsForDistribution,
        tokenIndexToGroup[_tokenId].addressToContribution[userAdd]),
        tokenIndexToGroup[_tokenId].contributedBalance));
      userAddressToContributor[userAdd].withdrawableBalance += userProceeds;

      _clearGroupRecordInContributor(_tokenId, userAdd);

      // clear contributor record on group
      tokenIndexToGroup[_tokenId].addressToContribution[userAdd] = 0;
      tokenIndexToGroup[_tokenId].addressToContributorArrIndex[userAdd] = 0;
      commission -= userProceeds;
      activeGroups -= 1;
      tokenIndexToGroup[_tokenId].exists = false;
      FundsRedistributed(_tokenId, userAdd, userProceeds);
    }

    commissionBalance += commission;
    Commission(_tokenId, commission);
    tokenIndexToGroup[_tokenId].contributorArr.length = 0;
    tokenIndexToGroup[_tokenId].contributedBalance = 0;
    tokenIndexToGroup[_tokenId].purchasePrice = 0;
  }
}
