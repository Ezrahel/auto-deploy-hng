FROM node:18-alpine

# Set working directory
WORKDIR /app

# Create package.json
RUN echo '{ \
  "name": "deploy-demo-app", \
  "version": "1.0.0", \
  "description": "Demo app for deploy.sh script", \
  "main": "server.js", \
  "scripts": { \
    "start": "node server.js" \
  }, \
  "dependencies": { \
    "express": "^4.18.2" \
  } \
}' > package.json

# Create server.js
RUN echo "const express = require('express');\n\
const app = express();\n\
const PORT = process.env.PORT || 3000;\n\
\n\
app.get('/', (req, res) => {\n\
  res.json({\n\
    message: 'HNG DevOps Stage 1 - Deploy.sh Working!',\n\
    status: 'success',\n\
    timestamp: new Date().toISOString(),\n\
    deployed_by: 'deploy.sh automation script'\n\
  });\n\
});\n\
\n\
app.get('/health', (req, res) => {\n\
  res.json({ status: 'healthy', uptime: process.uptime() });\n\
});\n\
\n\
app.listen(PORT, '0.0.0.0', () => {\n\
  console.log(\`Server running on port \${PORT}\`);\n\
});" > server.js

# Install dependencies
RUN npm install --production

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "require('http').get('http://localhost:3000/health', (r) => {process.exit(r.statusCode === 200 ? 0 : 1)})"

# Start application
CMD ["npm", "start"]