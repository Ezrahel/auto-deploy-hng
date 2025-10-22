const express = require('express');
const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(express.json());

// Root endpoint
app.get('/', (req, res) => {
  res.json({
    message: '🚀 HNG DevOps Stage 1 - Deployment Successful!',
    status: 'running',
    timestamp: new Date().toISOString(),
    environment: process.env.NODE_ENV || 'production',
    version: '1.0.0',
    author: 'HNG DevOps Intern'
  });
});

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ 
    status: 'healthy',
    uptime: process.uptime(),
    memory: process.memoryUsage(),
    timestamp: new Date().toISOString()
  });
});

// Info endpoint
app.get('/info', (req, res) => {
  res.json({
    node_version: process.version,
    platform: process.platform,
    architecture: process.arch,
    pid: process.pid,
    cwd: process.cwd()
  });
});

// Test endpoint
app.get('/test', (req, res) => {
  res.json({
    message: 'Test endpoint working!',
    headers: req.headers,
    method: req.method,
    url: req.url
  });
});

// Start server
app.listen(PORT, '0.0.0.0', () => {
  console.log('========================================');
  console.log('✓ HNG DevOps Demo App Started');
  console.log(`✓ Server running on port ${PORT}`);
  console.log(`✓ Environment: ${process.env.NODE_ENV || 'production'}`);
  console.log('========================================');
  console.log('Available endpoints:');
  console.log('  GET / - Welcome message');
  console.log('  GET /health - Health check');
  console.log('  GET /info - System information');
  console.log('  GET /test - Test endpoint');
  console.log('========================================');
});