require('babel-register');
require('babel-polyfill');

module.exports = {
  networks: {
    development: {
      host: "127.0.0.1",
      port: 9545,
      network_id: "*" // Match any network id
    },
    live: {
      host: "127.0.0.1",
      port: 8546,
      network_id: "1"
    }
  },
  rpc: {
    host: "127.0.0.1",
    port: 8545
  }
};
