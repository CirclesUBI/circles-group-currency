// SPDX-License-Identifier: AGPL
pragma solidity ^0.8.0;

import "./DiscriminatorList.sol";
import "../../IGroupMembershipDiscriminator.sol";
import "../../../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

contract XorAggregateDiscriminator is Ownable, DiscriminatorList, IGroupMembershipDiscriminator {

    constructor(address _owner, IGroupMembershipDiscriminator[] memory _discriminators) {
        transferOwnership(_owner);
        discriminators = _discriminators;
    }

    function requireIsMember(address _user) external view {
        require(this.isMember(_user), "Not a member according to XOR logic");
    }

    function isMember(address _user) external view returns(bool) {
        uint256 trueCount = 0;
        for(uint i = 0; i < discriminators.length; i++) {
            if(discriminators[i].isMember(_user)) {
                trueCount += 1;
            }
        }
        return trueCount == 1;
    }
}
