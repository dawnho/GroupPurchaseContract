// Specifically request an abstraction for GroupBuyContract
let CelebrityToken = artifacts.require("CelebrityToken");
let GroupBuyContract = artifacts.require("GroupBuyContract");
import expectThrow from "zeppelin-solidity/test/helpers/expectThrow";
let Web3 = require('web3');
let web3 = new Web3(new Web3.providers.HttpProvider("http://localhost:9545"));


contract('GroupBuyContract#setup', accounts => {
  it("should set contract up with proper attributes", async () => {
    let groupBuy = await GroupBuyContract.deployed();
    const ceo = await groupBuy.ceoAddress.call();
    const coo = await groupBuy.cooAddress.call();
    const cfo = await groupBuy.cfoAddress.call();
    const address = await groupBuy.getLinkedContractAddress.call();
    assert.equal(ceo, accounts[0], "CEO was set incorrectly");
    assert.equal(coo, accounts[0], "COO was set incorrectly");
    assert.equal(cfo, accounts[0], "CFO was set incorrectly");
    assert.equal(address, CelebrityToken.address, "Contract Address was set incorrectly");
  });
});

contract("GroupBuyContract", accounts => {
  describe("#contributeToTokenGroup", () => {
    let account_one, celeb, groupBuy;

    beforeEach(async () => {
      account_one = accounts[0];
      celeb = await CelebrityToken.deployed();
      groupBuy = await GroupBuyContract.deployed();
      await celeb.createPromoPerson(account_one, "Adam", 1000, {from: account_one});
      await celeb.createPromoPerson(account_one, "Bob", 2000, {from: account_one});
    });

    it("should save the contribution record", () => {
      let tokenId = 0;
      let contribution = 100;
      let contribCount, savedBalance, totalBalance;
      return groupBuy.contributeToTokenGroup(tokenId, {from: account_one, value: contribution}).then(() => {
        return groupBuy.getContributionBalanceForTokenGroup(0, {from: account_one});
      }).then(balance => {
        savedBalance = balance;
        return groupBuy.getTokenGroupTotalBalance(0, {from: account_one});
      }).then(balance => {
        totalBalance = balance;
        return groupBuy.getContributorsInTokenGroupCount(0, {from: account_one});
      }).then(count => {
        contribCount = count;
      }).then(() => {
        assert.equal(savedBalance, contribution);
        assert.equal(totalBalance, contribution);
        assert.equal(contribCount, 1);
      });
    });
  });

});
