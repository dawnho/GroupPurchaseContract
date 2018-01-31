pragma solidity ^0.4.18;
import "zeppelin-solidity/contracts/math/SafeMath.sol"; // solhint-disable-line


contract CelebrityToken {
  function approve(address _to, uint256 _tokenId) public;
  function balanceOf(address _owner) public view returns (uint256 balance);
  function createPromoPerson(address _owner, string _name, uint256 _price) public;
  function createContractPerson(string _name) public;
  function getPerson(uint256 _tokenId) public view returns (string personName, uint256 sellingPrice, address owner);
  function implementsERC721() public pure returns (bool);
  function name() public pure returns (string);
  function ownerOf(uint256 _tokenId) public view returns (address owner);
  function payout(address _to) public;
  function purchase(uint_tokenId) public payable;
  function priceOf(uint256 _tokenId) public view returns (uint256 price);
  function setCEO(address _newCEO) public;
  function setCOO(address _newCOO) public;
  function symbol() public pure returns (string);
  function takeOwnership(uint256 _tokenId) public;
  function tokensOfOwner(address _owner)public view returns(uint256[] ownerTokens);
  function totalSupply() public view returns (uint256 total);
  function transfer(address _to, uint256 _tokenId) public;
  function transferFrom(address _from, address _to, uint256 _tokenId) public;
  function withdraw() public;
}


contract GroupBuyContract {
  /*** CONSTANTS ***/
  bool public isGroupBuy = true;
  uint256 public constant MIN_CONTRIBUTION = 0.1 ether; // Check

  /*** DATATYPES ***/
  // @dev A Group is created for all the contributors who want to contribute
  //  to the purchase of a particular token.
  struct Group {
    // Array of addresses of contributors in group
    address[] contributorArr;
    // Maps address to an address's position (+ 1) in the contributorArr;
    // 1 is added to the position because zero is the default value in the mapping
    mapping(address => uint) addressToContributorArrIndex;
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
    mapping(uint256 => uint) tokenIdToGroupIndex;
    // Array of tokenIds contributed to by a contributor
    uint256[] groupArr;
    bool exists;
    uint256 proceedsBalance; // ledger for proceeds from group sale
  }

  /*** EVENTS ***/
  event Contribution(uint256 _tokenId, address contributor, uint256 newBalance, uint256 netChange);
  event FundsReceived(uint256 balance, address origin);

  /*** STORAGE ***/
  /// @dev A mapping from token IDs to the group associated with that token.
  mapping(uint256 => Group) private tokenIndexToGroup;

  // @dev A mapping from owner address to available balance not held by a Group.
  mapping (address => Contributor) private userAddressToContributor;

  uint256 public groupCount;

  CelebrityToken celebContract;

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

  /// @notice Get contributed balance
  /// @param _tokenId The ID of the token to be queried
  function getContributionInGroup(uint256 _tokenId) public view returns (uint balance) {
    group = tokenIndexToGroup[_tokenId];
    require(group.exists);
    balance = group.addressToContribution[msg.sender];
  }

  /// @notice Get no. of contributors in a Group
  /// @param _tokenId The ID of the token to be queried
  function getGroupContributorCount(uint256 _tokenId) public view returns (uint count) {
    group = tokenIndexToGroup[_tokenId];
    require(group.exists); // DOUBLE CHECK IF THIS IS A VALID CHECK
    count = group.contributorArr.length;
  }

  /// @notice Get contributed balance
  /// @param _tokenId The ID of the token to be queried
  function getTotalGroupBalance(uint256 _tokenId) public view returns (uint balance) {
    group = tokenIndexToGroup[_tokenId];
    require(group.exists);
    balance = group.contributedBalance;
  }

  /// @notice Allow user to join purchase group
  /// @param _tokenId The ID of the Token purchase group to be joined
  function contributeToGroup(uint256 _tokenId) public {
    address newOwner = msg.sender;
    Group storage group = tokenIndexToGroup[_tokenId];

    // Safety check to prevent against an unexpected 0x0 default.
    require(_addressNotNull(newOwner));

    /// Safety check to ensure amount contributed is higher than MIN_CONTRIBUTION
    require(msg.value > MIN_CONTRIBUTION);

    /// Safety check to make sure contributor has not already joined this group buy
    require(group[_tokenId].addressToContributorArrIndex[msg.sender] == 0);

    uint256 tokenPrice =

    if (!group.exists) {
      tokenIndexToGroup[_tokenId].exists = true;
    }

    uint index = tokenIndexToGroup[_tokenId].contributorArr.push(msg.sender);
    tokenIndexToGroup[_tokenId].addressToContributorArrIndex






    /* Contributor memory _contributor = Contributor({
      address: newOwner,
      amount: balance
    }); */


  }

  /// @notice Allow user to withdraw contribution to purchase group
  /// @param _tokenId The ID of the Token purchase group to be left
  function withdrawFromGroup(uint256 _tokenId) public {
    address newOwner = msg.sender;



    // Safety check to prevent against an unexpected 0x0 default.
    require(_addressNotNull(newOwner));

    /// amount contributed to be higher than zero
    require(msg.value > 0);


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
