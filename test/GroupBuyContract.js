// Specifically request an abstraction for GroupBuyContract
const CelebrityToken = artifacts.require("CelebrityToken");
const GroupBuyContract = artifacts.require("GroupBuyContract");

const _ = require('lodash');
const chai = require('chai');
const expect = chai.expect;
const should = chai.should();
const utils = require("./utils.js");
const Web3 = require('web3');
const web3 = new Web3(new Web3.providers.HttpProvider("http://localhost:7545"));

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
  describe("Joining and Leaving Groups", () => {
    let account_one, account_two, account_three, account_four, celeb, groupBuy;

    before(async () => {
      account_one = accounts[0];
      account_two = accounts[1];
      account_three = accounts[2];
      account_four = accounts[4];
      celeb = await CelebrityToken.deployed();
      groupBuy = await GroupBuyContract.deployed();
      await celeb.createPromoPerson(account_one, "Adam", 1000, {from: account_one});
      await celeb.createPromoPerson(account_one, "Bob", 2000, {from: account_one});
      await celeb.createPromoPerson(account_one, "Carrot", 3000, {from: account_one});
    });

    describe("#contributeToTokenGroup", () => {
      it("should save the contribution record", () => {
        let tokenId = 1;
        let contribution = 100;
        let contractUsersBalance, contribGroupArr, groupContribBalance, groupContribCount,
          groupTotalBalance, contribWithdrawableBalance;
        return groupBuy.contributeToTokenGroup(tokenId, {
          from: account_one,
          value: contribution
        }).then(tx => {
          expect(tx.receipt.status).to.equal('0x01', 'transaction should succeed');
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

        return groupBuy.contributeToTokenGroup(tokenId, {
          from: account_two,
          value: tooSmallContribution
        }).then(tx => {
          expect(tx.receipt.status).to.equal('0x00', 'transaction should fail');
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

        return groupBuy.contributeToTokenGroup(tokenId, {
          from: account_two,
          value: contribution
        }).then(tx => {
          expect(tx.receipt.status).to.equal('0x00', 'transaction should fail');
        });
      });

      it("should purchase token when enough contributed", async () => {
        let tokenId = 1;
        let contributionNeeded = 1700;
        let excessBalance = 100;

        return groupBuy.contributeToTokenGroup(tokenId, {
          from: account_three,
          value: contributionNeeded + excessBalance
        }).then(tx => {
          expect(tx.receipt.status).to.equal('0x01', 'transaction should succeed');
          return groupBuy.getContributionBalanceForTokenGroup(tokenId, {from: account_three});
        }).then(balance => {
          assert.equal(balance.toNumber(), contributionNeeded);
          return groupBuy.getGroupPurchasedPrice(tokenId, {from: account_three});
        }).then(price => {
          assert.equal(price, 2000);
          return celeb.ownerOf(tokenId, {from: account_three});
        }).then(address => {
          assert.equal(address, GroupBuyContract.address, "Contract Address was set incorrectly");
          return groupBuy.getWithdrawableBalance({from: account_three});
        }).then(balance => {
          assert.equal(balance, excessBalance);
        });
      });
    });

    describe("#withdrawBalance", () => {
      it("should deposit right amount in user's account", () => {
        let eventName = "FundsWithdrawn";

        var filterFn = o => {
          return o.event == eventName && o.logIndex == 0 && o.args._to == account_three
            && o.args.amount.toNumber() == 100;
        };

        return groupBuy.getWithdrawableBalance({from: account_three}).then(balance => {
          assert.equal(100, balance.toNumber());
          return groupBuy.withdrawBalance({from: account_three});
        }).then(tx => {
          expect(tx.receipt.status).to.equal('0x01', 'transaction should succeed');
          return groupBuy.getWithdrawableBalance({from: account_three});
        }).then(balance => {
          assert.equal(0, balance.toNumber());
          return utils.assertEvent(groupBuy, eventName, filterFn);
        });
      });
    });

    describe("#leaveTokenGroup", () => {
      it("should remove contribution record", () => {
        let tokenId = 0;
        let contribution = 300;

        return groupBuy.contributeToTokenGroup(tokenId, {
          from: account_three,
          value: contribution
        }).then(tx => {
          expect(tx.receipt.status).to.equal('0x01', 'transaction should succeed');
          return groupBuy.contributeToTokenGroup(tokenId, {
            from: account_two,
            value: contribution
          });
        }).then(tx => {
          expect(tx.receipt.status).to.equal('0x01', 'transaction should succeed');
          return groupBuy.leaveTokenGroup(tokenId, {from: account_three});
        }).then(() => {
          return groupBuy.getWithdrawableBalance({from: account_three});
        }).then(balance => {
          assert.equal(contribution, balance);
          return groupBuy.getGroupsContributedTo({from: account_three});
        }).then(arr => {
          assert.equal(arr[0].toNumber(), 1);
          assert.equal(arr.length, 1);
          return groupBuy.getContributionBalanceForTokenGroup(tokenId, {from: account_three});
        }).then(balance => {
          assert.equal(balance.toNumber(), 0);
          return groupBuy.getContributionBalanceForTokenGroup(tokenId, {from: account_two});
        }).then(balance => {
          assert.equal(balance.toNumber(), contribution);
          return groupBuy.getContributorsInTokenGroupCount(tokenId, {from: account_three});
        }).then(count => {
          assert.equal(count, 1);
          return groupBuy.getTokenGroupTotalBalance(tokenId, {from: account_three});
        }).then(balance => {
          assert.equal(balance.toNumber(), contribution);
        });
      });

      it("should block departure if not part of group", () => {
        let tokenId = 0;

        return groupBuy.leaveTokenGroup(tokenId, {
          from: account_three
        }).then(tx => {
          expect(tx.receipt.status).to.equal('0x00', 'transaction should fail');
        });
      });

      it("should block departure if token purchased", () => {
        let tokenId = 1;

        return groupBuy.leaveTokenGroup(tokenId, {
          from: account_three
        }).then(tx => {
          expect(tx.receipt.status).to.equal('0x00', 'transaction should fail');
        });
      });
    });

    describe("#redistributeSaleProceeds", () => {
      describe("Safety checks", () => {
        it("should block redistribution if group had not purchased yet", () => {
          return groupBuy.redistributeSaleProceeds(0, {
            from: account_one
          }).then(tx => {
            expect(tx.receipt.status).to.equal('0x00', 'transaction should fail');
          });
        });

        it("should block redistribution if token had not sold yet", () => {
          return groupBuy.redistributeSaleProceeds(1, {
            from: account_one
          }).then(tx => {
            expect(tx.receipt.status).to.equal('0x00', 'transaction should fail');
          });
        });
      });

      describe("After Sale", () => {
        before(() => {
          return celeb.purchase(1, {from: account_four, value: 100000});
        });

        it("should throw if anyone other than coo initiates redistribution", () => {
          return groupBuy.redistributeSaleProceeds(1, {from: account_two})
          .then(tx => {
            expect(tx.receipt.status).to.equal('0x00', 'transaction should fail');
          });
        });

        it("should redistribute funds correctly", () => {
          var eventName = "FundsRedistributed";
          var contrib = [100, 200, 1700];
          var wholeContribution = 2000;
          var distributableFunds = parseInt(4000*97/100);
          var sumFunds = 0;

          return groupBuy.redistributeSaleProceeds(1, {from: account_one}).then(tx => {
            expect(tx.receipt.status).to.equal('0x01', 'transaction should succeed');
            return utils.collectEvents(groupBuy, eventName);
          }).then(events => {
            _.each(events, e => {
              sumFunds += e.amount.toNumber();
            });
            expect((sumFunds - 5) < distributableFunds).to.be.true;
            expect((sumFunds + 5) > distributableFunds).to.be.true;
          });
        });
      });

      describe("Load testing", () => {
        before(async () => {
          for (var i = 0; i < 20; i++) {
            await groupBuy.contributeToTokenGroup(2, {
              from: accounts[i],
              value: 150
            })
          }
          return groupBuy.getTokenGroupTotalBalance(2, {
            from: account_one
          }).then(balance => {
            expect(balance.toNumber()).to.equal(3000);
          });
        });

        it("should redistribute funds correctly", () => {
          var eventName = "FundsRedistributed";
          var contrib = [100, 200, 1700];
          var wholeContribution = 2000;
          var distributableFunds = parseInt(4000*97/100);
          var sumFunds = 0;

          return groupBuy.redistributeSaleProceeds(2, {from: account_one}).then(tx => {
            expect(tx.receipt.status).to.equal('0x01', 'transaction should succeed');
            return utils.collectEvents(groupBuy, eventName);
          }).then(events => {
            _.each(events, e => {
              sumFunds += e.amount.toNumber();
            });
            console.log('sum', sumFunds);
            console.log(distributableFunds);
            expect((sumFunds - 5) < distributableFunds).to.be.true;
            expect((sumFunds + 5) > distributableFunds).to.be.true;
          });
        });
      });
    });
  });
});
