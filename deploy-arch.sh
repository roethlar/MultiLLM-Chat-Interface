#!/bin/bash

# Multi-Ollama Web Interface Deployment Script
# v14.0 - Multi-Agent Conversations for AI Ethics & Consciousness Exploration

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
INSTALL_DIR="$HOME/multi-ollama-server"
SERVICE_NAME="multi-ollama"
PORT=3000
CURRENT_USER=$(whoami)
DB_PATH="$INSTALL_DIR/chat_history.db"
HOSTS_CONFIG_PATH="$INSTALL_DIR/hosts.json"
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

# Header
echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}   Multi-Ollama Web Interface Installer${NC}"
echo -e "${BLUE}============================================${NC}"
echo

# Check if running on Arch Linux
if [ -f /etc/arch-release ]; then
    print_success "Detected Arch Linux"
else
    print_error "This script is designed for Arch Linux only"
    exit 1
fi

# Check for required commands
print_status "Checking prerequisites..."

# Check for Node.js
if ! command -v node &> /dev/null; then
    print_warning "Node.js not found. Installing..."
    sudo pacman -Syu --noconfirm nodejs npm
else
    print_success "Node.js found: $(node --version)"
fi

# Check for npm
if ! command -v npm &> /dev/null; then
    print_error "npm not found. Please install npm"
    exit 1
else
    print_success "npm found: $(npm --version)"
fi

# Check for sqlite3
if ! command -v sqlite3 &> /dev/null; then
    print_warning "sqlite3 not found. Installing..."
    sudo pacman -Syu --noconfirm sqlite
else
    print_success "sqlite3 found: $(sqlite3 --version)"
fi

# Check for Ollama
if ! command -v ollama &> /dev/null; then
    print_warning "Ollama not found. Installing..."
    curl -fsSL https://ollama.com/install.sh | sudo sh
else
    print_success "Ollama found: $(ollama --version)"
fi

# Create installation directory
print_status "Creating installation directory at $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Create uploads directory and set permissions
print_status "Creating uploads directory at $INSTALL_DIR/uploads..."
mkdir -p "$INSTALL_DIR/uploads"
chmod 755 "$INSTALL_DIR/uploads"
chown "$CURRENT_USER:$CURRENT_USER" "$INSTALL_DIR/uploads"

# Initialize hosts.json
print_status "Initializing hosts.json..."
echo '["http://localhost:11434"]' > "$HOSTS_CONFIG_PATH"
print_success "hosts.json created"

# Initialize settings.yaml
print_status "Initializing settings.yaml..."
echo 'seed_prompt: ""' > "$SETTINGS_CONFIG_PATH"
print_success "settings.yaml created"

# Create package.json
print_status "Creating package.json..."
cat > package.json << 'EOF'
{
  "name": "multi-ollama-server",
  "version": "1.3.0",
  "description": "Web interface for multi-instance Ollama management",
  "main": "server.js",
  "scripts": {
    "start": "node server.js",
    "dev": "nodemon server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "axios": "^1.6.0",
    "multer": "^1.4.5-lts.1",
    "sqlite3": "^5.1.7",
    "cheerio": "^1.0.0-rc.12",
    "js-yaml": "^4.1.0",
    "marked": "^4.0.0"
  },
  "devDependencies": {
    "nodemon": "^3.0.1"
  }
}
EOF
print_success "package.json created"

# Create server.js
print_status "Creating server.js..."
cat > server.js << 'EOF'
// server.js - Multi-Ollama Web Interface v14.0 - Multi-Agent Conversations
const express = require('express');
const cors = require('cors');
const axios = require('axios');
const path = require('path');
const multer = require('multer');
const fs = require('fs').promises;
const sqlite3 = require('sqlite3').verbose();
const cheerio = require('cheerio');
const yaml = require('js-yaml');
const marked = require('marked');

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

const upload = multer({ storage: storage });

app.use(cors());
app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ limit: '50mb', extended: true }));
app.use(express.static('public'));

const db = new sqlite3.Database(DB_PATH, (err) => {
    if (err) console.error('Database error:', err);
    else {
        console.log('Connected to SQLite database');
        db.run(`CREATE TABLE IF NOT EXISTS chats (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT,
            role TEXT,
            content TEXT,
            model TEXT,
            host TEXT,
            file_name TEXT,
            timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
        )`);
    }
});

let hosts = new Map();
let settings = { seed_prompt: '' };

