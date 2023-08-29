// SPDX-License-Identifier: AGPL
pragma solidity ^0.8.0;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "./IGroupMembershipDiscriminator.sol";
import "./IHub.sol";

contract GroupCurrencyToken is ERC20 {

    using SafeERC20 for ERC20;

    uint8 public mintFeePerThousand;
    
    bool public suspended;
    bool public onlyOwnerCanMint;
    bool public onlyTrustedCanMint;

    address public owner; // the safe/EOA/contract that deployed this token, can be changed by owner
    address public hub; // the address of the hub this token is associated with
    address public treasury; // account which gets the personal tokens for whatever later usage
    address public discriminator;
    
    event Minted(address indexed _receiver, uint256 _amount, uint256 _mintAmount, uint256 _mintFee);
    event Suspended(address indexed _owner);
    event OwnerChanged(address indexed _old, address indexed _new);
    event OnlyOwnerCanMint(bool indexed _onlyOwnerCanMint);
    event OnlyTrustedCanMint(bool indexed _onlyTrustedCanMint);
    event MemberTokenAdded(address indexed _memberToken);
    event MemberTokenRemoved(address indexed _memberToken);

    /// @dev modifier allowing function to be only called by the token owner
    modifier onlyOwner() {
        require(msg.sender == owner, "only owner can call");
        _;
    }

    constructor(address _discriminator, address _hub, address _treasury, address _owner, uint8 _mintFeePerThousand, string memory _name, string memory _symbol) ERC20(_name, _symbol) {
            discriminator = _discriminator;
        owner = _owner;
        hub = _hub;
        treasury = _treasury;
        mintFeePerThousand = _mintFeePerThousand;
        IHub(hub).organizationSignup();
    }
    
    function suspend(bool _suspend) external onlyOwner {
        suspended = _suspend;
        emit Suspended(owner);
    }
    
    function changeOwner(address _owner) external onlyOwner {
        owner = _owner;
        emit OwnerChanged(msg.sender, owner);
    }

    function setOnlyOwnerCanMint(bool _onlyOwnerCanMint) external onlyOwner {
        onlyOwnerCanMint = _onlyOwnerCanMint;
        emit OnlyOwnerCanMint(onlyOwnerCanMint);
    }

    function setOnlyTrustedCanMint(bool _onlyTrustedCanMint) external onlyOwner {
        onlyTrustedCanMint = _onlyTrustedCanMint;
        emit OnlyTrustedCanMint(onlyTrustedCanMint);
    }

//    function addMemberToken(address _member) external onlyOwner {
//        address memberTokenUser = IHub(hub).tokenToUser(_member);
//        _directTrust(memberTokenUser, 100);
//        emit MemberTokenAdded(memberTokenUser);
//    }
//
//    function removeMemberToken(address _member) external onlyOwner {
//        address memberTokenUser = IHub(hub).tokenToUser(_member);
//        _directTrust(memberTokenUser, 0);
//        emit MemberTokenRemoved(memberTokenUser);
//    }

    function addMember(address _user) external {
        IGroupMembershipDiscriminator(discriminator).requireIsMember(address(this), _user); // Must revert if not a member, everyone can add qualified members
        // Add a trust relation between this org and the user
        _directTrust(_user, 100);
    }
    function removeMember(address _user) external {
        if (!IGroupMembershipDiscriminator(discriminator).isMember(address(this), _user)) {
            // remove member, no matter who called the function
            _directTrust(_user, 0);
        }
        // If sender is the member in question, remove him from the group.
        // If sender is the owner, also remove the member from the group.
        if (msg.sender == _user || msg.sender == owner) {
            _directTrust(_user, 0);
        }
    }

    // Group currently is created from collateral tokens, which have to be transferred to this Token before.
    // Note: This function is not restricted, so anybody can mint with the collateral Token! The function call must be transactional to be safe.
    function mint(address[] calldata _collateral, uint256[] calldata _amount) external returns (uint256) {
        require(!suspended, "Minting is suspended.");
        // Check status
        if (onlyOwnerCanMint) {
            require(msg.sender == owner, "Only owner can mint");
        } else if (onlyTrustedCanMint) {
            require(IHub(hub).limits(address(this), msg.sender) > 0, "GCT does not trust sender");
        }
        uint mintedAmount = 0;
        for (uint i = 0; i < _collateral.length; i++) {
            mintedAmount += _mintGroupCurrencyTokenForCollateral(_collateral[i], _amount[i]);
        }
        return mintedAmount;
    }

    function transfer(address _dst, uint256 _wad) public override returns (bool) {
        // this code shouldn't be necessary, but when it's removed the gas estimation methods
        // in the gnosis safe no longer work, still true as of solidity 7.1
        return super.transfer(_dst, _wad);
    }

    function _mintGroupCurrencyTokenForCollateral(address _collateral, uint256 _amount) internal returns (uint256) {
        // Check if the Collateral Owner is trusted by this GroupCurrencyToken
        address collateralOwner = IHub(hub).tokenToUser(_collateral);
        require(IHub(hub).limits(address(this), collateralOwner) > 0, "collateral owner not trusted");
        uint256 mintFee = (_amount / 1000) * mintFeePerThousand;
        uint256 mintAmount = _amount - mintFee;
        // mint amount-fee to msg.sender
        _mint(msg.sender, mintAmount);
        // Token Swap, send CRC from GCTO to Treasury (has been transferred to GCTO by transferThrough)
        ERC20(_collateral).safeTransfer(treasury, _amount);
        emit Minted(msg.sender, _amount, mintAmount, mintFee);
        return mintAmount;
    }

    // Trust must be called by this contract (as a delegate) on Hub
    function _directTrust(address _trustee, uint _amount) internal {
        require(_trustee != address(0), "trustee must be valid address");
        IHub(hub).trust(_trustee, _amount);
    }
}
