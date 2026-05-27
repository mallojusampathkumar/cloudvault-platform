// user-service/index.js
// A minimal authentication microservice - production-grade scaffolding
const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const morgan = require('morgan');
const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');

const app = express();
const PORT = process.env.PORT || 3001;
const JWT_SECRET = process.env.JWT_SECRET || 'dev-secret-change-in-prod';

// Middleware
app.use(helmet());                    // Sets security HTTP headers
app.use(cors());                      // Cross-origin support
app.use(express.json());              // Parse JSON bodies
app.use(morgan('combined'));          // HTTP request logging

// In-memory user store (we'll swap for PostgreSQL on Day 3)
const users = new Map();

// Health check - K8s and ALB use this
app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'healthy',
    service: 'user-service',
    timestamp: new Date().toISOString(),
    uptime: process.uptime()
  });
});

// Readiness check - K8s uses this to know "ready to receive traffic"
app.get('/ready', (req, res) => {
  // In real apps: check DB connection, cache, etc.
  res.status(200).json({ ready: true });
});

// Metrics endpoint - Prometheus will scrape this on Day 6
app.get('/metrics', (req, res) => {
  res.set('Content-Type', 'text/plain');
  res.send(`# HELP user_service_users_total Total registered users\n# TYPE user_service_users_total gauge\nuser_service_users_total ${users.size}\n`);
});

// Register
app.post('/register', async (req, res) => {
  try {
    const { email, password, name } = req.body;
    if (!email || !password) {
      return res.status(400).json({ error: 'Email and password required' });
    }
    if (users.has(email)) {
      return res.status(409).json({ error: 'User already exists' });
    }
    const hash = await bcrypt.hash(password, 10);
    users.set(email, { email, name, password: hash, createdAt: new Date() });
    res.status(201).json({ message: 'User created', email });
  } catch (err) {
    console.error('Register error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Login
app.post('/login', async (req, res) => {
  try {
    const { email, password } = req.body;
    const user = users.get(email);
    if (!user) return res.status(401).json({ error: 'Invalid credentials' });
    const valid = await bcrypt.compare(password, user.password);
    if (!valid) return res.status(401).json({ error: 'Invalid credentials' });
    const token = jwt.sign({ email: user.email, name: user.name }, JWT_SECRET, { expiresIn: '1h' });
    res.json({ token, user: { email: user.email, name: user.name } });
  } catch (err) {
    console.error('Login error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Graceful shutdown - critical for K8s rolling deployments
const server = app.listen(PORT, () => {
  console.log(`✅ user-service listening on port ${PORT}`);
});

process.on('SIGTERM', () => {
  console.log('SIGTERM received, shutting down gracefully...');
  server.close(() => {
    console.log('HTTP server closed.');
    process.exit(0);
  });
});
