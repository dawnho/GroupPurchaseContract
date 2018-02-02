var CelebrityToken = artifacts.require("CelebrityToken");
var GroupBuyContract = artifacts.require("GroupBuyContract");

module.exports = function(deployer, network) {
  if (network === "development") {
    deployer.deploy(CelebrityToken).then(() => {
      return deployer.deploy(GroupBuyContract, CelebrityToken.address);
    });
  } else {

  }
};
