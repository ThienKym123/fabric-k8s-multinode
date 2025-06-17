'use strict';

const { Wallets } = require('fabric-network');
const FabricCAServices = require('fabric-ca-client');
const fs = require('fs').promises;
const { buildCAClient, registerAndEnrollUser } = require('./CAUtil.js');
const { buildCCPOrg1, buildCCPOrg2, buildWallet } = require('./AppUtil.js');

const mspOrg1 = 'Org1MSP';
const mspOrg2 = 'Org2MSP';

async function connectToOrg1CA(userId) {
    console.log('\n--> Register and enrolling new user');
    const ccpOrg1 = buildCCPOrg1();
    const caOrg1Client = buildCAClient(FabricCAServices, ccpOrg1, 'org1-ca');

    const walletPathOrg1 = '/fabric/application/wallet/org1';
    await fs.mkdir(walletPathOrg1, { recursive: true });
    const walletOrg1 = await buildWallet(Wallets, walletPathOrg1);

    try {
        await registerAndEnrollUser(caOrg1Client, walletOrg1, mspOrg1, userId, 'org1.department1');
        console.log(`User ${userId} enrolled successfully for Org1`);
        const identities = await walletOrg1.list();
        console.log('Wallet identities:', identities);
    } catch (error) {
        console.error(`Failed to enroll user ${userId} for Org1:`, error);
        throw error;
    }
}

async function connectToOrg2CA(userId) {
    console.log('\n--> Register and enrolling new user');
    const ccpOrg2 = buildCCPOrg2();
    const caOrg2Client = buildCAClient(FabricCAServices, ccpOrg2, 'org2-ca');

    const walletPathOrg2 = '/fabric/application/wallet/org2';
    await fs.mkdir(walletPathOrg2, { recursive: true });
    const walletOrg2 = await buildWallet(Wallets, walletPathOrg2);

    try {
        await registerAndEnrollUser(caOrg2Client, walletOrg2, mspOrg2, userId, 'org2.department1');
        console.log(`User ${userId} enrolled successfully for Org2`);
        const identities = await walletOrg2.list();
        console.log('Wallet identities:', identities);
    } catch (error) {
        console.error(`Failed to enroll user ${userId} for Org2:`, error);
        throw error;
    }
}

async function main() {
    if (process.argv[2] === undefined || process.argv[3] === undefined) {
        console.log('Usage: node registerEnrollUser.js org userID');
        process.exit(1);
    }

    const org = process.argv[2];
    const userId = process.argv[3];

    try {
        if (org === 'Org1' || org === 'org1') {
            await connectToOrg1CA(userId);
        } else if (org === 'Org2' || org === 'org2') {
            await connectToOrg2CA(userId);
        } else {
            console.log('Org must be Org1 or Org2');
        }
    } catch (error) {
        console.error(`Error in enrolling user: ${error}`);
        process.exit(1);
    }
}

if (require.main === module) {
    main();
}

module.exports = { connectToOrg1CA, connectToOrg2CA };