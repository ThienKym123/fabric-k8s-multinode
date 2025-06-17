const { getContract } = require('./gateway');

// Init ledger
exports.initLedger = async (req, res) => {
  const { org, userId } = req.body;
  if (!org || !userId) {
    return res.status(400).json({ error: 'Thiếu org hoặc userId' });
  }
  let gateway;
  try {
    const { gateway: gw, contract } = await getContract(org, userId);
    gateway = gw;
    console.log(`Submitting InitLedger for ${org}/${userId}`);
    await contract.submitTransaction('InitLedger');
    res.json({ message: 'Ledger initialized successfully' });
  } catch (error) {
    console.error(`Lỗi InitLedger: ${error.message}`);
    res.status(500).json({ error: error.message });
  } finally {
    if (gateway) gateway.disconnect();
  }
};

// Create asset
exports.createAsset = async (req, res) => {
  const { org, userId, id, color, size, owner, appraisedValue } = req.body;
  if (!org || !userId || !id || !color || size === undefined || !owner || appraisedValue === undefined) {
    return res.status(400).json({ error: 'Thiếu tham số: org, userId, id, color, size, owner, appraisedValue' });
  }
  let gateway;
  try {
    const { gateway: gw, contract } = await getContract(org, userId);
    gateway = gw;
    console.log(`Submitting CreateAsset ${id} for ${org}/${userId}`);
    await contract.submitTransaction('CreateAsset', id, color, size.toString(), owner, appraisedValue.toString());
    res.json({ message: 'Asset created successfully', id: id });
  } catch (error) {
    console.error(`Lỗi CreateAsset: ${error.message}`);
    res.status(500).json({ error: error.message });
  } finally {
    if (gateway) gateway.disconnect();
  }
};

// Read asset
exports.readAsset = async (req, res) => {
  const { org, userId } = req.query;
  const { id } = req.params;
  if (!org || !userId || !id) {
    return res.status(400).json({ error: 'Thiếu org, userId hoặc id' });
  }
  let gateway;
  try {
    const { gateway: gw, contract } = await getContract(org, userId);
    gateway = gw;
    console.log(`Evaluating ReadAsset ${id} for ${org}/${userId}`);
    const result = await contract.evaluateTransaction('ReadAsset', id);
    const asset = JSON.parse(result.toString());
    res.json({ 
      message: 'Asset read successfully',
      asset: asset
    });
  } catch (error) {
    console.error(`Lỗi ReadAsset: ${error.message}`);
    res.status(500).json({ error: error.message });
  } finally {
    if (gateway) gateway.disconnect();
  }
};

// Update asset
exports.updateAsset = async (req, res) => {
  const { org, userId, id, color, size, owner, appraisedValue } = req.body;
  if (!org || !userId || !id || !color || size === undefined || !owner || appraisedValue === undefined) {
    return res.status(400).json({ error: 'Thiếu tham số: org, userId, id, color, size, owner, appraisedValue' });
  }
  let gateway;
  try {
    const { gateway: gw, contract } = await getContract(org, userId);
    gateway = gw;
    console.log(`Submitting UpdateAsset ${id} for ${org}/${userId}`);
    await contract.submitTransaction('UpdateAsset', id, color, size.toString(), owner, appraisedValue.toString());
    res.json({ message: 'Asset updated successfully', id: id });
  } catch (error) {
    console.error(`Lỗi UpdateAsset: ${error.message}`);
    res.status(500).json({ error: error.message });
  } finally {
    if (gateway) gateway.disconnect();
  }
};

// Delete asset
exports.deleteAsset = async (req, res) => {
  const { org, userId } = req.query;
  const { id } = req.params;
  if (!org || !userId || !id) {
    return res.status(400).json({ error: 'Thiếu org, userId hoặc id' });
  }
  let gateway;
  try {
    const { gateway: gw, contract } = await getContract(org, userId);
    gateway = gw;
    console.log(`Submitting DeleteAsset ${id} for ${org}/${userId}`);
    await contract.submitTransaction('DeleteAsset', id);
    res.json({ message: 'Asset deleted successfully', id: id });
  } catch (error) {
    console.error(`Lỗi DeleteAsset: ${error.message}`);
    res.status(500).json({ error: error.message });
  } finally {
    if (gateway) gateway.disconnect();
  }
};

// Transfer asset
exports.transferAsset = async (req, res) => {
  const { org, userId, id, newOwner } = req.body;
  if (!org || !userId || !id || !newOwner) {
    return res.status(400).json({ error: 'Thiếu tham số: org, userId, id, newOwner' });
  }
  let gateway;
  try {
    const { gateway: gw, contract } = await getContract(org, userId);
    gateway = gw;
    console.log(`Submitting TransferAsset ${id} for ${org}/${userId}`);
    const result = await contract.submitTransaction('TransferAsset', id, newOwner);
    const oldOwner = result.toString();
    res.json({ 
      message: 'Asset transferred successfully', 
      id: id,
      oldOwner: oldOwner,
      newOwner: newOwner
    });
  } catch (error) {
    console.error(`Lỗi TransferAsset: ${error.message}`);
    res.status(500).json({ error: error.message });
  } finally {
    if (gateway) gateway.disconnect();
  }
};

// Check if asset exists
exports.assetExists = async (req, res) => {
  const { org, userId } = req.query;
  const { id } = req.params;
  if (!org || !userId || !id) {
    return res.status(400).json({ error: 'Thiếu org, userId hoặc id' });
  }
  let gateway;
  try {
    const { gateway: gw, contract } = await getContract(org, userId);
    gateway = gw;
    console.log(`Evaluating AssetExists ${id} for ${org}/${userId}`);
    const result = await contract.evaluateTransaction('AssetExists', id);
    const exists = result.toString() === 'true';
    res.json({ 
      message: exists ? 'Asset exists' : 'Asset does not exist',
      id: id,
      exists: exists
    });
  } catch (error) {
    console.error(`Lỗi AssetExists: ${error.message}`);
    res.status(500).json({ error: error.message });
  } finally {
    if (gateway) gateway.disconnect();
  }
};

// Get all assets
exports.getAllAssets = async (req, res) => {
  const { org, userId } = req.query;
  if (!org || !userId) {
    return res.status(400).json({ error: 'Thiếu org hoặc userId' });
  }
  let gateway;
  try {
    const { gateway: gw, contract } = await getContract(org, userId);
    gateway = gw;
    console.log(`Evaluating GetAllAssets for ${org}/${userId}`);
    const result = await contract.evaluateTransaction('GetAllAssets');
    const assets = JSON.parse(result.toString());
    res.json({ 
      message: 'All assets retrieved successfully',
      count: assets.length,
      assets: assets
    });
  } catch (error) {
    console.error(`Lỗi GetAllAssets: ${error.message}`);
    res.status(500).json({ error: error.message });
  } finally {
    if (gateway) gateway.disconnect();
  }
};