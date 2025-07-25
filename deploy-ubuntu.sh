#!/bin/bash

# Multi-Ollama Web Interface Deployment Script - Ubuntu/Debian Version
# Features: Multi-host support, conversation rounds, file uploads, web search, host history
# Version: v13-ubuntu

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
INSTALL_DIR="$HOME/multi-ollama-server"
SERVICE_NAME="multi-ollama"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
HOSTS_CONFIG_PATH="$INSTALL_DIR/hosts.json"
HOSTS_HISTORY_PATH="$INSTALL_DIR/hosts_history.json"
SETTINGS_CONFIG_PATH="$INSTALL_DIR/settings.yaml"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[*]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        print_error "This script should not be run as root. Please run as a regular user."
        exit 1
    fi
}

# Update system packages
update_system() {
    print_status "Updating system packages..."
    sudo apt update
    print_success "System packages updated"
}

# Install Node.js and npm
install_nodejs() {
    print_status "Installing Node.js and npm..."
    
    # Check if Node.js is already installed
    if command -v node &> /dev/null; then
        NODE_VERSION=$(node --version)
        print_warning "Node.js $NODE_VERSION is already installed"
    else
        # Install Node.js from NodeSource repository
        curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
        sudo apt install -y nodejs
        print_success "Node.js installed"
    fi
    
    # Verify installation
    node --version
    npm --version
}

# Install system dependencies
install_dependencies() {
    print_status "Installing system dependencies..."
    sudo apt install -y curl wget sqlite3 git build-essential
    print_success "System dependencies installed"
}

# Install Ollama
install_ollama() {
    print_status "Installing Ollama..."
    
    if command -v ollama &> /dev/null; then
        print_warning "Ollama is already installed"
    else
        curl -fsSL https://ollama.ai/install.sh | sh
        print_success "Ollama installed"
    fi
    
    # Start Ollama service
    print_status "Starting Ollama service..."
    sudo systemctl enable ollama
    sudo systemctl start ollama
    
    # Wait for Ollama to be ready
    sleep 3
    
    print_success "Ollama service started"
}

# Create installation directory
create_install_dir() {
    print_status "Creating installation directory..."
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    print_success "Installation directory created at $INSTALL_DIR"
}

# Initialize hosts.json
print_status "Initializing hosts.json..."
echo '["http://localhost:11434"]' > "$HOSTS_CONFIG_PATH"
print_success "hosts.json created"

# Initialize hosts_history.json
print_status "Initializing hosts_history.json..."
echo '[]' > "$HOSTS_HISTORY_PATH"
print_success "hosts_history.json created"

# Initialize settings.yaml
print_status "Initializing settings.yaml..."
echo 'seed_prompt: ""' > "$SETTINGS_CONFIG_PATH"
print_success "settings.yaml created"

# Create package.json
create_package_json() {
    print_status "Creating package.json..."
    
    cat > package.json << 'EOL'
{
  "name": "multi-ollama-web-interface",
  "version": "1.0.0",
  "description": "Multi-Ollama Web Interface with conversation rounds and file uploads",
  "main": "server.js",
  "scripts": {
    "start": "node server.js",
    "dev": "node server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "axios": "^1.6.0",
    "multer": "^1.4.5-lts.1",
    "sqlite3": "^5.1.6",
    "js-yaml": "^4.1.0",
    "marked": "^9.1.2"
  },
  "keywords": ["ollama", "ai", "chat", "web-interface"],
  "author": "Multi-Ollama Team",
  "license": "MIT"
}
EOL
    
    print_success "package.json created"
}

# Create server.js (same content as test.sh but extracted)
create_server_js() {
    print_status "Creating server.js..."
    
    cat > server.js << 'EOL'
const express = require('express');
const multer = require('multer');
const axios = require('axios');
const sqlite3 = require('sqlite3').verbose();
const fs = require('fs').promises;
const path = require('path');
const yaml = require('js-yaml');

const app = express();
const PORT = process.env.PORT || 3000;
const DB_PATH = path.join(__dirname, 'chat_history.db');
const HOSTS_CONFIG_PATH = path.join(__dirname, 'hosts.json');
const HOSTS_HISTORY_PATH = path.join(__dirname, 'hosts_history.json');
const SETTINGS_CONFIG_PATH = path.join(__dirname, 'settings.yaml');
const UPLOADS_DIR = path.join(__dirname, 'uploads');

const storage = multer.diskStorage({
    destination: async (req, file, cb) => {
        try {
            await fs.mkdir(UPLOADS_DIR, { recursive: true });
            cb(null, UPLOADS_DIR);
        } catch (error) {
            cb(error);
        }
    },
    filename: (req, file, cb) => {
        const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
        cb(null, file.fieldname + '-' + uniqueSuffix + path.extname(file.originalname));
    }
});

const upload = multer({ 
    storage: storage,
    limits: { fileSize: 50 * 1024 * 1024 },
    fileFilter: (req, file, cb) => {
        const allowedTypes = /jpeg|jpg|png|gif|bmp|webp|txt|md|json|xml|csv|pdf|doc|docx|py|js|html|css|cpp|c|java|go|rs|sh|yml|yaml/;
        const extname = allowedTypes.test(path.extname(file.originalname).toLowerCase());
        const mimetype = allowedTypes.test(file.mimetype) || file.mimetype.startsWith('text/') || 
                        file.mimetype.startsWith('image/') || file.mimetype.startsWith('application/');
        
        if (mimetype && extname) {
            return cb(null, true);
        } else {
            cb(new Error('Unsupported file type'));
        }
    }
});

app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ extended: true, limit: '50mb' }));
app.use(express.static('public'));

const hosts = new Map();
let models = [];
let settings = { seed_prompt: '' };

// Database initialization
const db = new sqlite3.Database(DB_PATH);
db.serialize(() => {
    db.run(`CREATE TABLE IF NOT EXISTS chats (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        model TEXT,
        host TEXT,
        timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
        file_name TEXT,
        file_data TEXT
    )`);
});

async function loadSettings() {
    try {
        if (await fs.access(SETTINGS_CONFIG_PATH).then(() => true).catch(() => false)) {
            const data = await fs.readFile(SETTINGS_CONFIG_PATH, 'utf-8');
            settings = yaml.load(data) || { seed_prompt: '' };
        }
    } catch (error) {
        console.error('Error loading settings:', error);
        settings = { seed_prompt: '' };
    }
}

async function saveSettings() {
    await fs.writeFile(SETTINGS_CONFIG_PATH, yaml.dump(settings));
}

async function saveHostsToFile() {
    await fs.writeFile(HOSTS_CONFIG_PATH, JSON.stringify(Array.from(hosts.keys()), null, 2));
}

