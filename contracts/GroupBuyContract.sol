pragma solidity ^0.4.18;
import "zeppelin-solidity/contracts/math/SafeMath.sol"; // solhint-disable-line


contract GroupBuyContract {
  event TokenPurchased(uint256 tokenId);

  /*** CONSTANTS ***/
  string public constant NAME = "GroupBuy";
  uint256 public constant MIN_CONTRIBUTION = 0.1 ether; // Check

  /*** STORAGE ***/
  /// @dev A mapping from token IDs to the group associated with that token.
  mapping(uint256 => Group) private tokenIndexToGroup;

  // @dev A mapping from owner address to count of tokens that address owns.
  //  Used internally inside balanceOf() to resolve ownership count.
  mapping (address => uint256) private ownershipTokenCount;

  /*** DATATYPES ***/
  struct Group {
    string name;
    uint256 startingBalance;
    uint256 contributorCount;
    mapping(address => Contributor) addressToContributor;
    bool holdingToken;
    uint256 currentBalance;
  }

  struct Contributor {
    address contribAddress;
    uint256 amount;
  }

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

  /// Access modifier for contract owner only functionality
  modifier onlyCLevel() {
    require(
      msg.sender == ceoAddress ||
      msg.sender == cooAddress
    );
    _;
  }

  /*** CONSTRUCTOR ***/
  function GroupBuyContract() public {
    ceoAddress = msg.sender;
    cooAddress = msg.sender;
  }

  /*** PUBLIC FUNCTIONS ***/
  /// @notice Get contributor count
  /// @param _tokenId The ID of the token to be queried
  function getGroupContributorCount(uint256 _tokenId) public view returns (uint count) {
    group = tokenIndexToGroup[_tokenId];
    require(group > 0); // DOUBLE CHECK IF THIS IS A VALID CHECK
    count = group.contributorCount;
  }

  /// @notice Get contributor count
  /// @param _tokenId The ID of the token to be queried
  function getGroupBalance(uint256 _tokenId) public view returns (uint balance) {
    group = tokenIndexToGroup[_tokenId];
    require(group > 0); // DOUBLE CHECK IF THIS IS A VALID CHECK
    count = group.contributorCount;
  }

  /// @notice Allow user to join purchase group
  /// @param _tokenId The ID of the Token purchase group to be joined
  function joinGroup(uint256 _tokenId) public {
    address newOwner = msg.sender;

    // Safety check to prevent against an unexpected 0x0 default.
    require(_addressNotNull(newOwner));

    /// amount contributed to be higher than zero
    require(msg.value > MIN_CONTRIBUTION);

    group = tokenIndexToGroup[_tokenId];

    Contributor memory _contributor = Contributor({
      address: newOwner,
      amount: balance
    });


  }

  /// @notice Allow user to leave purchase group
  /// @param _tokenId The ID of the Token purchase group to be left
  function leaveGroup(uint256 _tokenId) public {
    address newOwner = msg.sender;



    // Safety check to prevent against an unexpected 0x0 default.
    require(_addressNotNull(newOwner));

    /// amount contributed to be higher than zero
    require(msg.value > 0);


  }
}
