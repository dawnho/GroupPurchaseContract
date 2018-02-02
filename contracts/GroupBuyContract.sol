pragma solidity ^0.4.18;
import "zeppelin-solidity/contracts/math/SafeMath.sol"; // solhint-disable-line
import "./CelebrityToken.sol";


contract GroupBuyContract {
  /*** CONSTANTS ***/
  bool public isGroupBuy = true;
  uint256 public constant MAX_CONTRIBUTION_SLOTS = 20; // Check

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
    bool tokenPurchased; // Set to true if token was purchased by group
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
  event FundsReceived(uint256 amount, address _from);

  event Contribution(
    uint256 _tokenId,
    address contributor,
    uint256 groupBalance,
    uint256 netChange
  );

  event TokenPurchaseAttempt(uint256 balance, address origin);

  event TokenSold(uint256 balance, address origin);

  /*** STORAGE ***/
  /// @dev A mapping from token IDs to the group associated with that token.
  mapping(uint256 => Group) private tokenIndexToGroup;

  // @dev A mapping from owner address to available balance not held by a Group.
  mapping (address => Contributor) private userAddressToContributor;

  uint256 public groupCount;
  uint256 public usersBalance;

  CelebrityToken private celebContract;

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
    celebContract = CelebrityToken(contractAddress);
  }

  /*** PUBLIC FUNCTIONS ***/
  /// @notice Fallback fn for receiving ether
  function () public payable {
    FundsReceived(msg.value, msg.sender);
  }

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
    require(group.exists); // DOUBLE CHECK IF THIS IS A VALID CHECK
    count = group.contributorArr.length;
  }

  function getGroupsContributedTo() public view returns (uint256[] groupIds) {
    var contributor = userAddressToContributor[msg.sender];
    require(contributor.exists);
    groupIds = contributor.groupArr;
  }

  /// @notice Get address of connected contract
  function getLinkedContractAddress() public view returns (address) {
    return celebContract;
  }

  /// @notice Get contributed balance
  /// @param _tokenId The ID of the token to be queried
  function getTokenGroupTotalBalance(uint256 _tokenId) public view returns (uint balance) {
    var group = tokenIndexToGroup[_tokenId];
    require(group.exists);
    balance = group.contributedBalance;
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
      tokenIndexToGroup[_tokenId].exists = true;
    } else {
      require(tokenIndexToGroup[_tokenId].addressToContributorArrIndex[userAdd] == 0);
    }

    if (!contributor.exists) {
      userAddressToContributor[userAdd].exists = true;
    } else {
      require(userAddressToContributor[userAdd].tokenIdToGroupArrIndex[_tokenId] == 0);
    }

    uint256 tokenPrice = celebContract.priceOf(_tokenId);

    /// Safety check to ensure amount contributed is higher than min portion of the
    ///  purchase price
    require(msg.value > SafeMath.div(tokenPrice, MAX_CONTRIBUTION_SLOTS));

    if (!tokenIndexToGroup[_tokenId].exists) {
      tokenIndexToGroup[_tokenId].exists = true;
    }

    // Index saved is 1 + the array's index, b/c 0 is the default value in a mapping,
    //  so as stored on the mapping, array index will begin at 1
    uint256 cIndex = tokenIndexToGroup[_tokenId].contributorArr.push(userAdd);
    tokenIndexToGroup[_tokenId].addressToContributorArrIndex[userAdd] = cIndex;

    tokenIndexToGroup[_tokenId].addressToContribution[userAdd] = msg.value;
    tokenIndexToGroup[_tokenId].contributedBalance += msg.value;

    if (!contributor.exists) {
      userAddressToContributor[userAdd].exists = true;
    }

    // Index saved is 1 + the array's index, b/c 0 is the default value in a mapping,
    //  so as stored on the mapping, array index will begin at 1
    uint256 gIndex = userAddressToContributor[userAdd].groupArr.push(_tokenId);
    userAddressToContributor[userAdd].tokenIdToGroupArrIndex[_tokenId] = gIndex;

    usersBalance += msg.value;

    Contribution(
      _tokenId,
      userAdd,
      tokenIndexToGroup[_tokenId].contributedBalance,
      msg.value
    );

    if (tokenIndexToGroup[_tokenId].contributedBalance > tokenPrice) {
      //run purchase!!!!! @#$@#)$(@#())
    }
  }

  /// @notice Allow user to withdraw contribution to purchase group
  /// @param _tokenId The ID of the Token purchase group to be left
  function withdrawFromTokenGroup(uint256 _tokenId) public {
    address userAdd = msg.sender;

    var group = tokenIndexToGroup[_tokenId];
    var contributor = userAddressToContributor[userAdd];

    // Safety check to prevent against an unexpected 0x0 default.
    require(_addressNotNull(userAdd));

    // Safety checks to ensure contributor has contributed to group
    require(group.addressToContributorArrIndex[userAdd] > 0);
    require(contributor.tokenIdToGroupArrIndex[_tokenId] > 0);

    // Index was saved is 1 + the array's index, b/c 0 is the default value
    //  in a mapping.
    uint cIndex = group.addressToContributorArrIndex[userAdd] - 1;
    uint lastCIndex = group.contributorArr.length - 1;
    uint refundBalance = group.addressToContribution[userAdd];
    address lastAddress = group.contributorArr[lastCIndex];

    // clear contribution record in group
    tokenIndexToGroup[_tokenId].addressToContributorArrIndex[userAdd] = 0;
    tokenIndexToGroup[_tokenId].addressToContribution[userAdd] = 0;

    // move address in last position to deleted contributor's spot
    if (lastCIndex > 0) {
      tokenIndexToGroup[_tokenId].addressToContributorArrIndex[lastAddress] = cIndex;
      tokenIndexToGroup[_tokenId].contributorArr[cIndex] = lastAddress;
    }

    tokenIndexToGroup[_tokenId].contributorArr.length -= 1;
    tokenIndexToGroup[_tokenId].contributedBalance -= refundBalance;

    // Index saved is 1 + the array's index, b/c 0 is the default value
    //  in a mapping.
    uint gIndex = contributor.tokenIdToGroupArrIndex[_tokenId] - 1;
    uint lastGIndex = contributor.groupArr.length - 1;
    uint lastTokenId = contributor.groupArr[lastGIndex];

    // clear group record in Contributor
    userAddressToContributor[userAdd].tokenIdToGroupArrIndex[_tokenId] = 0;

    // move tokenId in last position to deleted group record's spot
    if (lastGIndex > 0) {
      userAddressToContributor[userAdd].tokenIdToGroupArrIndex[lastTokenId] = gIndex;
      userAddressToContributor[userAdd].groupArr[gIndex] = lastTokenId;
    }

    usersBalance -= refundBalance;

    userAddressToContributor[userAdd].withdrawableBalance += refundBalance;
    //userAdd.transfer(refundBalance); // DO WE WANT TO USE WITHDRAWAL METHOD INSTEAD

    Contribution(
      _tokenId,
      userAdd,
      tokenIndexToGroup[_tokenId].contributedBalance,
      SafeMath.mul(uint256(-1), refundBalance)
    );
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
}
