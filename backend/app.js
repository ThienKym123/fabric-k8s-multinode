const express = require('express');
const cors = require('cors');
const assetRoutes = require('./scripts/assetRoutes');

const app = express();

// Log để debug mọi yêu cầu
app.use((req, res, next) => {
  console.log(`Nhận yêu cầu: ${req.method} ${req.url}`);
  console.log(`Headers: ${JSON.stringify(req.headers)}`);
  console.log(`Raw body: ${req.body}`);
  next();
});

// Middleware phân tích JSON
app.use(express.json());

// Log body sau khi phân tích
app.use((req, res, next) => {
  console.log(`Parsed body: ${JSON.stringify(req.body)}`);
  if (req.method === 'POST' && !req.body) {
    return res.status(400).json({ error: 'Body JSON không hợp lệ hoặc thiếu' });
  }
  next();
});

app.use(cors());

// Routes
app.use('/api', assetRoutes);

// Xử lý lỗi chung
app.use((err, req, res, next) => {
  console.error(`Lỗi server: ${err.stack}`);
  res.status(500).json({ error: 'Lỗi server nội bộ' });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Server running on port ${PORT}`));