async function saveHostToHistory(url, hostInfo) {
    try {
        let history = [];
        try {
            const data = await fs.readFile(HOSTS_HISTORY_PATH, 'utf-8');
            history = JSON.parse(data);
        } catch (e) {
            // File doesn't exist yet, start with empty array
        }
        
        // Remove existing entry if it exists
        history = history.filter(h => h.url !== url);
        
        // Add new entry with timestamp and connection info
        history.unshift({
            url,
            lastConnected: new Date().toISOString(),
            status: hostInfo.status,
            modelCount: hostInfo.models ? hostInfo.models.length : 0,
            nickname: extractHostNickname(url)
        });
        
        // Keep only last 20 entries
        history = history.slice(0, 20);
        
        await fs.writeFile(HOSTS_HISTORY_PATH, JSON.stringify(history, null, 2));
    } catch (error) {
        console.error('Error saving host to history:', error);
    }
}

async function loadHostHistory() {
    try {
        const data = await fs.readFile(HOSTS_HISTORY_PATH, 'utf-8');
        return JSON.parse(data);
    } catch (error) {
        return []; // Return empty array if file doesn't exist
    }
}

function extractHostNickname(url) {
    try {
        const urlObj = new URL(url);
        const hostname = urlObj.hostname;
        if (hostname === 'localhost' || hostname === '127.0.0.1') {
            return 'Local';
        }
        // Extract last part of IP or hostname
        const parts = hostname.split('.');
        return parts[parts.length - 1] || hostname;
    } catch (e) {
        return url.replace(/^https?:\/\//, '').split(':')[0];
    }
}

async function checkAndAddHost(url) {
    try {
        const response = await axios.get(`${url}/api/tags`, { timeout: 5000 });
        const hostInfo = { url, status: 'online', models: response.data.models || [], lastChecked: new Date() };
        hosts.set(url, hostInfo);
        
        // Save to history when successfully connected
        await saveHostToHistory(url, hostInfo);
        
        return { success: true, host: hostInfo };
    } catch (error) {
        const hostInfo = { url, status: 'offline', error: error.message, lastChecked: new Date() };
        hosts.set(url, hostInfo);
        
        // Also save failed attempts to history (user might want to retry later)
        await saveHostToHistory(url, hostInfo);
        
        return { success: false, error: error.message, host: hostInfo };
    }
}

async function loadHostsFromFile() {
    try {
        if (await fs.access(HOSTS_CONFIG_PATH).then(() => true).catch(() => false)) {
            const data = await fs.readFile(HOSTS_CONFIG_PATH, 'utf-8');
            const hostUrls = JSON.parse(data);
            for (const url of hostUrls) await checkAndAddHost(url);
        } else {
            await checkAndAddHost('http://localhost:11434');
            await saveHostsToFile();
        }
    } catch (error) {
        console.error('Error loading hosts:', error);
    }
}

async function extractTextFromFile(filePath, mimeType, originalName) {
    try {
        if (mimeType.startsWith('image/')) {
            const imageBuffer = await fs.readFile(filePath);
            return {
                type: 'image',
                data: `data:${mimeType};base64,${imageBuffer.toString('base64')}`,
                filename: originalName
            };
        } else {
            const textContent = await fs.readFile(filePath, 'utf-8');
            return {
                type: 'text',
                data: textContent,
                filename: originalName
            };
        }
    } catch (error) {
        throw new Error(`Failed to process file: ${error.message}`);
    }
}

async function saveChatMessage(sessionId, role, content, model = null, host = null, fileName = null, fileData = null) {
    return new Promise((resolve, reject) => {
        const stmt = db.prepare(`INSERT INTO chats (session_id, role, content, model, host, file_name, file_data) VALUES (?, ?, ?, ?, ?, ?, ?)`);
        stmt.run([sessionId, role, content, model, host, fileName, fileData], function(err) {
            if (err) reject(err);
            else resolve(this.lastID);
        });
        stmt.finalize();
    });
}

async function searchWeb(query) {
    try {
        const searchUrl = `https://api.duckduckgo.com/?q=${encodeURIComponent(query)}&format=json&no_redirect=1&no_html=1&skip_disambig=1`;
        const response = await axios.get(searchUrl, { timeout: 10000 });
        
        if (response.data && response.data.AbstractText) {
            return {
                source: 'DuckDuckGo',
                content: response.data.AbstractText,
                url: response.data.AbstractURL
            };
        }
        
        return null;
    } catch (error) {
        console.error('Web search failed:', error);
        return null;
    }
}

async function generateSingleResponse(model, requestBody) {
    const { host, name } = model;
    let { prompt, fileData, webSearch } = requestBody;

    try {
        // Add web search if enabled
        if (webSearch && !fileData) {
            const searchResult = await searchWeb(prompt);
            if (searchResult) {
                prompt = `Context from web search: ${searchResult.content}\n\nUser question: ${prompt}`;
            }
        }

        // Add seed prompt if configured
        if (settings.seed_prompt) {
            prompt = `${settings.seed_prompt}\n\n${prompt}`;
        }

        // Prepare messages for chat endpoint
        const messages = [{ role: 'user', content: prompt }];

        // Add file content if present
        if (fileData) {
            if (fileData.type === 'image') {
                messages[0].images = [fileData.data.split(',')[1]]; // Remove data:image/...;base64, prefix
            } else {
                messages[0].content = `File: ${fileData.filename}\n\n${fileData.data}\n\nUser: ${prompt}`;
            }
        }

        const requestData = {
            model: name,
            messages: messages,
            stream: false
        };

        const response = await axios.post(`${host}/api/chat`, requestData, { timeout: 120000 });
        
        return {
            model: name,
            host: host,
            response: response.data.message?.content || 'No response received'
        };
    } catch (error) {
        // Fallback to older generate endpoint
        try {
            const fallbackData = {
                model: name,
                prompt: prompt,
                stream: false
            };

            const fallbackResponse = await axios.post(`${host}/api/generate`, fallbackData, { timeout: 120000 });
            
            return {
                model: name,
                host: host,
                response: fallbackResponse.data.response || 'No response received'
            };
        } catch (fallbackError) {
            return {
                model: name,
                host: host,
                error: `Failed to generate response: ${error.message}`
            };
        }
    }
}

async function generateConsensus(responses, prompt) {
    if (responses.length < 2) return null;
    
    const synthesizer = responses[0];
    const synthesisPrompt = `Synthesize consensus for "${prompt}":\n${responses.map(r => `${r.model}: ${r.response}`).join('\n')}\nConsensus:`;
    
    try {
        const requestData = {
            model: synthesizer.model,
            messages: [{ role: 'user', content: synthesisPrompt }],
            stream: false
        };

        const response = await axios.post(`${synthesizer.host}/api/chat`, requestData, { timeout: 60000 });
        const data = response.data;
        
        return { model: `Consensus (via ${synthesizer.model.split(':')[0]})`, host: 'System', response: data.message?.content || '', consensus: true };
    } catch (error) {
        return { model: 'Consensus', host: 'System', error: 'Consensus failed' };
    }
}

async function runConversationRoundsStreaming(models, initialPrompt, rounds, mode, requestBody, sessionId, res) {
    const conversationHistory = [];
    let currentContext = initialPrompt;
    
    const modeInstructions = {
        collaborative: "Build upon the previous responses and contribute constructively to the discussion.",
        debate: "Present a different perspective or challenge the previous arguments respectfully.",
        socratic: "Ask probing questions or provide deeper analysis of the previous responses.",
        panel: "Contribute your unique perspective to this panel discussion."
    };
    
    for (let round = 1; round <= rounds; round++) {
        console.log(`Starting conversation round ${round}/${rounds}`);
        res.write(`data: ${JSON.stringify({type: 'status', message: `Round ${round}/${rounds}`})}\n\n`);
        
        for (const model of models) {
            const contextPrompt = round === 1 ? 
                `${modeInstructions[mode]} Initial topic: ${initialPrompt}` :
                `${modeInstructions[mode]} 

Previous conversation:
${conversationHistory.slice(-6).map(h => `${h.model}: ${h.response}`).join('\n\n')}

Continue the discussion:`;

            const roundRequestBody = {
                ...requestBody,
                prompt: contextPrompt
            };
            
            try {
                const response = await generateSingleResponse(model, roundRequestBody);
                if (!response.error) {
                    const entry = {
                        round,
                        model: model.name,
                        host: model.host,
                        response: response.response
                    };
                    conversationHistory.push(entry);
                    
                    // Stream this response immediately to the UI
                    res.write(`data: ${JSON.stringify({type: 'response', model: entry.model, host: entry.host, response: entry.response, round: entry.round})}\n\n`);
                    
                    // Save to database immediately
                    await saveChatMessage(sessionId, 'assistant', entry.response, entry.model, entry.host);
                }
            } catch (error) {
                console.error(`Error in round ${round} for ${model.name}:`, error);
                // Stream error response
                res.write(`data: ${JSON.stringify({type: 'response', model: model.name, host: model.host, error: error.message, round: round})}\n\n`);
            }
        }
    }
    
    return conversationHistory;
}

// API Endpoints
app.post('/api/hosts', async (req, res) => {
    const { url } = req.body;
    const result = await checkAndAddHost(url);
    await saveHostsToFile();
    res.json(result);
});

app.get('/api/hosts', (req, res) => res.json(Array.from(hosts.values())));

app.get('/api/hosts/history', async (req, res) => {
    try {
        const history = await loadHostHistory();
        res.json(history);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

app.delete('/api/hosts/:url', async (req, res) => {
    hosts.delete(decodeURIComponent(req.params.url));
    await saveHostsToFile();
    res.json({ success: true });
});

app.get('/api/models', async (req, res) => {
    const models = [];
    for (const [url, host] of hosts) {
        if (host.status === 'online') {
            host.models.forEach(model => {
                models.push({
                    name: model.name,
                    host: url,
                    size: model.size,
                    modified: model.modified_at
                });
            });
        }
    }
    res.json(models);
});

app.post('/api/generate-multi', upload.single('file'), async (req, res) => {
    const { models: selectedModels, prompt, sessionId, webSearch, enableConsensus = true, conversationRounds, conversationMode } = req.body;
    const models = JSON.parse(selectedModels);
    
    let fileData = null;
    if (req.file) {
        try {
            fileData = await extractTextFromFile(req.file.path, req.file.mimetype, req.file.originalname);
            await fs.unlink(req.file.path);
        } catch (error) {
            return res.status(400).json({ error: error.message });
        }
    } else if (req.body.fileData) {
        fileData = req.body.fileData;
    }

    await saveChatMessage(sessionId, 'user', prompt, null, null, fileData?.filename, JSON.stringify(fileData));
    
    let conversationHistory = [];
    let results = [];

    if (conversationRounds > 0) {
        // Run multi-round conversation with real-time streaming
        console.log(`Running ${conversationRounds} rounds of ${conversationMode} conversation`);
        
        // Set up Server-Sent Events for real-time streaming
        res.writeHead(200, {
            'Content-Type': 'text/event-stream',
            'Cache-Control': 'no-cache',
            'Connection': 'keep-alive',
            'Access-Control-Allow-Origin': '*'
        });
        
        // Send initial status
        res.write(`data: ${JSON.stringify({type: 'status', message: `Starting ${conversationRounds} rounds of ${conversationMode} conversation`})}\n\n`);
        
        conversationHistory = await runConversationRoundsStreaming(models, prompt, conversationRounds, conversationMode, req.body, sessionId, res);
        
        // Generate final responses after conversation
        res.write(`data: ${JSON.stringify({type: 'status', message: 'Generating final responses...'})}\n\n`);
        
        const finalPrompt = `Based on the previous conversation, provide your final thoughts on: ${prompt}

Conversation summary:
${conversationHistory.slice(-4).map(h => `${h.model}: ${h.response.substring(0, 200)}...`).join('\n')}`;
        
        const finalRequestBody = { ...req.body, prompt: finalPrompt };
        const finalResponses = await Promise.allSettled(models.map(m => generateSingleResponse(m, finalRequestBody)));
        results = finalResponses.map((r, i) => (r.status === 'fulfilled' ? r.value : { model: models[i].name, host: models[i].host, error: r.reason.message }));
        
        // Send final responses
        for (const result of results) {
            if (!result.error) {
                res.write(`data: ${JSON.stringify({type: 'response', ...result})}\n\n`);
                await saveChatMessage(sessionId, 'assistant', result.response, result.model, result.host);
            }
        }
        
        // Generate consensus if multiple models responded successfully
        if (results.length >= 2) {
            const successful = results.filter(r => !r.error);
            if (successful.length >= 2) {
                const consensusPrompt = `Create a consensus summary of the entire conversation and final thoughts on: ${prompt}`;
                const consensus = await generateConsensus(successful, consensusPrompt);
                res.write(`data: ${JSON.stringify({type: 'response', ...consensus})}\n\n`);
                await saveChatMessage(sessionId, 'assistant', consensus.response, consensus.model, consensus.host);
                results.push(consensus);
            }
        }
        
        res.write(`data: ${JSON.stringify({type: 'complete'})}\n\n`);
        res.end();
        return;
    } else {
        // Standard direct response
        const initialResponses = await Promise.allSettled(models.map(m => generateSingleResponse(m, req.body)));
        results = initialResponses.map((r, i) => (r.status === 'fulfilled' ? r.value : { model: models[i].name, host: models[i].host, error: r.reason.message }));
    }

    // Generate consensus if multiple models responded successfully
    if (enableConsensus && results.length >= 2) {
        const successful = results.filter(r => !r.error);
        if (successful.length >= 2) {
            const consensusPrompt = conversationRounds > 0 ? 
                `Create a consensus summary of the entire conversation and final thoughts on: ${prompt}` : 
                prompt;
            const consensus = await generateConsensus(successful, consensusPrompt);
            results.push(consensus);
            await saveChatMessage(sessionId, 'assistant', consensus.response, consensus.model, consensus.host);
        }
    }

    // Save final results to database
    results.forEach(r => r.error || saveChatMessage(sessionId, 'assistant', r.response, r.model, r.host));
    
    res.json({ 
        responses: results,
        conversationHistory: conversationHistory.length > 0 ? conversationHistory : null
    });
});

app.get('/api/download-chat/:sessionId/:format', (req, res) => {
    const { sessionId, format } = req.params;
    db.all(`SELECT * FROM chats WHERE session_id = ? ORDER BY timestamp`, [sessionId], (err, rows) => {
        if (err) return res.status(500).json({ error: err.message });
        
        const timestamp = new Date().toISOString().split('T')[0];
        const filename = `chat-${sessionId}-${timestamp}`;
        
        if (format === 'json') {
            res.setHeader('Content-Disposition', `attachment; filename="${filename}.json"`);
            res.setHeader('Content-Type', 'application/json');
            res.json(rows);
        } else if (format === 'txt') {
            res.setHeader('Content-Disposition', `attachment; filename="${filename}.txt"`);
            res.setHeader('Content-Type', 'text/plain');
            const txtContent = rows.map(row => 
                `[${row.timestamp}] ${row.role}${row.model ? ` (${row.model})` : ''}: ${row.content}`
            ).join('\n\n');
            res.send(txtContent);
        }
    });
});

app.get('/api/chats/:sessionId', (req, res) => {
    db.all(`SELECT * FROM chats WHERE session_id = ? ORDER BY timestamp`, [req.params.sessionId], (err, rows) => {
        if (err) return res.status(500).json({ error: err.message });
        res.json(rows);
    });
});

app.get('/api/sessions', (req, res) => {
    db.all(`SELECT DISTINCT session_id, MIN(timestamp) as start_time, MAX(timestamp) as last_message 
            FROM chats GROUP BY session_id ORDER BY last_message DESC LIMIT 50`, (err, rows) => {
        if (err) return res.status(500).json({ error: err.message });
        res.json(rows);
    });
});

app.get('/api/settings/seed-prompt', (req, res) => {
    res.json({ prompt: settings.seed_prompt || '' });
});

app.post('/api/settings/seed-prompt', async (req, res) => {
    try {
        settings.seed_prompt = req.body.prompt || '';
        await saveSettings();
        res.json({ success: true });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Initialize and start server
async function startServer() {
    await loadSettings();
    await loadHostsFromFile();
    
    app.listen(PORT, '0.0.0.0', () => {
        console.log(`Multi-Ollama Web Interface running on http://localhost:${PORT}`);
        console.log(`Dashboard: http://localhost:${PORT}`);
    });
}

startServer().catch(console.error);
EOL
    
    print_success "server.js created"
}

# Create HTML frontend (same as test.sh)  
create_frontend() {
    print_status "Creating frontend..."
    
    mkdir -p public
    
    cat > public/index.html << 'EOL'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Multi-Ollama Web Interface</title>
    <script src="https://cdn.jsdelivr.net/npm/marked@9.1.2/marked.min.js"></script>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', sans-serif; background: #0a0a0a; color: #e0e0e0; height: 100vh; overflow: hidden; }
        .container { display: flex; height: 100vh; }
        .sidebar { width: 300px; background: #111; border-right: 1px solid #333; padding: 20px; overflow-y: auto; display: flex; flex-direction: column; scrollbar-width: thin; scrollbar-color: #333 #111; }
        .sidebar::-webkit-scrollbar { width: 8px; }
        .sidebar::-webkit-scrollbar-track { background: #111; }
        .sidebar::-webkit-scrollbar-thumb { background: #333; border-radius: 4px; }
        .sidebar::-webkit-scrollbar-thumb:hover { background: #555; }
        .sidebar h2 { color: #fff; margin-bottom: 20px; font-size: 18px; }
        .sidebar section { margin-bottom: 30px; }
        .host-input { display: flex; gap: 8px; margin-bottom: 10px; flex-wrap: wrap; }
        .host-input input { flex: 1; min-width: 120px; padding: 8px 12px; background: #1a1a1a; border: 1px solid #333; color: #e0e0e0; border-radius: 4px; }
        .host-input button { padding: 8px 12px; background: #2563eb; color: white; border: none; border-radius: 4px; cursor: pointer; transition: background 0.2s; flex-shrink: 0; }
        .host-input button:hover { background: #1d4ed8; }
        .host-input button#historyToggle { background: #6b7280; }
        .host-input button#historyToggle:hover { background: #4b5563; }
        .host-history { margin-bottom: 15px; background: #1a1a1a; border: 1px solid #333; border-radius: 6px; padding: 12px; }
        .host-history h3 { margin: 0 0 10px 0; color: #e0e0e0; font-size: 14px; }
        .host-history-item { padding: 8px; background: #0f0f0f; border-radius: 4px; margin-bottom: 6px; cursor: pointer; transition: background 0.2s; }
        .host-history-item:hover { background: #262626; }
        .host-history-item:last-child { margin-bottom: 0; }
        .host-history-url { color: #3b82f6; font-weight: 500; font-size: 13px; margin-bottom: 4px; }
        .host-history-meta { font-size: 11px; color: #9ca3af; display: flex; justify-content: space-between; }
        .host-list { margin-top: 10px; }
        .host-item { padding: 10px; background: #1a1a1a; border-radius: 4px; margin-bottom: 8px; display: flex; justify-content: space-between; align-items: center; }
        .host-item.offline { border-left: 3px solid #dc2626; }
        .host-item.online { border-left: 3px solid #10b981; }
        .host-status { display: inline-block; width: 8px; height: 8px; border-radius: 50%; margin-right: 8px; }
        .host-status.online { background: #10b981; }
        .host-status.offline { background: #dc2626; }
        .host-url { flex: 1; font-size: 14px; }
        .remove-host { background: none; border: none; color: #dc2626; cursor: pointer; padding: 4px 8px; border-radius: 4px; transition: background 0.2s; }
        .remove-host:hover { background: #2a1a1a; }
        .model-list { max-height: 300px; overflow-y: auto; }
        .model-item { padding: 12px; background: #1a1a1a; border-radius: 4px; margin-bottom: 8px; display: flex; align-items: center; cursor: pointer; transition: background 0.2s; }
        .model-item:hover { background: #262626; }
        .model-item.selected { background: #1e3a8a; }
        .model-item input[type="checkbox"] { margin-right: 12px; }
        .model-details { flex: 1; }
        .model-name { font-weight: 500; color: #fff; margin-bottom: 4px; }
        .model-meta { font-size: 12px; color: #9ca3af; }
        .seed-prompt-section textarea { width: 100%; height: 80px; padding: 12px; background: #1a1a1a; border: 1px solid #333; color: #e0e0e0; border-radius: 4px; resize: vertical; font-family: inherit; }
        .seed-prompt-section button { width: 100%; margin-top: 10px; padding: 10px; background: #059669; color: white; border: none; border-radius: 4px; cursor: pointer; transition: background 0.2s; }
        .seed-prompt-section button:hover { background: #047857; }
        .web-search-section { display: flex; align-items: center; gap: 10px; }
        .web-search-section input[type="checkbox"] { transform: scale(1.2); }
        .consensus-section label { display: flex; align-items: center; gap: 8px; font-size: 14px; cursor: pointer; }
        .consensus-section input[type="checkbox"] { width: 18px; height: 18px; cursor: pointer; }
        .conversation-controls { margin-bottom: 20px; }
        .conversation-controls h3 { color: #fff; margin-bottom: 10px; font-size: 16px; }
        .conversation-row { display: flex; gap: 10px; margin-bottom: 10px; align-items: center; }
        .conversation-row label { color: #e0e0e0; font-size: 14px; min-width: 60px; }
        .conversation-row input, .conversation-row select { flex: 1; padding: 6px 10px; background: #1a1a1a; border: 1px solid #333; color: #e0e0e0; border-radius: 4px; }
        .selected-models { position: sticky; bottom: 0; background: #111; padding-top: 20px; border-top: 1px solid #333; }
        .selected-models h3 { color: #fff; margin-bottom: 10px; font-size: 16px; }
        .selected-model-item { padding: 8px 12px; background: #1e3a8a; border-radius: 4px; margin-bottom: 6px; display: flex; justify-content: space-between; align-items: center; font-size: 14px; }
        .remove-selected { background: none; border: none; color: #dc2626; cursor: pointer; font-weight: bold; }
        .main-content { flex: 1; display: flex; flex-direction: column; }
        .chat-header { padding: 20px; background: #111; border-bottom: 1px solid #333; display: flex; justify-content: space-between; align-items: center; }
        .chat-header h1 { color: #fff; font-size: 24px; }
        .session-controls { display: flex; gap: 10px; align-items: center; }
        .session-controls select { padding: 8px 12px; background: #1a1a1a; border: 1px solid #333; color: #e0e0e0; border-radius: 4px; }
        .session-controls button { padding: 8px 16px; background: #2563eb; color: white; border: none; border-radius: 4px; cursor: pointer; transition: background 0.2s; }
        .session-controls button:hover { background: #1d4ed8; }
        .chat-messages { flex: 1; padding: 20px; overflow-y: auto; display: flex; flex-direction: column; gap: 20px; }
        .message { max-width: 800px; animation: fadeIn 0.3s ease-in; }
        .message.user { align-self: flex-end; }
        .message.assistant { align-self: flex-start; }
        .message-content { padding: 16px 20px; border-radius: 12px; line-height: 1.6; }
        .message.user .message-content { background: #2563eb; color: white; }
        .message.assistant .message-content { background: #1a1a1a; color: #e0e0e0; border: 1px solid #333; }
        .message.error .message-content { background: #dc2626; color: white; }
        .model-tag { font-size: 12px; color: #9ca3af; margin-bottom: 8px; font-weight: 500; }
        .file-preview { background: #374151; padding: 8px 12px; border-radius: 6px; margin-bottom: 8px; font-size: 12px; color: #d1d5db; }
        .loading-indicator { display: none; align-items: center; gap: 10px; padding: 16px 20px; background: #1a1a1a; border-radius: 12px; border: 1px solid #333; }
        .loading-spinner { width: 20px; height: 20px; border: 2px solid #333; border-top-color: #2563eb; border-radius: 50%; animation: spin 1s linear infinite; }
        .chat-input { padding: 20px; background: #111; border-top: 1px solid #333; }
        .input-area { display: flex; gap: 12px; align-items: flex-end; }
        .input-container { flex: 1; position: relative; }
        .message-input { width: 100%; min-height: 50px; max-height: 150px; padding: 12px 16px; background: #1a1a1a; border: 1px solid #333; color: #e0e0e0; border-radius: 8px; resize: none; font-family: inherit; font-size: 16px; }
        .message-input:focus { outline: none; border-color: #2563eb; }
        .file-input-container { position: relative; }
        .file-input { display: none; }
        .file-button { padding: 12px; background: #374151; color: #e0e0e0; border: none; border-radius: 8px; cursor: pointer; transition: background 0.2s; }
        .file-button:hover { background: #4b5563; }
        .send-button { padding: 12px 24px; background: #2563eb; color: white; border: none; border-radius: 8px; cursor: pointer; font-weight: 500; transition: background 0.2s; }
        .send-button:hover { background: #1d4ed8; }
        .send-button:disabled { background: #4b5563; cursor: not-allowed; }
        .file-preview-area { margin-top: 12px; padding: 12px; background: #1a1a1a; border-radius: 8px; display: none; }
        .file-info { display: flex; justify-content: space-between; align-items: center; }
        .file-name { color: #e0e0e0; font-size: 14px; }
        .remove-file { background: none; border: none; color: #dc2626; cursor: pointer; }
        .consensus-indicator { display: inline-block; padding: 2px 8px; background: #10b981; color: white; border-radius: 4px; font-size: 11px; margin-left: 8px; }
        @keyframes fadeIn { from { opacity: 0; transform: translateY(10px); } to { opacity: 1; transform: translateY(0); } }
        @keyframes spin { to { transform: rotate(360deg); } }
        
        /* Markdown styles */
        .message-content pre { background: #0a0a0a; padding: 12px; border-radius: 6px; overflow-x: auto; margin: 8px 0; }
        .message-content code { background: #0a0a0a; padding: 2px 6px; border-radius: 4px; font-family: 'SF Mono', Monaco, 'Cascadia Code', 'Roboto Mono', Consolas, 'Courier New', monospace; }
        .message-content pre code { background: none; padding: 0; }
        .message-content blockquote { border-left: 3px solid #2563eb; padding-left: 12px; margin: 8px 0; opacity: 0.8; }
        .message-content ul, .message-content ol { padding-left: 20px; margin: 8px 0; }
        .message-content table { border-collapse: collapse; width: 100%; margin: 8px 0; }
        .message-content th, .message-content td { border: 1px solid #333; padding: 8px; text-align: left; }
        .message-content th { background: #1a1a1a; }
    </style>
</head>
<body>
    <div class="container">
        <div class="sidebar">
            <section>
                <h2>Ollama Hosts</h2>
                <div class="host-input">
                    <input type="text" id="hostInput" placeholder="http://10.1.10.x:11434" />
                    <button onclick="addHost()">Add</button>
                    <button onclick="toggleHostHistory()" id="historyToggle">History</button>
                </div>
                <div class="host-history" id="hostHistory" style="display: none;">
                    <h3>Recent Hosts</h3>
                    <div id="hostHistoryList"></div>
                </div>
                <div class="host-list" id="hostList"></div>
            </section>
            <section>
                <h2>Available Models</h2>
                <div class="model-list" id="modelList"></div>
            </section>
            <section class="seed-prompt-section">
                <h2>System Seed Prompt</h2>
                <textarea id="seedPromptInput" placeholder="Set a system-wide prompt for all models..." rows="4"></textarea>
                <button onclick="saveSeedPrompt()">Save Prompt</button>
            </section>
            <section class="web-search-section">
                <h2>Web Search</h2>
                <label>
                    <input type="checkbox" id="enableWebSearch">
                    Enable DuckDuckGo search
                </label>
            </section>
            <section class="consensus-section">
                <h2>Consensus Generation</h2>
                <label>
                    <input type="checkbox" id="enableConsensus" checked>
                    <span>Generate Consensus Response</span>
                </label>
            </section>
            <section class="conversation-controls">
                <h2>Multi-Round Conversation</h2>
                <div class="conversation-row">
                    <label>Rounds:</label>
                    <input type="number" id="conversationRounds" min="0" max="10" value="0" />
                </div>
                <div class="conversation-row">
                    <label>Mode:</label>
                    <select id="conversationMode">
                        <option value="collaborative">Collaborative</option>
                        <option value="debate">Debate</option>
                        <option value="socratic">Socratic</option>
                        <option value="panel">Panel Discussion</option>
                    </select>
                </div>
            </section>
            <div class="selected-models">
                <h3>Active Models</h3>
                <div id="selectedModels"></div>
            </div>
        </div>
        
        <div class="main-content">
            <div class="chat-header">
                <h1>Multi-Ollama Chat</h1>
                <div class="session-controls">
                    <select id="sessionSelect" onchange="loadSession()">
                        <option value="">New Session</option>
                    </select>
                    <button onclick="handleNewSession()">New Session</button>
                </div>
            </div>
            
            <div class="chat-messages" id="chatMessages">
                <div class="message assistant">
                    <div class="message-content">
                        Welcome to Multi-Ollama Web Interface! Select models from the sidebar and start chatting.
                        
                        **Features:**
                        - Multi-model conversations with real-time responses
                        - File uploads (text, code, images up to 50MB)
                        - Web search integration
                        - Multi-round conversations (collaborative, debate, socratic, panel modes)
                        - Host history for quick reconnection
                        - Chat session management
                        - Consensus generation from multiple model responses
                    </div>
                </div>
            </div>
            
            <div class="loading-indicator" id="loadingIndicator">
                <div class="loading-spinner"></div>
                <span>Models are thinking...</span>
            </div>
            
            <div class="chat-input">
                <div class="file-preview-area" id="filePreview">
                    <div class="file-info">
                        <span class="file-name" id="fileName"></span>
                        <button class="remove-file" onclick="removeFile()">×</button>
                    </div>
                </div>
                
                <div class="input-area">
                    <div class="input-container">
                        <textarea 
                            id="messageInput" 
                            class="message-input" 
                            placeholder="Type your message... (Shift+Enter for new line)"
                            onkeydown="handleKeyPress(event)"
                        ></textarea>
                    </div>
                    
                    <div class="file-input-container">
                        <input type="file" id="fileInput" class="file-input" onchange="handleFileSelect(event)" accept=".txt,.md,.json,.xml,.csv,.pdf,.doc,.docx,.py,.js,.html,.css,.cpp,.c,.java,.go,.rs,.sh,.yml,.yaml,image/*">
                        <button class="file-button" onclick="document.getElementById('fileInput').click()">
                            📎
                        </button>
                    </div>
                    
                    <button class="send-button" id="sendButton" onclick="sendMessage()">
                        Send
                    </button>
                </div>
            </div>
        </div>
    </div>

    <script>
        let hosts = [];
        let models = [];
        let selectedModels = [];
        let currentSessionId = `session_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
        let isLoading = false;
        let attachedFile = null;

        // Initialize the application
        document.addEventListener('DOMContentLoaded', async function() {
            await loadInitialHosts();
            await loadSessionList();
            await loadSeedPrompt();
            handleNewSession();
            marked.setOptions({ breaks: true, gfm: true });
        });

        async function sendMessage() {
            const input = document.getElementById('messageInput'), prompt = input.value.trim();
            if ((!prompt && !attachedFile) || !selectedModels.length || isLoading) return;
            isLoading = true; input.value = ''; document.getElementById('sendButton').disabled = true;
            addMessageToUI('user', prompt, { file_name: attachedFile?.file?.filename }); showLoadingIndicator(true);

            const conversationRounds = parseInt(document.getElementById('conversationRounds').value) || 0;
            const conversationMode = document.getElementById('conversationMode').value;

            try {
                if (conversationRounds > 0) {
                    // Use Server-Sent Events for multi-round streaming
                    const response = await fetch('/api/generate-multi', {
                        method: 'POST', headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ 
                            models: selectedModels, 
                            prompt: prompt || (attachedFile ? 'Process this file' : ''),
                            sessionId: currentSessionId, 
                            fileData: attachedFile?.file, 
                            webSearch: document.getElementById('enableWebSearch').checked,
                            enableConsensus: document.getElementById('enableConsensus').checked,
                            conversationRounds,
                            conversationMode
                        })
                    });

                    if (!response.ok) throw await response.text();

                    const reader = response.body.getReader();
                    const decoder = new TextDecoder();
                    let buffer = '';

                    while (true) {
                        const { done, value } = await reader.read();
                        if (done) break;

                        buffer += decoder.decode(value, { stream: true });
                        const lines = buffer.split('\n');
                        buffer = lines.pop(); // Keep incomplete line in buffer

                        for (const line of lines) {
                            if (line.startsWith('data: ')) {
                                try {
                                    const data = JSON.parse(line.slice(6));
                                    if (data.type === 'status') {
                                        // Show status updates
                                        console.log('Status:', data.message);
                                    } else if (data.type === 'response') {
                                        // Display each response immediately
                                        const roundInfo = data.round ? ` (Round ${data.round})` : '';
                                        addMessageToUI('assistant', data.error || data.response, {
                                            ...data,
                                            model: data.model + roundInfo
                                        });
                                    } else if (data.type === 'complete') {
                                        showLoadingIndicator(false);
                                        isLoading = false;
                                        document.getElementById('sendButton').disabled = false;
                                        input.focus();
                                    }
                                } catch (e) {
                                    console.error('Failed to parse SSE data:', e);
                                }
                            }
                        }
                    }
                } else {
                    // Standard single-round response
                    const response = await fetch('/api/generate-multi', {
                        method: 'POST', headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ 
                            models: selectedModels, 
                            prompt: prompt || (attachedFile ? 'Process this file' : ''),
                            sessionId: currentSessionId, 
                            fileData: attachedFile?.file, 
                            webSearch: document.getElementById('enableWebSearch').checked,
                            enableConsensus: document.getElementById('enableConsensus').checked,
                            conversationRounds,
                            conversationMode
                        })
                    });
                    showLoadingIndicator(false);
                    if (!response.ok) throw await response.json();
                    const data = await response.json();
                    
                    // Display final responses
                    data.responses.forEach(r => addMessageToUI('assistant', r.error || r.response, r));
                }
            } catch (error) {
                console.error(error); addMessageToUI('assistant', `Error: ${error.message}`, { error: true });
            } finally {
                removeFile(); 
                if (!isLoading) return; // Don't reset if already handled by SSE
                isLoading = false; 
                document.getElementById('sendButton').disabled = false; 
                input.focus();
            }
        }

        function getContext() { return Array.from(document.querySelectorAll('.message')).slice(0, -1).map(m => `${m.classList.contains('user') ? 'user' : 'assistant'}: ${m.querySelector('.message-content').textContent}`).join('\n'); }

        async function loadInitialHosts() { try { hosts = await (await fetch('/api/hosts')).json(); renderHosts(); await updateModels(); } catch (e) { console.error(e); } }
        async function addHost() { try { const url = document.getElementById('hostInput').value.trim(); if (!url) return; const response = await fetch('/api/hosts', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ url }) }); if (!response.ok) { const error = await response.json(); throw new Error(error.error || 'Failed to add host'); } document.getElementById('hostInput').value = ''; await loadInitialHosts(); } catch (e) { alert(e.message); } }
        
        async function toggleHostHistory() {
            const historyDiv = document.getElementById('hostHistory');
            const toggleBtn = document.getElementById('historyToggle');
            
            if (historyDiv.style.display === 'none') {
                await loadHostHistory();
                historyDiv.style.display = 'block';
                toggleBtn.textContent = 'Hide';
            } else {
                historyDiv.style.display = 'none';
                toggleBtn.textContent = 'History';
            }
        }
        
        async function loadHostHistory() {
            try {
                const history = await fetch('/api/hosts/history').then(r => r.json());
                renderHostHistory(history);
            } catch (e) {
                console.error('Failed to load host history:', e);
            }
        }
        
        function renderHostHistory(history) {
            const historyList = document.getElementById('hostHistoryList');
            
            if (history.length === 0) {
                historyList.innerHTML = '<div style="color: #9ca3af; font-size: 12px;">No recent hosts</div>';
                return;
            }
            
            historyList.innerHTML = history.map(host => `
                <div class="host-history-item" onclick="addHostFromHistory('${host.url}')">
                    <div class="host-history-url">${host.nickname} (${host.url})</div>
                    <div class="host-history-meta">
                        <span>${host.status === 'online' ? '✅' : '❌'} ${host.modelCount} models</span>
                        <span>${formatActualTime(host.lastConnected)}</span>
                    </div>
                </div>
            `).join('');
        }
        
        async function addHostFromHistory(url) {
            document.getElementById('hostInput').value = url;
            await addHost();
            // Hide history after adding
            document.getElementById('hostHistory').style.display = 'none';
            document.getElementById('historyToggle').textContent = 'History';
        }
        
        function formatActualTime(isoString) {
            const date = new Date(isoString);
            return date.toLocaleString();
        }
        async function removeHost(url) { if (confirm(`Remove ${url}?`)) { await fetch(`/api/hosts/${encodeURIComponent(url)}`, { method: 'DELETE' }); await loadInitialHosts(); } }
        async function updateModels() { try { models = await (await fetch('/api/models')).json(); renderModels(); } catch (e) { console.error(e); } }
        function toggleModel(name, host) { selectedModels = selectedModels.some(m => m.name === name && m.host === host) ? selectedModels.filter(m => !(m.name === name && m.host === host)) : [...selectedModels, { name, host }]; renderSelectedModels(); renderModels(); }
        function handleNewSession() { currentSessionId = `session_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`; document.getElementById('chatMessages').innerHTML = ''; document.getElementById('sessionSelect').value = ''; removeFile(); }
        async function loadSession() { const id = document.getElementById('sessionSelect').value; if (!id) return handleNewSession(); currentSessionId = id; try { document.getElementById('chatMessages').innerHTML = ''; const messages = await (await fetch(`/api/chats/${id}`)).json(); messages.forEach(m => addMessageToUI(m.role, m.content, m)); } catch (e) { alert(e.message); } }
        async function loadSessionList() { try { const sessions = await (await fetch('/api/chats')).json(); const select = document.getElementById('sessionSelect'); select.innerHTML = '<option value="">New Session</option>' + sessions.map(s => `<option value="${s.session_id}">${new Date(s.last_message).toLocaleString()}</option>`).join(''); } catch (e) { console.error(e); } }
        function handleKeyPress(event) { if (event.key === 'Enter' && !event.shiftKey) { event.preventDefault(); sendMessage(); } }
        function handleFileSelect(event) { const file = event.target.files[0]; if (!file) return; if (file.size > 50 * 1024 * 1024) return alert('File too large (max 50MB)'); attachedFile = { file }; document.getElementById('fileName').textContent = file.name; document.getElementById('filePreview').style.display = 'block'; }
        function removeFile() { attachedFile = null; document.getElementById('fileInput').value = ''; document.getElementById('filePreview').style.display = 'none'; }
        function showLoadingIndicator(show) { document.getElementById('loadingIndicator').style.display = show ? 'flex' : 'none'; }
        async function saveSeedPrompt() { try { const prompt = document.getElementById('seedPromptInput').value; await fetch('/api/settings/seed-prompt', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ prompt }) }); alert('Seed prompt saved!'); } catch (e) { alert('Failed to save seed prompt'); } }
        async function loadSeedPrompt() { try { const response = await fetch('/api/settings/seed-prompt'); const data = await response.json(); document.getElementById('seedPromptInput').value = data.prompt || ''; } catch (e) { console.error('Failed to load seed prompt:', e); } }

        function renderHosts() {
            const hostList = document.getElementById('hostList');
            hostList.innerHTML = hosts.map(host => {
                const status = host.status === 'online' ? 'online' : 'offline';
                return `
                    <div class="host-item ${status}">
                        <div>
                            <span class="host-status ${status}"></span>
                            <span class="host-url">${host.url}</span>
                            ${host.models ? `<div style="font-size: 12px; color: #9ca3af; margin-left: 16px;">${host.models.length} models</div>` : ''}
                        </div>
                        <button class="remove-host" onclick="removeHost('${host.url}')">×</button>
                    </div>
                `;
            }).join('');
        }

        function renderModels() {
            const modelList = document.getElementById('modelList');
            if (models.length === 0) {
                modelList.innerHTML = '<div style="color: #9ca3af; padding: 10px;">No models available</div>';
                return;
            }

            modelList.innerHTML = models.map(model => {
                const isSelected = selectedModels.some(m => m.name === model.name && m.host === model.host);
                const hostUrl = new URL(model.host);
                const hostDisplay = hostUrl.hostname === 'localhost' ? 'Local' : hostUrl.hostname;
                
                return `
                    <div class="model-item ${isSelected ? 'selected' : ''}" onclick="toggleModel('${model.name}', '${model.host}')">
                        <input type="checkbox" ${isSelected ? 'checked' : ''} onclick="event.stopPropagation(); toggleModel('${model.name}', '${model.host}')">
                        <div class="model-details">
                            <div class="model-name">${model.name}</div>
                            <div class="model-meta">${hostDisplay} • ${(model.size / 1e9).toFixed(1)}GB</div>
                        </div>
                    </div>
                `;
            }).join('');
        }

        function renderSelectedModels() {
            const selectedModelsDiv = document.getElementById('selectedModels');
            if (selectedModels.length === 0) {
                selectedModelsDiv.innerHTML = '<div style="color: #9ca3af; padding: 10px; font-size: 14px;">No models selected</div>';
                return;
            }

            selectedModelsDiv.innerHTML = selectedModels.map(model => {
                const hostUrl = new URL(model.host);
                const hostDisplay = hostUrl.hostname === 'localhost' ? 'Local' : hostUrl.hostname;
                
                return `
                    <div class="selected-model-item">
                        <span>${model.name} @ ${hostDisplay}</span>
                        <button class="remove-selected" onclick="toggleModel('${model.name}', '${model.host}')">×</button>
                    </div>
                `;
            }).join('');
        }

        function addMessageToUI(role, content, details = {}) {
            const chatMessages = document.getElementById('chatMessages');
            const messageDiv = document.createElement('div');
            messageDiv.className = `message ${role} ${details.error ? 'error' : ''}`;

            let messageHTML = '';
            
            // Add file preview if present
            if (details.file_name) {
                messageHTML += `<div class="file-preview">📎 ${details.file_name}</div>`;
            }
            
            // Add model tag for assistant messages
            if (details.model && role === 'assistant') {
                const hostUrl = details.host ? new URL(details.host).hostname : '';
                const hostDisplay = hostUrl === 'localhost' ? 'Local' : hostUrl;
                messageHTML += `<div class="model-tag">${details.model} @ ${hostDisplay}</div>`;
            }
            
            // Add message content
            messageHTML += `<div class="message-content">`;
            if (details.error) {
                messageHTML += content;
            } else {
                messageHTML += role === 'assistant' ? marked.parse(content || '') : content;
            }
            messageHTML += `</div>`;
            
            // Add consensus indicator
            if (details.consensus || (details.model && details.model.includes('Consensus'))) {
                messageHTML += '<span class="consensus-indicator">Consensus</span>';
            }
            
            messageDiv.innerHTML = messageHTML;
            chatMessages.appendChild(messageDiv);
            chatMessages.scrollTop = chatMessages.scrollHeight;
            
            // Update session list after assistant responses
            if (role === 'assistant') {
                setTimeout(loadSessionList, 1000);
            }
        }
    </script>
</body>
</html>
EOL
    
    print_success "Frontend created"
}

# Install npm dependencies
install_npm_dependencies() {
    print_status "Installing npm dependencies..."
    npm install
    print_success "Dependencies installed"
}

# Create systemd service
create_systemd_service() {
    print_status "Creating systemd service..."
    
    sudo tee "$SERVICE_FILE" > /dev/null << EOL
[Unit]
Description=Multi-Ollama Web Interface
After=network.target ollama.service
Wants=ollama.service

[Service]
Type=simple
User=$USER
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=3
Environment=NODE_ENV=production
Environment=PORT=3000

[Install]
WantedBy=multi-user.target
EOL
    
    print_success "Systemd service created"
}

# Enable and start service
start_service() {
    print_status "Enabling and starting service..."
    sudo systemctl daemon-reload
    sudo systemctl enable "$SERVICE_NAME"
    sudo systemctl start "$SERVICE_NAME"
    
    sleep 3
    
    if sudo systemctl is-active --quiet "$SERVICE_NAME"; then
        print_success "Service started successfully"
    else
        print_error "Service failed to start"
        sudo systemctl status "$SERVICE_NAME"
        exit 1
    fi
}

# Create uninstall script
create_uninstall_script() {
    print_status "Creating uninstall script..."
    
    cat > "$INSTALL_DIR/uninstall.sh" << EOL
#!/bin/bash
echo "Stopping and removing Multi-Ollama Web Interface..."
sudo systemctl stop $SERVICE_NAME 2>/dev/null || true
sudo systemctl disable $SERVICE_NAME 2>/dev/null || true
sudo rm -f $SERVICE_FILE
sudo systemctl daemon-reload
rm -rf "$INSTALL_DIR"
echo "Multi-Ollama Web Interface has been uninstalled."
EOL
    
    chmod +x "$INSTALL_DIR/uninstall.sh"
    print_success "Uninstall script created at $INSTALL_DIR/uninstall.sh"
}

# Display final information
show_completion_info() {
    echo
    print_success "Multi-Ollama Web Interface installed successfully!"
    echo
    echo -e "${BLUE}Access your interface at:${NC} http://localhost:3000"
    echo
    echo -e "${BLUE}Service Management:${NC}"
    echo "  Status: sudo systemctl status $SERVICE_NAME"
    echo "  Stop:   sudo systemctl stop $SERVICE_NAME"
    echo "  Start:  sudo systemctl start $SERVICE_NAME"
    echo "  Logs:   sudo journalctl -u $SERVICE_NAME -f"
    echo
    echo -e "${BLUE}Installation Directory:${NC} $INSTALL_DIR"
    echo -e "${BLUE}Uninstall:${NC} bash $INSTALL_DIR/uninstall.sh"
    echo
    print_warning "Default setup includes localhost:11434. Add remote Ollama hosts via the web interface."
}

# Main installation process
main() {
    print_status "Starting Multi-Ollama Web Interface installation (Ubuntu/Debian)..."
    
    check_root
    update_system
    install_nodejs
    install_dependencies
    install_ollama
    create_install_dir
    create_package_json
    create_server_js
    create_frontend
    install_npm_dependencies
    create_systemd_service
    start_service
    create_uninstall_script
    show_completion_info
}

# Run main function
main "$@"