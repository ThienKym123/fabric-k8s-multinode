const express = require('express');
const router = express.Router();
const fabricController = require('./fabricController');
const controller = require('./assetController');

// Admin and user management
router.post('/enrollAdmin', fabricController.enrollAdmin);
router.post('/registerUser', fabricController.registerUser);

// Asset management
router.post('/init', controller.initLedger);
router.post('/createAsset', controller.createAsset);
router.get('/asset/:id', controller.readAsset);
router.put('/updateAsset', controller.updateAsset);
router.delete('/asset/:id', controller.deleteAsset);
router.post('/transferAsset', controller.transferAsset);
router.get('/asset/exists/:id', controller.assetExists);
router.get('/getAllAssets', controller.getAllAssets);

module.exports = router;