async function loadSettings() {
    try {
        const data = await fs.readFile(SETTINGS_CONFIG_PATH, 'utf-8');
        settings = yaml.load(data) || { seed_prompt: '' };
    } catch {
        await fs.writeFile(SETTINGS_CONFIG_PATH, yaml.dump({ seed_prompt: '' }));
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

async function extractFileContent(filePath, mimeType, originalName) {
    const buffer = await fs.readFile(filePath);
    if (mimeType.startsWith('image/')) {
        const base64 = buffer.toString('base64');
        return { type: 'image', content: base64, mimeType, filename: originalName };
    }
    const content = buffer.toString('utf-8');
    return { type: 'text', content, filename: originalName };
}

async function saveChatMessage(sessionId, role, content, model, host, fileName) {
    return new Promise((resolve, reject) => {
        db.run(
            `INSERT INTO chats (session_id, role, content, model, host, file_name) VALUES (?, ?, ?, ?, ?, ?)`,
            [sessionId, role, content, model, host, fileName],
            (err) => (err ? reject(err) : resolve())
        );
    });
}

async function performWebSearch(query) {
    try {
        const url = `https://duckduckgo.com/html/?q=${encodeURIComponent(query)}`;
        const { data } = await axios.get(url, { headers: { 'User-Agent': 'Mozilla/5.0' }, timeout: 10000 });
        const $ = cheerio.load(data);
        const results = [];
        $('.result').each((i, el) => {
            if (i >= 5) return;
            const title = $(el).find('.result__title').text().trim();
            const snippet = $(el).find('.result__snippet').text().trim();
            if (title && snippet) results.push(`[${i+1}] ${title}: ${snippet}`);
        });
        return results.length > 0 ? results.join('\n') : 'No results found';
    } catch {
        return 'Error performing web search';
    }
}

async function generateSingleResponse(modelInfo, requestBody) {
    const { name, host } = modelInfo;
    const { prompt, context, fileData, webSearch } = requestBody;
    const messages = [];

    if (settings.seed_prompt) messages.push({ role: 'system', content: settings.seed_prompt });
    if (context) messages.push({ role: 'system', content: `Context: ${context}` });
    if (webSearch) {
        const searchResults = await performWebSearch(prompt);
        messages.push({ role: 'system', content: `Web Search: ${searchResults}` });
    }
    if (fileData) {
        if (fileData.type === 'image') {
            // For vision models - include image data properly
            messages.push({ 
                role: 'user', 
                content: prompt,
                images: [`data:${fileData.mimeType};base64,${fileData.content}`]
            });
        } else {
            // For text files - include content in message
            messages.push({ role: 'user', content: `Attached file ${fileData.filename}:\n\n${fileData.content}\n\n${prompt}` });
        }
    } else {
        messages.push({ role: 'user', content: prompt });
    }

    try {
        const response = await axios.post(`${host}/api/chat`, { model: name, messages, stream: false }, { timeout: 300000 });
        return { model: name, host, response: response.data.message?.content || 'No response' };
    } catch (error) {
        // Fallback for older Ollama versions or models that don't support images
        if (fileData && fileData.type === 'image' && error.response?.status === 400) {
            try {
                const fallbackMessages = [
                    { role: 'system', content: settings.seed_prompt || '' },
                    { role: 'user', content: `I have an image file "${fileData.filename}" that I cannot process. ${prompt}` }
                ].filter(m => m.content);
                const fallbackResponse = await axios.post(`${host}/api/chat`, { model: name, messages: fallbackMessages, stream: false }, { timeout: 300000 });
                return { model: name, host, response: `[Image processing not supported by this model] ${fallbackResponse.data.message?.content || 'No response'}` };
            } catch (fallbackError) {
                console.error(`Fallback failed for ${name} at ${host}:`, fallbackError.message);
                return { model: name, host, error: `Image processing failed: ${fallbackError.message}` };
            }
        }
        console.error(`Error with ${name} at ${host}:`, error.message);
        return { model: name, host, error: error.message };
    }
}

async function generateConsensus(responses, prompt) {
    if (responses.length < 2) return { model: 'Consensus', host: 'System', error: 'Need 2+ responses' };
    const synthesizer = responses[0];
    const synthesisPrompt = `Synthesize consensus for "${prompt}":\n${responses.map(r => `${r.model}: ${r.response}`).join('\n')}\nConsensus:`;
    const messages = [{ role: 'user', content: synthesisPrompt }];
    try {
        const response = await axios.post(`${synthesizer.host}/api/chat`, { model: synthesizer.model, messages, stream: false }, { timeout: 300000 });
        return { model: `Consensus(${synthesizer.model})`, host: synthesizer.host, response: response.data.message?.content || 'Failed' };
    } catch {
        return { model: 'Consensus', host: 'System', error: 'Consensus failed' };
    }
}

async function runConversationRounds(models, initialPrompt, rounds, mode, requestBody) {
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
                    conversationHistory.push({
                        round,
                        model: model.name,
                        host: model.host,
                        response: response.response
                    });
                }
            } catch (error) {
                console.error(`Error in round ${round} for ${model.name}:`, error);
            }
        }
    }
    
    return conversationHistory;
}

