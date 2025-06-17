const path = require('path');
const { Gateway, Wallets } = require('fabric-network');
const { buildCCPOrg1, buildCCPOrg2, buildWallet } = require('./AppUtil');

const myChannel = 'mychannel';
const myChaincodeName = 'asset-transfer-basic';

async function getContract(org, userId) {
    let ccp, walletPath;
    if (org === 'org1') {
        ccp = buildCCPOrg1();
        walletPath = '/fabric/application/wallet/org1';
    } else if (org === 'org2') {
        ccp = buildCCPOrg2();
        walletPath = '/fabric/application/wallet/org2';
    } else {
        throw new Error('Organization must be Org1 or Org2');
    }

    const wallet = await buildWallet(Wallets, walletPath);
    const gateway = new Gateway();
    try {
        await gateway.connect(ccp, { wallet, identity: userId, discovery: { enabled: true, asLocalhost: false } });
        const network = await gateway.getNetwork(myChannel);
        const contract = network.getContract(myChaincodeName);
        return { gateway, contract };
    } catch (error) {
        gateway.disconnect();
        throw error;
    }
}

module.exports = { getContract };
