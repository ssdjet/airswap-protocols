const utils = require('web3-utils')

let padAddressToLocator = address => {
  if (!utils.isAddress(address)) {
    throw new Error(`Address must be a valid Ethereum address: ${address}`)
  }
  return `${address.padEnd(66, '0')}`
}

module.exports = {
  padAddressToLocator,
}