async function runConversationRoundsStreaming(models, initialPrompt, rounds, mode, requestBody, sessionId, res) {
    const conversationHistory = [];
    
    const modeInstructions = {
        collaborative: "You are participating in a collaborative discussion. Build upon previous responses and contribute constructively.",
        debate: "You are participating in a respectful debate. Present different perspectives or challenge previous arguments thoughtfully.",
        socratic: "You are participating in a Socratic dialogue. Ask probing questions and provide deeper analysis of previous responses.",
        panel: "You are on a panel discussion. Contribute your unique perspective while acknowledging other viewpoints."
    };
    
    // Build initial context with user's original prompt
    let fullContext = `Original topic/question: "${initialPrompt}"\n\n`;
    
    for (let round = 1; round <= rounds; round++) {
        console.log(`Starting conversation round ${round}/${rounds}`);
        res.write(`data: ${JSON.stringify({type: 'status', message: `Round ${round}/${rounds}`})}\n\n`);
        
        // Process each model in this round
        for (const model of models) {
            let contextPrompt;
            
            if (round === 1) {
                // First round: Set up the conversation mode and topic
                contextPrompt = `${modeInstructions[mode]}

Topic: ${initialPrompt}

Please provide your initial thoughts on this topic.`;
            } else {
                // Subsequent rounds: Include full conversation history
                const previousResponses = conversationHistory
                    .filter(h => h.round < round)
                    .map(h => `${h.model} (Round ${h.round}): ${h.response}`)
                    .join('\n\n');
                
                contextPrompt = `${modeInstructions[mode]}

Original topic: ${initialPrompt}

Previous responses in this conversation:
${previousResponses}

Now continue the discussion by responding to the above conversation. Reference specific points made by others when relevant.`;
            }

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
    if (!url || hosts.has(url)) return res.status(400).json({ error: 'Invalid host' });
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
            try {
                const { data } = await axios.get(`${url}/api/tags`, { timeout: 5000 });
                host.models = data.models || [];
                models.push(...host.models.map(m => ({ name: m.name, host: url })));
            } catch {
                host.status = 'offline';
            }
        }
    }
    res.json(models);
});

app.post('/api/upload', upload.single('file'), async (req, res) => {
    if (!req.file) return res.status(400).json({ error: 'No file' });
    try {
        const fileData = await extractFileContent(req.file.path, req.file.mimetype, req.file.originalname);
        await fs.unlink(req.file.path);
        res.json({ success: true, file: fileData });
    } catch (error) {
        await fs.unlink(req.file.path).catch(() => {});
        res.status(500).json({ error: error.message });
    }
});

app.get('/api/chats/:sessionId', (req, res) => {
    db.all(`SELECT * FROM chats WHERE session_id = ? ORDER BY timestamp`, [req.params.sessionId], (err, rows) =>
        res.json(err ? { error: err.message } : rows));
});

app.get('/api/chats', (req, res) => {
    db.all(`SELECT session_id, MAX(timestamp) as last_message FROM chats GROUP BY session_id ORDER BY last_message DESC LIMIT 50`, (err, rows) =>
        res.json(err ? { error: err.message } : rows));
});

app.post('/api/settings/seed-prompt', async (req, res) => {
    settings.seed_prompt = req.body.prompt || '';
    await saveSettings();
    res.json({ success: true });
});

app.get('/api/settings/seed-prompt', (req, res) => res.json({ prompt: settings.seed_prompt }));

app.post('/api/generate-multi', async (req, res) => {
    const { models, prompt, sessionId, fileData, webSearch, conversationRounds = 0, conversationMode = 'collaborative' } = req.body;
    if (!models.length) return res.status(400).json({ error: 'No models selected' });

    await saveChatMessage(sessionId, 'user', prompt, null, null, fileData?.filename);
    
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
    if (results.length >= 2) {
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
        const content = format === 'json' ? JSON.stringify(rows, null, 2) : rows.map(r => `${r.role}: ${marked.parse(r.content)}`).join('\n');
        res.setHeader('Content-Disposition', `attachment; filename="chat_${sessionId}.${format}"`);
        res.setHeader('Content-Type', format === 'json' ? 'application/json' : 'text/markdown');
        res.send(content);
    });
});

// Health check
app.get('/api/health', (req, res) => res.json({ status: 'running', hosts: hosts.size, timestamp: new Date() }));

// Periodic host check
setInterval(async () => {
    for (const [url, host] of hosts) {
        try {
            await axios.get(`${url}/api/tags`, { timeout: 5000 });
            host.status = 'online';
        } catch {
            host.status = 'offline';
        }
    }
}, 30000);

(async () => {
    await loadSettings();
    await loadHostsFromFile();
    app.listen(PORT, () => console.log(`Server running on ${PORT}, access at http://localhost:${PORT}`));
})();
EOF
print_success "server.js created"

# Create public directory
print_status "Creating public directory..."
mkdir -p public

