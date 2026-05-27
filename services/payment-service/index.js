// payment-service/index.js - Mock payment processor
const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const morgan = require('morgan');

const app = express();
const PORT = process.env.PORT || 3005;

app.use(helmet());
app.use(cors());
app.use(express.json());
app.use(morgan('combined'));

const payments = new Map();

app.get('/health', (req, res) => res.json({ status: 'healthy', service: 'payment-service' }));
app.get('/ready', (req, res) => res.json({ ready: true }));

app.post('/payments', (req, res) => {
  const { orderId, amount, method } = req.body;
  const success = Math.random() > 0.05;
  const paymentId = `pay_${Date.now()}`;
  const result = {
    id: paymentId,
    orderId,
    amount,
    method,
    status: success ? 'succeeded' : 'failed',
    timestamp: new Date().toISOString()
  };
  payments.set(paymentId, result);
  res.status(success ? 201 : 402).json(result);
});

app.get('/payments/:id', (req, res) => {
  const payment = payments.get(req.params.id);
  if (!payment) return res.status(404).json({ error: 'not found' });
  res.json(payment);
});

const server = app.listen(PORT, () => console.log(`✅ payment-service on ${PORT}`));
process.on('SIGTERM', () => server.close(() => process.exit(0)));
