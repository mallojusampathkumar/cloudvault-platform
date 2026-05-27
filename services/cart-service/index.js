// cart-service/index.js
// Shopping cart microservice - Redis-backed for speed
const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const morgan = require('morgan');
const { createClient } = require('redis');

const app = express();
const PORT = process.env.PORT || 3003;
const REDIS_URL = process.env.REDIS_URL || 'redis://localhost:6379';

app.use(helmet());
app.use(cors());
app.use(express.json());
app.use(morgan('combined'));

// Initialize Redis client
const redisClient = createClient({ url: REDIS_URL });
redisClient.on('error', (err) => console.error('Redis error:', err));
redisClient.on('connect', () => console.log('✅ Connected to Redis'));

// Health check (no Redis dependency - basic liveness)
app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'healthy',
    service: 'cart-service',
    timestamp: new Date().toISOString()
  });
});

// Readiness check (verifies Redis connectivity)
app.get('/ready', async (req, res) => {
  try {
    await redisClient.ping();
    res.status(200).json({ ready: true });
  } catch (err) {
    res.status(503).json({ ready: false, error: 'redis unreachable' });
  }
});

// Get cart for user
app.get('/cart/:userId', async (req, res) => {
  try {
    const cart = await redisClient.get(`cart:${req.params.userId}`);
    res.json(cart ? JSON.parse(cart) : { userId: req.params.userId, items: [] });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Add item to cart
app.post('/cart/:userId/items', async (req, res) => {
  try {
    const { productId, quantity } = req.body;
    const key = `cart:${req.params.userId}`;
    const existing = await redisClient.get(key);
    const cart = existing ? JSON.parse(existing) : { userId: req.params.userId, items: [] };

    const existingItem = cart.items.find(i => i.productId === productId);
    if (existingItem) {
      existingItem.quantity += quantity;
    } else {
      cart.items.push({ productId, quantity });
    }

    // Set with 24h TTL (carts expire if abandoned)
    await redisClient.setEx(key, 86400, JSON.stringify(cart));
    res.status(201).json(cart);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Clear cart
app.delete('/cart/:userId', async (req, res) => {
  try {
    await redisClient.del(`cart:${req.params.userId}`);
    res.status(204).send();
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Startup: connect to Redis FIRST, then start HTTP server
async function start() {
  try {
    await redisClient.connect();
    const server = app.listen(PORT, () => {
      console.log(`✅ cart-service listening on port ${PORT}`);
    });

    // Graceful shutdown
    process.on('SIGTERM', async () => {
      console.log('SIGTERM received, shutting down...');
      server.close(async () => {
        await redisClient.quit();
        process.exit(0);
      });
    });
  } catch (err) {
    console.error('Startup failed:', err);
    process.exit(1);
  }
}

start();