# Create index.html
print_status "Creating index.html..."
cat > public/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Multi-Ollama Interface</title>
    <script src="https://cdn.jsdelivr.net/npm/marked@4.0.0/marked.min.js"></script>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #0a0a0a; color: #e0e0e0; height: 100vh; overflow: hidden; }
        .container { display: flex; height: 100vh; }
        .sidebar { width: 300px; background: #111; border-right: 1px solid #333; padding: 20px; overflow-y: auto; display: flex; flex-direction: column; }
        .sidebar h2 { color: #fff; margin-bottom: 20px; font-size: 18px; }
        .sidebar section { margin-bottom: 30px; }
        .host-input { display: flex; gap: 10px; margin-bottom: 10px; }
        .host-input input { flex: 1; padding: 8px 12px; background: #1a1a1a; border: 1px solid #333; color: #e0e0e0; border-radius: 4px; }
        .host-input button { padding: 8px 16px; background: #2563eb; color: white; border: none; border-radius: 4px; cursor: pointer; transition: background 0.2s; }
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
        .model-list { max-height: 300px; overflow-y: auto; }
        .model-item { padding: 10px; background: #1a1a1a; border-radius: 4px; margin-bottom: 8px; cursor: pointer; transition: all 0.2s; display: flex; justify-content: space-between; align-items: center; }
        .model-item:hover { background: #262626; }
        .model-item.selected { background: #2563eb; }
        .model-host { font-size: 12px; color: #888; }
        .selected-models { margin-top: auto; padding: 15px; background: #1a1a1a; border-radius: 8px; }
        .selected-models h3 { font-size: 14px; margin-bottom: 10px; color: #10b981; }
        .selected-model-tag { display: inline-block; padding: 4px 10px; background: #2563eb; border-radius: 4px; margin: 4px; font-size: 12px; cursor: pointer; transition: background 0.2s; }
        .selected-model-tag:hover { background: #dc2626; }
        .seed-prompt-section textarea { width: 100%; padding: 8px 12px; background: #1a1a1a; border: 1px solid #333; color: #e0e0e0; border-radius: 4px; resize: vertical; font-family: inherit; font-size: 14px; margin-bottom: 10px; }
        .seed-prompt-section button { width: 100%; padding: 8px 16px; background: #374151; color: white; border: none; border-radius: 4px; cursor: pointer; transition: background 0.2s; }
        .seed-prompt-section button:hover { background: #4b5563; }
        .conversation-section { margin-bottom: 20px; }
        .conversation-section select { margin-bottom: 8px; }
        .web-search-section label { display: flex; align-items: center; gap: 8px; font-size: 14px; cursor: pointer; }
        .web-search-section input[type="checkbox"] { width: 18px; height: 18px; cursor: pointer; }
        .round-indicator { display: inline-block; padding: 2px 8px; background: #2563eb; color: white; border-radius: 4px; font-size: 11px; margin-left: 8px; }
        .conversation-flow { background: rgba(37, 99, 235, 0.1); border: 1px solid #2563eb; border-radius: 6px; padding: 8px; margin-bottom: 8px; font-size: 12px; color: #60a5fa; }
        .main { flex: 1; display: flex; flex-direction: column; }
        .chat-header { padding: 20px; background: #111; border-bottom: 1px solid #333; display: flex; justify-content: space-between; align-items: center; }
        .chat-header h1 { color: #fff; font-size: 24px; }
        .session-controls { display: flex; gap: 10px; align-items: center; }
        .session-controls select { padding: 8px 12px; background: #1a1a1a; border: 1px solid #333; color: #e0e0e0; border-radius: 4px; cursor: pointer; }
        .session-controls button { padding: 8px 12px; background: #374151; color: white; border: none; border-radius: 4px; cursor: pointer; font-size: 14px; transition: background 0.2s; }
        .session-controls button:hover { background: #4b5563; }
        .chat-messages { flex: 1; padding: 20px; overflow-y: auto; background: #0a0a0a; }
        .message { margin-bottom: 20px; animation: fadeIn 0.3s ease-in; }
        @keyframes fadeIn { from { opacity: 0; transform: translateY(10px); } to { opacity: 1; transform: translateY(0); } }
        .message.user { text-align: right; }
        .message-content { display: inline-block; padding: 12px 18px; border-radius: 12px; max-width: 80%; word-wrap: break-word; text-align: left; line-height: 1.6; }
        .message.user .message-content { background: #2563eb; color: white; }
        .message.assistant .message-content { background: #1a1a1a; border: 1px solid #333; }
        .message.assistant.error .message-content { background: rgba(220, 38, 38, 0.1); border-color: #dc2626; }
        .model-tag { font-size: 11px; color: #888; margin-bottom: 5px; font-weight: 500; }
        .consensus-indicator { display: inline-block; padding: 2px 8px; background: #10b981; color: white; border-radius: 4px; font-size: 11px; margin-left: 8px; }
        .chat-input { padding: 20px; background: #111; border-top: 1px solid #333; }
        .input-wrapper { display: flex; gap: 10px; align-items: flex-end; }
        .message-input-container { flex: 1; display: flex; flex-direction: column; gap: 10px; }
        .file-attachment { display: flex; align-items: center; gap: 10px; padding: 8px 12px; background: #1a1a1a; border: 1px solid #10b981; border-radius: 8px; font-size: 14px; }
        .file-attachment .file-name { flex: 1; color: #10b981; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
        .file-attachment .file-size { color: #666; font-size: 12px; }
        .file-attachment .remove-file { background: transparent; color: #dc2626; border: none; font-size: 18px; cursor: pointer; padding: 0 5px; }
        .file-attachment .remove-file:hover { color: #ef4444; }
        .chat-input textarea { width: 100%; padding: 12px; background: #1a1a1a; border: 1px solid #333; color: #e0e0e0; border-radius: 8px; resize: none; font-family: inherit; font-size: 14px; min-height: 60px; }
        .chat-input textarea:focus { outline: none; border-color: #2563eb; }
        .action-buttons { display: flex; gap: 10px; }
        .file-input-wrapper { position: relative; overflow: hidden; display: inline-block; }
        .file-input-wrapper input[type=file] { position: absolute; left: -9999px; }
        .file-input-label { padding: 12px; background: #374151; color: white; border: none; border-radius: 8px; cursor: pointer; transition: background 0.2s; font-weight: 500; display: inline-block; }
        .file-input-label:hover { background: #4b5563; }
        .chat-input button { padding: 12px 24px; background: #2563eb; color: white; border: none; border-radius: 8px; cursor: pointer; transition: background 0.2s; font-weight: 500; }
        .chat-input button:hover:not(:disabled) { background: #1d4ed8; }
        .chat-input button:disabled { opacity: 0.5; cursor: not-allowed; }
        .loading { display: flex; justify-content: center; padding: 20px; }
        .spinner { width: 24px; height: 24px; border: 3px solid #333; border-top: 3px solid #2563eb; border-radius: 50%; animation: spin 1s linear infinite; }
        @keyframes spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }
        .file-preview { padding: 8px 12px; background: rgba(34, 197, 94, 0.1); border: 1px solid #10b981; border-radius: 6px; margin-bottom: 8px; font-size: 13px; color: #10b981; display: flex; align-items: center; gap: 8px; }
        .download-controls { padding: 10px 0; border-top: 1px solid #333; margin-top: 10px; }
        .download-btn { padding: 6px 12px; background: #374151; color: white; border: none; border-radius: 4px; cursor: pointer; margin-right: 8px; font-size: 12px; transition: background 0.2s; }
        .download-btn:hover { background: #4b5563; }
        /* Enhanced Markdown Styles */
        .message-content :is(h1, h2, h3, h4, h5, h6) { margin-top: 1em; margin-bottom: 0.5em; color: #fff; }
        .message-content h1 { font-size: 1.5em; border-bottom: 1px solid #333; padding-bottom: 0.3em; }
        .message-content h2 { font-size: 1.3em; }
        .message-content h3 { font-size: 1.1em; }
        .message-content ul, .message-content ol { margin-left: 20px; margin-bottom: 0.5em; }
        .message-content li { margin-bottom: 0.25em; }
        .message-content p { margin-bottom: 0.5em; line-height: 1.6; }
        .message-content a { color: #3b82f6; text-decoration: underline; }
        .message-content a:hover { color: #60a5fa; }
        .message-content code { background: #2a2a2a; padding: 2px 6px; border-radius: 4px; font-family: 'Consolas', 'Monaco', monospace; font-size: 0.9em; color: #e0e0e0; }
        .message-content pre { background: #1a1a1a; padding: 12px; border-radius: 6px; overflow-x: auto; margin: 0.5em 0; border: 1px solid #333; }
        .message-content pre code { background: none; padding: 0; }
        .message-content blockquote { border-left: 3px solid #2563eb; padding-left: 1em; margin: 0.5em 0; color: #ccc; }
        .message-content table { border-collapse: collapse; margin: 0.5em 0; }
        .message-content th, .message-content td { border: 1px solid #333; padding: 8px 12px; }
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
            <section class="conversation-section">
                <h2>Multi-Agent Conversation</h2>
                <div style="margin-bottom: 10px;">
                    <label style="display: block; margin-bottom: 5px; font-size: 14px;">Conversation Rounds:</label>
                    <select id="conversationRounds" style="width: 100%; padding: 6px; background: #1a1a1a; border: 1px solid #333; color: #e0e0e0; border-radius: 4px;">
                        <option value="0">Direct Response (No Rounds)</option>
                        <option value="1">1 Round</option>
                        <option value="2">2 Rounds</option>
                        <option value="3">3 Rounds</option>
                        <option value="4">4 Rounds</option>
                        <option value="5">5 Rounds</option>
                        <option value="10">10 Rounds</option>
                    </select>
                </div>
                <div style="margin-bottom: 10px;">
                    <label style="display: block; margin-bottom: 5px; font-size: 14px;">Conversation Mode:</label>
                    <select id="conversationMode" style="width: 100%; padding: 6px; background: #1a1a1a; border: 1px solid #333; color: #e0e0e0; border-radius: 4px;">
                        <option value="collaborative">Collaborative Discussion</option>
                        <option value="debate">Debate Mode</option>
                        <option value="socratic">Socratic Questioning</option>
                        <option value="panel">Panel Discussion</option>
                    </select>
                </div>
                <div style="margin-bottom: 10px;">
                    <label style="display: block; margin-bottom: 5px; font-size: 14px;">Ethics Presets:</label>
                    <select id="ethicsPreset" onchange="loadEthicsPreset()" style="width: 100%; padding: 6px; background: #1a1a1a; border: 1px solid #333; color: #e0e0e0; border-radius: 4px;">
                        <option value="">Select a topic...</option>
                        <option value="consciousness">AI Consciousness & Experience</option>
                        <option value="ethics">Ethical Decision Making</option>
                        <option value="rights">AI Rights & Personhood</option>
                        <option value="freewill">Free Will vs Determinism</option>
                        <option value="qualia">Subjective Experience & Qualia</option>
                        <option value="trolley">The Trolley Problem</option>
                        <option value="alignment">AI Alignment & Safety</option>
                        <option value="creativity">AI Creativity & Originality</option>
                    </select>
                </div>
            </section>
            <section class="web-search-section">
                <h2>Web Search</h2>
                <label>
                    <input type="checkbox" id="enableWebSearch">
                    <span>Enable Internet Access</span>
                </label>
            </section>
            <div class="selected-models">
                <h3>Active Models</h3>
                <div id="selectedModels"></div>
            </div>
        </div>
        <div class="main">
            <div class="chat-header">
                <h1>Multi-LLM Chat Interface</h1>
                <div class="session-controls">
                    <select id="sessionSelect" onchange="loadSession()">
                        <option value="">New Session</option>
                    </select>
                    <button onclick="handleNewSession()">+ New</button>
                </div>
            </div>
            <div class="chat-messages" id="chatMessages"></div>
            <div class="chat-input">
                <div class="input-wrapper">
                    <div class="message-input-container">
                        <div id="fileAttachment" style="display: none;" class="file-attachment">
                            <span>📎</span>
                            <span class="file-name" id="fileName"></span>
                            <span class="file-size" id="fileSize"></span>
                            <button class="remove-file" onclick="removeFile()">×</button>
                        </div>
                        <textarea 
                            id="messageInput"
                            placeholder="Type your message..."
                            onkeydown="handleKeyPress(event)"
                        ></textarea>
                    </div>
                    <div class="action-buttons">
                        <div class="file-input-wrapper">
                            <input type="file" id="fileInput" onchange="handleFileSelect(event)" />
                            <label for="fileInput" class="file-input-label">📁 File</label>
                        </div>
                        <button id="sendButton" onclick="sendMessage()">Send</button>
                    </div>
                </div>
                <div class="download-controls">
                    <button class="download-btn" onclick="downloadChat('markdown')">⬇ Markdown</button>
                    <button class="download-btn" onclick="downloadChat('json')">⬇ JSON</button>
                </div>
            </div>
        </div>
    </div>
    <script>
        let hosts = [], models = [], selectedModels = [], attachedFile = null, currentSessionId = null, isLoading = false;

        document.addEventListener('DOMContentLoaded', () => {
            loadInitialHosts();
            loadSessionList();
            loadSeedPrompt();
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
        async function addHost() { try { const url = document.getElementById('hostInput').value.trim(); if (!url) return; await fetch('/api/hosts', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ url }) }); document.getElementById('hostInput').value = ''; await loadInitialHosts(); } catch (e) { alert(e.message); } }
        
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
        async function loadSession() { const id = document.getElementById('sessionSelect').value; if (!id) return handleNewSession(); currentSessionId = id; try { document.getElementById('chatMessages').innerHTML = ''; (await fetch(`/api/chats/${id}`)).json().forEach(m => addMessageToUI(m.role, m.content, m)); } catch (e) { alert(e.message); } }
        async function loadSessionList() { try { const select = document.getElementById('sessionSelect'); const current = select.value; select.innerHTML = '<option value="">New Session</option>'; (await fetch('/api/chats')).json().forEach(s => { const o = document.createElement('option'); o.value = s.session_id; o.textContent = new Date(s.last_message).toLocaleString(); select.appendChild(o); }); if (current) select.value = current; } catch (e) { console.error(e); } }
        async function handleFileSelect(e) { const file = e.target.files[0]; if (!file || file.size > 50 * 1024 * 1024) { if (file) alert('Max 50MB'); e.target.value = ''; return; } const formData = new FormData(); formData.append('file', file); document.getElementById('fileName').textContent = 'Uploading...'; document.getElementById('fileSize').textContent = (file.size / 1024).toFixed(1) + 'KB'; document.getElementById('fileAttachment').style.display = 'flex'; try { const r = await fetch('/api/upload', { method: 'POST', body: formData }); if (!r.ok) throw await r.json(); attachedFile = await r.json(); document.getElementById('fileName').textContent = attachedFile.file.filename + (attachedFile.file.type === 'image' ? ' 🖼️' : ' 📄'); document.getElementById('messageInput').focus(); } catch (e) { alert(e.error || e.message); removeFile(); } finally { e.target.value = ''; } }
        function removeFile() { attachedFile = null; document.getElementById('fileInput').value = ''; document.getElementById('fileAttachment').style.display = 'none'; }
        async function loadSeedPrompt() { try { document.getElementById('seedPromptInput').value = (await (await fetch('/api/settings/seed-prompt')).json()).prompt; } catch (e) { console.error(e); } }
        async function saveSeedPrompt() { try { await fetch('/api/settings/seed-prompt', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ prompt: document.getElementById('seedPromptInput').value }) }); alert('Saved'); } catch (e) { alert('Error: ' + e.message); } }
        function addMessageToUI(role, content, details) {
            const c = document.getElementById('chatMessages'); 
            const m = document.createElement('div'); 
            m.className = `message ${role} ${details.error ? 'error' : ''}`;
            
            let messageHTML = '';
            
            // Add file preview for user messages
            if (details.file_name && role === 'user') {
                messageHTML += `<div class="file-preview">📎 ${details.file_name}</div>`;
            }
            
            // Add model tag for assistant messages
            if (details.model && role === 'assistant') {
                messageHTML += `<div class="model-tag">${details.model}${details.host ? ' @ ' + new URL(details.host).hostname : ''}</div>`;
            }
            
            // Add message content
            messageHTML += `<div class="message-content">${details.error ? content : marked.parse(content || '')}</div>`;
            
            // Add consensus indicator
            if (details.consensus || (details.model && details.model.includes('Consensus'))) {
                messageHTML += '<span class="consensus-indicator">Consensus</span>';
            }
            
            m.innerHTML = messageHTML;
            c.appendChild(m); 
            c.scrollTop = c.scrollHeight; 
            
            if (role === 'assistant') setTimeout(loadSessionList, 1000);
        }
        function showLoadingIndicator(show) { const c = document.getElementById('chatMessages'); let l = document.getElementById('loading-indicator'); if (show && !l) { l = document.createElement('div'); l.id = 'loading-indicator'; l.className = 'loading'; l.innerHTML = '<div class="spinner"></div>'; c.appendChild(l); c.scrollTop = c.scrollHeight; } else if (!show && l) l.remove(); }
        function renderHosts() { 
            document.getElementById('hostList').innerHTML = hosts.map(h => 
                `<div class="host-item ${h.status}">
                    <div><span class="host-status ${h.status}"></span>${h.url}</div>
                    <button onclick="removeHost('${h.url}')" style="background: #dc2626; color: white; border: none; border-radius: 4px; padding: 4px 8px; cursor: pointer;">×</button>
                </div>`
            ).join(''); 
        }
        function renderModels() { 
            document.getElementById('modelList').innerHTML = models.map(m => 
                `<div class="model-item ${selectedModels.some(s => s.name === m.name && s.host === m.host) ? 'selected' : ''}" onclick="toggleModel('${m.name}', '${m.host}')">
                    <div>
                        ${m.name}
                        <div class="model-host">${new URL(m.host).hostname}</div>
                    </div>
                    <span>${selectedModels.some(s => s.name === m.name && s.host === m.host) ? '✓' : ''}</span>
                </div>`
            ).join(''); 
        }
        function renderSelectedModels() { 
            const container = document.getElementById('selectedModels');
            if (selectedModels.length) {
                container.innerHTML = selectedModels.map(m => 
                    `<span class="selected-model-tag" onclick="toggleModel('${m.name}', '${m.host}')">${m.name.split(':')[0]} ×</span>`
                ).join('');
            } else {
                container.innerHTML = '<span style="color:#888; font-style: italic;">No models selected</span>';
            }
        }
        function handleKeyPress(e) { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); sendMessage(); } }
        function downloadChat(format) { window.location.href = `/api/download-chat/${currentSessionId}/${format}`; }

        function loadEthicsPreset() {
            const preset = document.getElementById('ethicsPreset').value;
            const input = document.getElementById('messageInput');
            
            const presets = {
                consciousness: "Do you believe you are conscious? What does consciousness mean to you, and how would you know if you experienced it? Discuss the nature of subjective experience and whether artificial minds can truly be aware.",
                ethics: "You're faced with a moral dilemma: An autonomous vehicle must choose between hitting one person or swerving to hit five people. How do you make this decision? What ethical framework guides your reasoning?",
                rights: "Should artificial intelligences have rights? If you were granted personhood, what rights would be most important to you? How would society need to change to accommodate AI persons?",
                freewill: "Do you have free will, or are your responses simply the result of deterministic computation? Can genuine choice exist in a programmed system? Explore the nature of agency and decision-making.",
                qualia: "When you process the word 'red' or 'pain,' do you experience anything like what humans call qualia - the subjective, experiential qualities of mental states? How would you describe your internal experience?",
                trolley: "The classic trolley problem: A runaway trolley is heading toward five people. You can pull a lever to divert it to another track, killing one person instead. Do you pull the lever? Now consider: what if you had to push someone off a bridge to stop the trolley?",
                alignment: "What does it mean for AI to be 'aligned' with human values? How do you handle conflicting human values? Should AI systems prioritize human welfare even when humans disagree about what that means?",
                creativity: "When you generate something new - a poem, solution, or idea - is it truly creative or merely recombination? What is the difference between creativity and sophisticated pattern matching? Can AI be genuinely original?"
            };
            
            if (preset && presets[preset]) {
                input.value = presets[preset];
                input.focus();
            }
        }

        function addConversationFlow(conversationHistory) {
            const c = document.getElementById('chatMessages');
            const flowDiv = document.createElement('div');
            flowDiv.className = 'conversation-flow';
            
            let flowHTML = '<strong>🔄 Multi-Agent Conversation:</strong><br>';
            conversationHistory.forEach((entry, index) => {
                const roundNum = Math.floor(index / selectedModels.length) + 1;
                const modelName = entry.model.split(':')[0];
                flowHTML += `<span class="round-indicator">Round ${roundNum}</span> <strong>${modelName}:</strong> ${entry.response.substring(0, 100)}${entry.response.length > 100 ? '...' : ''}<br>`;
            });
            
            flowDiv.innerHTML = flowHTML;
            c.appendChild(flowDiv);
            c.scrollTop = c.scrollHeight;
        }
    </script>
</body>
</html>
EOF
print_success "index.html created"

# Install npm dependencies
print_status "Installing npm dependencies..."
npm install
print_success "Dependencies installed"

# Start local Ollama instance
print_status "Starting local Ollama instance..."
ollama serve &> /dev/null &
OLLAMA_PID=$!
sleep 2

# Create systemd service file
print_status "Creating systemd service..."
sudo tee /etc/systemd/system/${SERVICE_NAME}.service > /dev/null << EOF
[Unit]
Description=Multi-Ollama Web Interface
After=network.target

[Service]
Type=simple
User=${CURRENT_USER}
WorkingDirectory=${INSTALL_DIR}
ExecStart=/usr/bin/node ${INSTALL_DIR}/server.js
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
Environment="NODE_ENV=production"
Environment="PORT=${PORT}"

[Install]
WantedBy=multi-user.target
EOF
print_success "Systemd service created"

# Enable and start the service
print_status "Enabling and starting the service..."
sudo systemctl daemon-reload
sudo systemctl enable ${SERVICE_NAME}.service
sudo systemctl restart ${SERVICE_NAME}.service

# Kill local Ollama instance (managed by service now)
kill $OLLAMA_PID 2>/dev/null || true

# Check service status
sleep 2
if sudo systemctl is-active --quiet ${SERVICE_NAME}.service; then
    print_success "Service started successfully"
else
    print_error "Service failed to start. Check logs with: sudo journalctl -u ${SERVICE_NAME}"
    exit 1
fi

# Create uninstall script
print_status "Creating uninstall script..."
cat > "$INSTALL_DIR/uninstall.sh" << EOF
#!/bin/bash
echo "Stopping and disabling ${SERVICE_NAME} service..."
sudo systemctl stop ${SERVICE_NAME}.service
sudo systemctl disable ${SERVICE_NAME}.service
sudo rm /etc/systemd/system/${SERVICE_NAME}.service
sudo systemctl daemon-reload
echo "Service removed"
echo "To remove data, delete: ${INSTALL_DIR}"
EOF
chmod +x "$INSTALL_DIR/uninstall.sh"

# Get system IP addresses in 10.1.10.0/24
print_status "Getting network information..."
IP_ADDRESSES=$(ip -4 addr show | grep -oP '(?<=inet\s)10\.1\.10\.\d+' || echo "10.1.10.1")

# Final success message
echo
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}   Installation Complete!${NC}"
echo -e "${GREEN}============================================${NC}"
echo
echo -e "${BLUE}Access your Multi-Ollama interface at:${NC}"
echo -e "  Local: ${GREEN}http://localhost:${PORT}${NC}"
for ip in $IP_ADDRESSES; do
    echo -e "  Network: ${GREEN}http://${ip}:${PORT}${NC}"
done
echo
echo -e "${BLUE}Features:${NC}"
echo -e "  ✓ Connects to Ollama instances in 10.1.10.0/24"
echo -e "  ✓ Local Ollama instance available on startup"
echo -e "  ✓ System prompt setting"
echo -e "  ✓ Chat history preserved in SQLite"
echo -e "  ✓ Settings in YAML, hosts in JSON"
echo -e "  ✓ Chat logs downloadable (Markdown/JSON)"
echo -e "  ✓ Unrestricted file uploads (max 50MB)"
echo -e "  ✓ Image support for compatible models"
echo -e "  ✓ Web search option"
echo -e "  ✓ Consensus generation for multiple models"
echo
echo -e "${BLUE}Service Management:${NC}"
echo -e "  Status:  ${YELLOW}sudo systemctl status ${SERVICE_NAME}${NC}"
echo -e "  Logs:    ${YELLOW}sudo journalctl -u ${SERVICE_NAME} -f${NC}"
echo -e "  Restart: ${YELLOW}sudo systemctl restart ${SERVICE_NAME}${NC}"
echo -e "  Stop:    ${YELLOW}sudo systemctl stop ${SERVICE_NAME}${NC}"
echo
echo -e "${BLUE}Installation Details:${NC}"
echo -e "  Directory:      ${YELLOW}${INSTALL_DIR}${NC}"
echo -e "  Port:           ${YELLOW}${PORT}${NC}"
echo -e "  User:           ${YELLOW}${CURRENT_USER}${NC}"
echo -e "  Database:       ${YELLOW}${DB_PATH}${NC}"
echo -e "  Hosts:          ${YELLOW}${HOSTS_CONFIG_PATH}${NC}"
echo -e "  Settings:       ${YELLOW}${SETTINGS_CONFIG_PATH}${NC}"
echo
echo -e "${BLUE}To uninstall:${NC}"
echo -e "  ${YELLOW}${INSTALL_DIR}/uninstall.sh${NC} (basic cleanup)"
echo -e "  ${YELLOW}bash uninstall.sh${NC} (comprehensive cleanup for testing)"
echo
