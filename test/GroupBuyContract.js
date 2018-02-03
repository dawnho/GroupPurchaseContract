// Specifically request an abstraction for GroupBuyContract
let CelebrityToken = artifacts.require("CelebrityToken");
let GroupBuyContract = artifacts.require("GroupBuyContract");
import { expectThrow } from "zeppelin-solidity/test/helpers/expectThrow";
let Web3 = require('web3');
let web3 = new Web3(new Web3.providers.HttpProvider("http://localhost:9545"));


contract('GroupBuyContract#setup', accounts => {
  it("should set contract up with proper attributes", async () => {
    let groupBuy = await GroupBuyContract.deployed();
    const ceo = await groupBuy.ceoAddress.call();
    const coo = await groupBuy.cooAddress.call();
    const cfo = await groupBuy.cfoAddress.call();
    const address = await groupBuy.linkedContract.call();
    assert.equal(ceo, accounts[0], "CEO was set incorrectly");
    assert.equal(coo, accounts[0], "COO was set incorrectly");
    assert.equal(cfo, accounts[0], "CFO was set incorrectly");
    assert.equal(address, CelebrityToken.address, "Contract Address was set incorrectly");
  });
});

contract("GroupBuyContract", accounts => {
  describe("#contributeToTokenGroup", () => {
    let account_one, account_two, account_three, celeb, groupBuy;

    before(async () => {
      account_one = accounts[0];
      account_two = accounts[1];
      account_three = accounts[2];
      celeb = await CelebrityToken.deployed();
      groupBuy = await GroupBuyContract.deployed();
      await celeb.createPromoPerson(account_one, "Adam", 1000, {from: account_one});
      await celeb.createPromoPerson(account_one, "Bob", 2000, {from: account_one});
    });

    it("should save the contribution record", () => {
      let tokenId = 1;
      let contribution = 100;
      let contractUsersBalance, contribGroupArr, groupContribBalance, groupContribCount,
        groupTotalBalance, contribWithdrawableBalance;
      return groupBuy.contributeToTokenGroup(tokenId, {
        from: account_one,
        value: contribution
      }).then(() => {
        return groupBuy.getContributionBalanceForTokenGroup(tokenId, {from: account_one});
      }).then(balance => {
        groupContribBalance = balance;
        return groupBuy.getTokenGroupTotalBalance(tokenId, {from: account_one});
      }).then(balance => {
        groupTotalBalance = balance;
        return groupBuy.getContributorsInTokenGroupCount(tokenId, {from: account_one});
      }).then(count => {
        groupContribCount = count;
        return groupBuy.usersBalance({from: account_one});
      }).then(balance => {
        contractUsersBalance = balance;
        return groupBuy.getGroupsContributedTo({from: account_one});
      }).then(arr => {
        contribGroupArr = arr;
        return groupBuy.getWithdrawableBalance({from: account_one});
      }).then(balance => {
        contribWithdrawableBalance = balance
      }).then(() => {
        assert.equal(groupContribBalance, contribution);
        assert.equal(groupTotalBalance, contribution);
        assert.equal(contractUsersBalance, contribution);
        assert.equal(groupContribCount, 1);
        assert.equal(contribWithdrawableBalance, 0);
        assert.equal(contribGroupArr[0], tokenId);
      });
    });

    it("should not save the contribution record if price too low", async () => {
      let tokenId = 1;
      let tooSmallContribution = 10;
      let okContribution = 200;

      return expectThrow(groupBuy.contributeToTokenGroup(tokenId, {
        from: account_two,
        value: tooSmallContribution
      })).then(() => {
        return groupBuy.contributeToTokenGroup(tokenId, {
          from: account_two,
          value: okContribution
        });
      }).then(() => {
        return groupBuy.getContributionBalanceForTokenGroup(tokenId, {from: account_two});
      }).then(balance => {
        assert.equal(balance.toNumber(), okContribution);
      });
    });

    it("should revert if contributor already contributed", async () => {
      let tokenId = 1;
      let contribution = 300;

      return expectThrow(groupBuy.contributeToTokenGroup(tokenId, {
        from: account_two,
        value: contribution
      }));
    });

    it("should purchase token when enough contributed", async () => {
      let tokenId = 1;
      let contribution = 1700;
      let contributionBalance;

      return groupBuy.contributeToTokenGroup(tokenId, {
        from: account_three,
        value: contribution
      }).then(() => {
        return groupBuy.getContributionBalanceForTokenGroup(tokenId, {from: account_three});
      }).then(balance => {
        contributionBalance = balance;
        return groupBuy.getGroupPurchasedPrice(tokenId, {from: account_three});
      }).then(price => {
        assert.equal(price, 2000);
        assert.equal(contributionBalance.toNumber(), contribution);
      });
    });
  });
});
