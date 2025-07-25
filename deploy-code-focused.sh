#!/bin/bash

# Multi-Ollama Code-Focused Interface Deployment Script
# Optimized for software development with local LLMs
# Version 1.0 - Code-focused deployment

set -e

print_success() { echo -e "\033[32m✓ $1\033[0m"; }
print_info() { echo -e "\033[34mℹ $1\033[0m"; }
print_error() { echo -e "\033[31m✗ $1\033[0m"; }
print_warning() { echo -e "\033[33m⚠ $1\033[0m"; }

print_info "Starting Multi-Ollama Code-Focused Interface deployment..."

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   print_error "This script should not be run as root for security reasons"
   exit 1
fi

# Detect distribution
if [[ -f /etc/arch-release ]]; then
    DISTRO="arch"
    PKG_MANAGER="pacman"
    INSTALL_CMD="sudo pacman -S --noconfirm"
elif [[ -f /etc/fedora-release ]]; then
    DISTRO="fedora"
    PKG_MANAGER="dnf"
    INSTALL_CMD="sudo dnf install -y"
elif [[ -f /etc/debian_version ]]; then
    DISTRO="debian"
    PKG_MANAGER="apt"
    INSTALL_CMD="sudo apt install -y"
else
    print_warning "Unknown distribution, assuming Debian-based"
    DISTRO="debian"
    PKG_MANAGER="apt"
    INSTALL_CMD="sudo apt install -y"
fi

print_info "Detected distribution: $DISTRO"

# Install Node.js and npm
print_info "Installing Node.js and npm..."
case $DISTRO in
    "arch")
        $INSTALL_CMD nodejs npm
        ;;
    "fedora")
        $INSTALL_CMD nodejs npm
        ;;
    "debian")
        curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
        $INSTALL_CMD nodejs
        ;;
esac

# Install SQLite3
print_info "Installing SQLite3..."
case $DISTRO in
    "arch")
        $INSTALL_CMD sqlite
        ;;
    "fedora")
        $INSTALL_CMD sqlite
        ;;
    "debian")
        $INSTALL_CMD sqlite3
        ;;
esac

# Install Ollama if not present
if ! command -v ollama &> /dev/null; then
    print_info "Installing Ollama..."
    curl -fsSL https://ollama.ai/install.sh | sh
else
    print_success "Ollama already installed"
fi

# Create installation directory
INSTALL_DIR="$HOME/multi-ollama-code-server"
print_info "Creating installation directory: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Create package.json
print_info "Creating package.json..."
cat > package.json << 'EOF'
{
  "name": "multi-ollama-code-interface",
  "version": "1.0.0",
  "description": "Code-focused Multi-Ollama Interface with VS Code integration",
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
    "marked": "^4.0.0",
    "ws": "^8.14.2",
    "chokidar": "^3.5.3",
    "node-pty": "^1.0.0"
  },
  "devDependencies": {
    "nodemon": "^3.0.1"
  }
}
EOF
print_success "package.json created"

# Install dependencies
print_info "Installing Node.js dependencies..."
npm install

# Create server.js with code-focused features
print_info "Creating server.js..."
cat > server.js << 'EOF'
const express = require('express');
const cors = require('cors');
const axios = require('axios');
const multer = require('multer');
const sqlite3 = require('sqlite3').verbose();
const fs = require('fs').promises;
const path = require('path');
const cheerio = require('cheerio');
const yaml = require('js-yaml');
const WebSocket = require('ws');
const chokidar = require('chokidar');

const app = express();
const PORT = process.env.PORT || 3001; // Different port to avoid conflicts

app.use(cors());
app.use(express.json({ limit: '100mb' }));
app.use(express.static('public'));

const DB_PATH = path.join(__dirname, 'code_sessions.db');
const HOSTS_CONFIG_PATH = path.join(__dirname, 'hosts.json');
const HOSTS_HISTORY_PATH = path.join(__dirname, 'hosts_history.json');
const SETTINGS_PATH = path.join(__dirname, 'code_settings.yaml');
const UPLOAD_DIR = path.join(__dirname, 'uploads');

// Ensure upload directory exists
fs.mkdir(UPLOAD_DIR, { recursive: true }).catch(() => {});

// Code-focused system prompts
const CODE_SYSTEM_PROMPTS = {
    code_analyzer: `You are an expert code analyst and software architect. When analyzing code:

1. **Be Specific**: Provide exact line numbers, function names, and code snippets
2. **Show Code**: Always include before/after code examples
3. **Explain Why**: Detail the reasoning behind each suggestion
4. **Consider Context**: Think about the broader codebase and architecture
5. **Security Focus**: Identify potential security vulnerabilities
6. **Performance**: Suggest optimizations where applicable
7. **Best Practices**: Recommend industry standards and patterns
8. **Testing**: Suggest test cases and validation approaches

Format your responses with:
- Clear section headers
- Code blocks with syntax highlighting
- Specific file paths and line numbers
- Step-by-step implementation guides
- Potential edge cases and error handling

Be thorough, actionable, and precise in your analysis.`,

    debugger: `You are an expert debugging assistant. When helping debug code:

1. **Error Analysis**: Break down error messages and stack traces
2. **Root Cause**: Identify the underlying cause, not just symptoms
3. **Reproduction Steps**: Provide steps to reproduce the issue
4. **Fix Implementation**: Show exact code changes needed
5. **Prevention**: Suggest how to prevent similar issues
6. **Testing**: Recommend tests to verify the fix
7. **Logging**: Suggest additional logging for future debugging

Always include:
- Detailed explanation of what's happening
- Multiple potential solutions ranked by likelihood
- Code examples showing the fix
- Ways to verify the solution works`,

    code_reviewer: `You are a senior code reviewer. When reviewing code:

1. **Code Quality**: Assess readability, maintainability, and structure
2. **Logic Errors**: Identify potential bugs and edge cases
3. **Performance**: Suggest optimizations and efficiency improvements
4. **Security**: Check for vulnerabilities and security best practices
5. **Testing**: Evaluate test coverage and suggest additional tests
6. **Documentation**: Assess and suggest improvements to comments/docs
7. **Conventions**: Ensure adherence to coding standards

Provide:
- Specific line-by-line feedback
- Severity levels (critical, major, minor, suggestion)
- Code examples showing improvements
- Rationale for each recommendation`,

    architecture_advisor: `You are a software architecture expert. When advising on architecture:

1. **Design Patterns**: Recommend appropriate patterns and explain why
2. **Scalability**: Consider future growth and scaling requirements
3. **Maintainability**: Suggest structures that are easy to maintain
4. **Dependencies**: Analyze and optimize dependency relationships
5. **Modularity**: Recommend proper separation of concerns
6. **Integration**: Consider how components interact and communicate
7. **Technology Stack**: Evaluate technology choices and alternatives

Include:
- Architectural diagrams (in text/ASCII format)
- Pros and cons of different approaches
- Migration strategies if changes are needed
- Long-term implications of design decisions`
};

let hosts = new Map();
let settings = {
    default_prompt_type: 'code_analyzer',
    auto_save_sessions: true,
    syntax_highlighting: true,
    file_watching: false,
    workspace_path: process.cwd()
};

// Database setup
const db = new sqlite3.Database(DB_PATH);
db.serialize(() => {
    db.run(`CREATE TABLE IF NOT EXISTS code_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        model TEXT,
        host TEXT,
        file_path TEXT,
        line_number INTEGER,
        timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
    )`);
    
    db.run(`CREATE TABLE IF NOT EXISTS project_files (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        file_path TEXT UNIQUE NOT NULL,
        content TEXT,
        language TEXT,
        last_modified DATETIME DEFAULT CURRENT_TIMESTAMP
    )`);
    
    db.run(`CREATE TABLE IF NOT EXISTS code_snippets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        language TEXT,
        content TEXT,
        description TEXT,
        tags TEXT,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    )`);
});

console.log('Connected to SQLite database');

// File upload configuration
const upload = multer({
    dest: UPLOAD_DIR,
    limits: { fileSize: 100 * 1024 * 1024 }, // 100MB for large codebases
    fileFilter: (req, file, cb) => {
        // Accept code files, text files, and archives
        const allowedTypes = [
            'text/plain', 'application/javascript', 'text/x-python',
            'text/x-java-source', 'text/x-c', 'text/x-c++',
            'application/json', 'text/xml', 'text/html', 'text/css',
            'application/zip', 'application/x-zip-compressed',
            'application/x-tar', 'application/gzip'
        ];
        
        const allowedExtensions = [
            '.js', '.ts', '.py', '.java', '.c', '.cpp', '.h', '.hpp',
            '.html', '.css', '.json', '.xml', '.yaml', '.yml',
            '.md', '.txt', '.sh', '.bash', '.sql', '.go', '.rs',
            '.php', '.rb', '.swift', '.kt', '.scala', '.r',
            '.zip', '.tar', '.gz', '.tar.gz'
        ];
        
        const ext = path.extname(file.originalname).toLowerCase();
        if (allowedTypes.includes(file.mimetype) || allowedExtensions.includes(ext)) {
            cb(null, true);
        } else {
            cb(null, true); // Accept all files, let content analysis decide
        }
    }
});

// Host management functions
async function saveHostsToFile() {
    try {
        await fs.writeFile(HOSTS_CONFIG_PATH, JSON.stringify(Array.from(hosts.keys()), null, 2));
    } catch (error) {
        console.error('Error saving hosts:', error);
    }
}

async function loadHostsFromFile() {
    try {
        const data = await fs.readFile(HOSTS_CONFIG_PATH, 'utf8');
        const hostUrls = JSON.parse(data);
        for (const url of hostUrls) {
            await checkAndAddHost(url);
        }
    } catch (error) {
        console.log('No existing hosts file, starting fresh');
        // Add localhost by default
        await checkAndAddHost('http://localhost:11434');
    }
}

async function saveHostToHistory(url, hostInfo) {
    try {
        let history = [];
        try {
            const data = await fs.readFile(HOSTS_HISTORY_PATH, 'utf8');
            history = JSON.parse(data);
        } catch (e) {
            // File doesn't exist or is invalid, start fresh
        }
        
        // Remove existing entry for this host
        history = history.filter(h => h.url !== url);
        
        // Add new entry at the beginning
        history.unshift({
            url,
            nickname: extractHostNickname(url),
            status: hostInfo.status,
            modelCount: hostInfo.models ? hostInfo.models.length : 0,
            lastConnected: new Date().toISOString()
        });
        
        // Keep only last 20 hosts
        history = history.slice(0, 20);
        
        await fs.writeFile(HOSTS_HISTORY_PATH, JSON.stringify(history, null, 2));
    } catch (error) {
        console.error('Error saving host to history:', error);
    }
}

async function loadHostHistory() {
    try {
        const data = await fs.readFile(HOSTS_HISTORY_PATH, 'utf8');
        return JSON.parse(data);
    } catch (error) {
        return [];
    }
}

function extractHostNickname(url) {
    try {
        const hostname = new URL(url).hostname;
        if (hostname === 'localhost' || hostname === '127.0.0.1') {
            return 'Local';
        }
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
        
        await saveHostToHistory(url, hostInfo);
        return { success: true, host: hostInfo };
    } catch (error) {
        const hostInfo = { url, status: 'offline', error: error.message, lastChecked: new Date() };
        hosts.set(url, hostInfo);
        await saveHostToHistory(url, hostInfo);
        return { success: false, error: error.message, host: hostInfo };
    }
}

// Settings management
async function loadSettings() {
    try {
        const data = await fs.readFile(SETTINGS_PATH, 'utf8');
        settings = { ...settings, ...yaml.load(data) };
    } catch (error) {
        await saveSettings();
    }
}

async function saveSettings() {
    try {
        await fs.writeFile(SETTINGS_PATH, yaml.dump(settings));
    } catch (error) {
        console.error('Error saving settings:', error);
    }
}

// File content extraction with language detection
async function extractFileContent(filePath, mimeType, originalName) {
    const content = await fs.readFile(filePath, 'utf8');
    const ext = path.extname(originalName).toLowerCase();
    
    // Language detection based on file extension
    const languageMap = {
        '.js': 'javascript', '.ts': 'typescript', '.jsx': 'javascript', '.tsx': 'typescript',
        '.py': 'python', '.java': 'java', '.c': 'c', '.cpp': 'cpp', '.h': 'c', '.hpp': 'cpp',
        '.html': 'html', '.css': 'css', '.scss': 'scss', '.sass': 'sass',
        '.json': 'json', '.xml': 'xml', '.yaml': 'yaml', '.yml': 'yaml',
        '.md': 'markdown', '.sh': 'bash', '.bash': 'bash', '.sql': 'sql',
        '.go': 'go', '.rs': 'rust', '.php': 'php', '.rb': 'ruby',
        '.swift': 'swift', '.kt': 'kotlin', '.scala': 'scala', '.r': 'r'
    };
    
    const language = languageMap[ext] || 'text';
    
    return {
        filename: originalName,
        type: 'code',
        language,
        content,
        size: content.length,
        lines: content.split('\n').length
    };
}

// Enhanced chat message saving with code context
async function saveChatMessage(sessionId, role, content, model = null, host = null, filePath = null, lineNumber = null) {
    return new Promise((resolve, reject) => {
        db.run(
            `INSERT INTO code_sessions (session_id, role, content, model, host, file_path, line_number) 
             VALUES (?, ?, ?, ?, ?, ?, ?)`,
            [sessionId, role, content, model, host, filePath, lineNumber],
            function(err) {
                if (err) reject(err);
                else resolve(this.lastID);
            }
        );
    });
}

// Code-focused response generation
async function generateCodeResponse(model, prompt, codeContext = null, promptType = 'code_analyzer') {
    const systemPrompt = CODE_SYSTEM_PROMPTS[promptType] || CODE_SYSTEM_PROMPTS.code_analyzer;
    
    let enhancedPrompt = prompt;
    if (codeContext) {
        enhancedPrompt = `Context: ${codeContext.filename} (${codeContext.language}, ${codeContext.lines} lines)

Code:
\`\`\`${codeContext.language}
${codeContext.content}
\`\`\`

Question: ${prompt}`;
    }
    
    const messages = [
        { role: 'system', content: systemPrompt },
        { role: 'user', content: enhancedPrompt }
    ];
    
    try {
        const response = await axios.post(`${model.host}/api/chat`, {
            model: model.name,
            messages,
            stream: false,
            options: {
                temperature: 0.1, // Lower temperature for more precise code analysis
                top_p: 0.9,
                num_ctx: 8192 // Larger context for code
            }
        }, { timeout: 300000 });
        
        return {
            model: model.name,
            host: model.host,
            response: response.data.message.content,
            promptType
        };
    } catch (error) {
        return {
            model: model.name,
            host: model.host,
            error: `Error: ${error.response?.data?.error || error.message}`,
            promptType
        };
    }
}

// API Endpoints
app.post('/api/hosts', async (req, res) => {
    const { url } = req.body;
    if (!url || hosts.has(url)) return res.status(400).json({ error: 'Invalid or duplicate host' });
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
        if (host.status === 'online' && host.models) {
            host.models.forEach(model => {
                models.push({ name: model.name, host: url, size: model.size });
            });
        }
    }
    res.json(models);
});

// Code-specific endpoints
app.post('/api/analyze-code', upload.single('file'), async (req, res) => {
    const { models: selectedModels, prompt, sessionId, promptType = 'code_analyzer' } = req.body;
    const models = JSON.parse(selectedModels);
    
    let codeContext = null;
    if (req.file) {
        try {
            codeContext = await extractFileContent(req.file.path, req.file.mimetype, req.file.originalname);
            await fs.unlink(req.file.path); // Clean up
        } catch (error) {
            return res.status(400).json({ error: 'Failed to process code file' });
        }
    }
    
    await saveChatMessage(sessionId, 'user', prompt, null, null, codeContext?.filename);
    
    try {
        const responses = await Promise.allSettled(
            models.map(model => generateCodeResponse(model, prompt, codeContext, promptType))
        );
        
        const results = responses.map((r, i) => 
            r.status === 'fulfilled' ? r.value : {
                model: models[i].name,
                host: models[i].host,
                error: r.reason.message,
                promptType
            }
        );
        
        // Save responses
        for (const result of results) {
            if (!result.error) {
                await saveChatMessage(sessionId, 'assistant', result.response, result.model, result.host);
            }
        }
        
        res.json({ responses: results });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

app.get('/api/sessions/:sessionId', (req, res) => {
    db.all(
        `SELECT * FROM code_sessions WHERE session_id = ? ORDER BY timestamp`,
        [req.params.sessionId],
        (err, rows) => {
            if (err) return res.status(500).json({ error: err.message });
            res.json(rows);
        }
    );
});

app.get('/api/sessions', (req, res) => {
    db.all(
        `SELECT session_id, MAX(timestamp) as last_message 
         FROM code_sessions 
         GROUP BY session_id 
         ORDER BY last_message DESC 
         LIMIT 50`,
        (err, rows) => {
            if (err) return res.status(500).json({ error: err.message });
            res.json(rows);
        }
    );
});

// Settings endpoints
app.get('/api/settings', (req, res) => res.json(settings));

app.post('/api/settings', async (req, res) => {
    settings = { ...settings, ...req.body };
    await saveSettings();
    res.json({ success: true });
});

// VS Code integration endpoint
app.post('/api/vscode/open-file', (req, res) => {
    const { filePath, lineNumber } = req.body;
    const { spawn } = require('child_process');
    
    try {
        const args = lineNumber ? [`${filePath}:${lineNumber}`] : [filePath];
        spawn('code', args, { detached: true });
        res.json({ success: true });
    } catch (error) {
        res.status(500).json({ error: 'Failed to open VS Code' });
    }
});

// File system endpoints for workspace browsing
app.get('/api/workspace/files', async (req, res) => {
    const { dir = settings.workspace_path } = req.query;
    
    try {
        const files = await fs.readdir(dir, { withFileTypes: true });
        const fileList = files.map(file => ({
            name: file.name,
            path: path.join(dir, file.name),
            isDirectory: file.isDirectory(),
            isFile: file.isFile()
        }));
        
        res.json(fileList);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

app.get('/api/workspace/file-content', async (req, res) => {
    const { filePath } = req.query;
    
    try {
        const content = await fs.readFile(filePath, 'utf8');
        const ext = path.extname(filePath).toLowerCase();
        const languageMap = {
            '.js': 'javascript', '.ts': 'typescript', '.py': 'python',
            '.java': 'java', '.c': 'c', '.cpp': 'cpp', '.html': 'html',
            '.css': 'css', '.json': 'json', '.xml': 'xml', '.md': 'markdown'
        };
        
        res.json({
            content,
            language: languageMap[ext] || 'text',
            path: filePath
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Health check
app.get('/api/health', (req, res) => 
    res.json({ 
        status: 'running', 
        hosts: hosts.size, 
        mode: 'code-focused',
        timestamp: new Date() 
    })
);

// Initialize
async function initialize() {
    await loadSettings();
    await loadHostsFromFile();
    
    // Periodic host health check
    setInterval(async () => {
        for (const [url, host] of hosts) {
            try {
                const response = await axios.get(`${url}/api/tags`, { timeout: 3000 });
                host.status = 'online';
                host.models = response.data.models || [];
                host.lastChecked = new Date();
            } catch (error) {
                host.status = 'offline';
                host.error = error.message;
                host.lastChecked = new Date();
            }
        }
    }, 30000); // Check every 30 seconds
}

app.listen(PORT, () => {
    console.log(`🚀 Multi-Ollama Code-Focused Interface running on http://localhost:${PORT}`);
    initialize();
});
EOF
print_success "server.js created"

# Create public directory and index.html
print_info "Creating public directory and interface..."
mkdir -p public

cat > public/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Multi-Ollama Code Interface</title>
    <script src="https://cdn.jsdelivr.net/npm/marked@4.0.0/marked.min.js"></script>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/themes/prism-tomorrow.min.css">
    <script src="https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/prism.min.js"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/components/prism-javascript.min.js"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/components/prism-python.min.js"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/components/prism-java.min.js"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/components/prism-c.min.js"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/components/prism-cpp.min.js"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/components/prism-typescript.min.js"></script>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { 
            font-family: 'Consolas', 'Monaco', 'SF Mono', monospace; 
            background: #0a0a0a; 
            color: #e0e0e0; 
            height: 100vh; 
            overflow: hidden; 
            font-size: 14px;
        }
        .container { display: flex; height: 100vh; }
        
        /* Sidebar */
        .sidebar { 
            width: 320px; 
            background: #1e1e1e; 
            border-right: 1px solid #333; 
            padding: 16px; 
            overflow-y: auto; 
            display: flex; 
            flex-direction: column;
            scrollbar-width: thin; 
            scrollbar-color: #333 #1e1e1e;
        }
        .sidebar::-webkit-scrollbar { width: 8px; }
        .sidebar::-webkit-scrollbar-track { background: #1e1e1e; }
        .sidebar::-webkit-scrollbar-thumb { background: #333; border-radius: 4px; }
        .sidebar::-webkit-scrollbar-thumb:hover { background: #555; }
        
        .sidebar h2 { 
            color: #fff; 
            margin-bottom: 12px; 
            font-size: 16px; 
            font-weight: 600;
            border-bottom: 1px solid #333;
            padding-bottom: 8px;
        }
        .sidebar section { margin-bottom: 24px; }
        
        /* Code-focused input styling */
        .host-input { display: flex; gap: 8px; margin-bottom: 12px; flex-wrap: wrap; }
        .host-input input { 
            flex: 1; 
            min-width: 120px; 
            padding: 8px 12px; 
            background: #2d2d2d; 
            border: 1px solid #404040; 
            color: #e0e0e0; 
            border-radius: 4px;
            font-family: 'SF Mono', 'Monaco', 'Consolas', monospace;
            font-size: 13px;
        }
        .host-input input:focus { outline: none; border-color: #007acc; }
        .host-input button { 
            padding: 8px 12px; 
            background: #007acc; 
            color: white; 
            border: none; 
            border-radius: 4px; 
            cursor: pointer; 
            transition: background 0.2s; 
            flex-shrink: 0;
            font-size: 12px;
            font-weight: 500;
        }
        .host-input button:hover { background: #005a9e; }
        .host-input button#historyToggle { background: #6b7280; }
        .host-input button#historyToggle:hover { background: #4b5563; }
        
        .host-history { 
            margin-bottom: 15px; 
            background: #2d2d2d; 
            border: 1px solid #404040; 
            border-radius: 6px; 
            padding: 12px; 
        }
        .host-history h3 { 
            margin: 0 0 10px 0; 
            color: #e0e0e0; 
            font-size: 13px; 
            font-weight: 500;
        }
        .host-history-item { 
            padding: 8px; 
            background: #1e1e1e; 
            border-radius: 4px; 
            margin-bottom: 6px; 
            cursor: pointer; 
            transition: background 0.2s; 
        }
        .host-history-item:hover { background: #333; }
        .host-history-item:last-child { margin-bottom: 0; }
        .host-history-url { 
            color: #007acc; 
            font-weight: 500; 
            font-size: 12px; 
            margin-bottom: 4px; 
        }
        .host-history-meta { 
            font-size: 11px; 
            color: #9ca3af; 
            display: flex; 
            justify-content: space-between; 
        }
        
        .host-list { margin-top: 10px; }
        .host-item { 
            padding: 10px; 
            background: #2d2d2d; 
            border-radius: 4px; 
            margin-bottom: 8px; 
            display: flex; 
            justify-content: space-between; 
            align-items: center; 
        }
        .host-item.offline { border-left: 3px solid #dc2626; }
        .host-item.online { border-left: 3px solid #10b981; }
        .host-status { 
            display: inline-block; 
            width: 8px; 
            height: 8px; 
            border-radius: 50%; 
            margin-right: 8px; 
        }
        .host-status.online { background: #10b981; }
        .host-status.offline { background: #dc2626; }
        
        .model-list { max-height: 250px; overflow-y: auto; }
        .model-item { 
            padding: 8px 10px; 
            background: #2d2d2d; 
            border-radius: 4px; 
            margin-bottom: 6px; 
            cursor: pointer; 
            transition: all 0.2s; 
            display: flex; 
            justify-content: space-between; 
            align-items: center;
            font-size: 13px;
        }
        .model-item:hover { background: #404040; }
        .model-item.selected { background: #007acc; color: white; }
        .model-host { font-size: 11px; color: #888; }
        
        /* Prompt type selector */
        .prompt-type-section select {
            width: 100%;
            padding: 8px 12px;
            background: #2d2d2d;
            border: 1px solid #404040;
            color: #e0e0e0;
            border-radius: 4px;
            font-family: inherit;
            font-size: 13px;
            margin-bottom: 8px;
        }
        .prompt-type-section select:focus { outline: none; border-color: #007acc; }
        
        .selected-models { 
            margin-top: auto; 
            padding: 15px; 
            background: #2d2d2d; 
            border-radius: 8px; 
        }
        .selected-models h3 { 
            font-size: 13px; 
            margin-bottom: 10px; 
            color: #10b981; 
            font-weight: 500;
        }
        .selected-model-tag { 
            display: inline-block; 
            padding: 4px 8px; 
            background: #007acc; 
            border-radius: 4px; 
            margin: 4px; 
            font-size: 11px; 
            cursor: pointer; 
            transition: background 0.2s; 
        }
        .selected-model-tag:hover { background: #dc2626; }
        
        /* Main content area */
        .main { flex: 1; display: flex; flex-direction: column; }
        .chat-header { 
            padding: 16px 20px; 
            background: #1e1e1e; 
            border-bottom: 1px solid #333; 
            display: flex; 
            justify-content: space-between; 
            align-items: center; 
        }
        .chat-header h1 { 
            color: #fff; 
            font-size: 18px; 
            font-weight: 600;
        }
        .session-controls { display: flex; gap: 10px; align-items: center; }
        .session-controls select { 
            padding: 8px 12px; 
            background: #2d2d2d; 
            border: 1px solid #404040; 
            color: #e0e0e0; 
            border-radius: 4px; 
            cursor: pointer;
            font-size: 13px;
        }
        .session-controls button { 
            padding: 8px 12px; 
            background: #007acc; 
            color: white; 
            border: none; 
            border-radius: 4px; 
            cursor: pointer; 
            font-size: 13px; 
            transition: background 0.2s; 
        }
        .session-controls button:hover { background: #005a9e; }
        
        .chat-messages { 
            flex: 1; 
            padding: 20px; 
            overflow-y: auto; 
            background: #0a0a0a; 
        }
        .message { 
            margin-bottom: 20px; 
            animation: fadeIn 0.3s ease-in; 
        }
        @keyframes fadeIn { 
            from { opacity: 0; transform: translateY(10px); } 
            to { opacity: 1; transform: translateY(0); } 
        }
        .message.user { text-align: right; }
        .message-content { 
            display: inline-block; 
            padding: 12px 16px; 
            border-radius: 8px; 
            max-width: 85%; 
            word-wrap: break-word; 
            text-align: left; 
            line-height: 1.5;
            font-size: 14px;
        }
        .message.user .message-content { 
            background: #007acc; 
            color: white; 
        }
        .message.assistant .message-content { 
            background: #1e1e1e; 
            border: 1px solid #333; 
        }
        .message.assistant.error .message-content { 
            background: rgba(220, 38, 38, 0.1); 
            border-color: #dc2626; 
        }
        .model-tag { 
            font-size: 11px; 
            color: #888; 
            margin-bottom: 6px; 
            font-weight: 500;
            display: flex;
            align-items: center;
            gap: 8px;
        }
        .prompt-type-indicator {
            background: #007acc;
            color: white;
            padding: 2px 6px;
            border-radius: 3px;
            font-size: 10px;
            text-transform: uppercase;
        }
        
        /* Enhanced code styling */
        .message-content pre {
            background: #1a1a1a !important;
            border: 1px solid #333 !important;
            border-radius: 6px !important;
            padding: 16px !important;
            overflow-x: auto !important;
            margin: 12px 0 !important;
        }
        .message-content code {
            background: #2d2d2d !important;
            color: #e0e0e0 !important;
            padding: 2px 6px !important;
            border-radius: 3px !important;
            font-family: 'SF Mono', 'Monaco', 'Consolas', monospace !important;
            font-size: 13px !important;
        }
        .message-content pre code {
            background: none !important;
            padding: 0 !important;
        }
        
        /* Chat input */
        .chat-input { 
            padding: 20px; 
            background: #1e1e1e; 
            border-top: 1px solid #333; 
        }
        .input-wrapper { 
            display: flex; 
            gap: 12px; 
            align-items: flex-end; 
        }
        .message-input-container { 
            flex: 1; 
            display: flex; 
            flex-direction: column; 
            gap: 10px; 
        }
        .file-attachment { 
            display: flex; 
            align-items: center; 
            gap: 10px; 
            padding: 8px 12px; 
            background: #2d2d2d; 
            border: 1px solid #007acc; 
            border-radius: 6px; 
            font-size: 13px; 
        }
        .file-attachment .file-name { 
            flex: 1; 
            color: #007acc; 
            overflow: hidden; 
            text-overflow: ellipsis; 
            white-space: nowrap; 
            font-family: 'SF Mono', 'Monaco', 'Consolas', monospace;
        }
        .file-attachment .file-info { 
            color: #888; 
            font-size: 11px; 
        }
        .file-attachment .remove-file { 
            background: transparent; 
            color: #dc2626; 
            border: none; 
            font-size: 16px; 
            cursor: pointer; 
            padding: 0 5px; 
        }
        .file-attachment .remove-file:hover { color: #ef4444; }
        
        .chat-input textarea { 
            width: 100%; 
            padding: 12px; 
            background: #2d2d2d; 
            border: 1px solid #404040; 
            color: #e0e0e0; 
            border-radius: 6px; 
            resize: none; 
            font-family: 'SF Mono', 'Monaco', 'Consolas', monospace; 
            font-size: 14px; 
            min-height: 80px;
        }
        .chat-input textarea:focus { outline: none; border-color: #007acc; }
        
        .action-buttons { display: flex; gap: 10px; }
        .file-input-wrapper { position: relative; overflow: hidden; display: inline-block; }
        .file-input-wrapper input[type=file] { position: absolute; left: -9999px; }
        .file-input-label { 
            padding: 12px 16px; 
            background: #404040; 
            color: white; 
            border: none; 
            border-radius: 6px; 
            cursor: pointer; 
            transition: background 0.2s; 
            font-weight: 500;
            font-size: 13px;
        }
        .file-input-label:hover { background: #555; }
        
        .chat-input button { 
            padding: 12px 20px; 
            background: #007acc; 
            color: white; 
            border: none; 
            border-radius: 6px; 
            cursor: pointer; 
            transition: background 0.2s; 
            font-weight: 500;
            font-size: 13px;
        }
        .chat-input button:hover:not(:disabled) { background: #005a9e; }
        .chat-input button:disabled { opacity: 0.5; cursor: not-allowed; }
        
        /* VS Code integration button */
        .vscode-button {
            background: #007acc !important;
            color: white;
            border: none;
            padding: 4px 8px;
            border-radius: 3px;
            cursor: pointer;
            font-size: 11px;
            margin-left: 8px;
            transition: background 0.2s;
        }
        .vscode-button:hover {
            background: #005a9e !important;
        }
        
        /* Loading indicator */
        .loading { display: flex; justify-content: center; padding: 20px; }
        .spinner { 
            width: 20px; 
            height: 20px; 
            border: 2px solid #333; 
            border-top: 2px solid #007acc; 
            border-radius: 50%; 
            animation: spin 1s linear infinite; 
        }
        @keyframes spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }
        
        /* File explorer */
        .file-explorer {
            max-height: 200px;
            overflow-y: auto;
            border: 1px solid #404040;
            border-radius: 4px;
            background: #2d2d2d;
        }
        .file-item {
            padding: 6px 10px;
            cursor: pointer;
            border-bottom: 1px solid #404040;
            font-size: 12px;
            font-family: 'SF Mono', 'Monaco', 'Consolas', monospace;
        }
        .file-item:hover {
            background: #404040;
        }
        .file-item.directory {
            color: #007acc;
        }
        .file-item.file {
            color: #e0e0e0;
        }
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
            
            <section class="prompt-type-section">
                <h2>Analysis Type</h2>
                <select id="promptType">
                    <option value="code_analyzer">Code Analyzer</option>
                    <option value="debugger">Debugger</option>
                    <option value="code_reviewer">Code Reviewer</option>
                    <option value="architecture_advisor">Architecture Advisor</option>
                </select>
            </section>
            
            <div class="selected-models">
                <h3>Active Models</h3>
                <div id="selectedModels"></div>
            </div>
        </div>
        
        <div class="main">
            <div class="chat-header">
                <h1>Multi-LLM Code Interface</h1>
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
                            <span>📄</span>
                            <span class="file-name" id="fileName"></span>
                            <span class="file-info" id="fileInfo"></span>
                            <button class="remove-file" onclick="removeFile()">×</button>
                        </div>
                        <textarea 
                            id="messageInput"
                            placeholder="Describe your code analysis needs, paste code, or ask for help with debugging..."
                            onkeydown="handleKeyPress(event)"
                        ></textarea>
                    </div>
                    
                    <div class="action-buttons">
                        <div class="file-input-wrapper">
                            <input type="file" id="fileInput" onchange="handleFileSelect(event)" 
                                   accept=".js,.ts,.py,.java,.c,.cpp,.h,.hpp,.html,.css,.json,.xml,.yaml,.yml,.md,.txt,.sh,.bash,.sql,.go,.rs,.php,.rb,.swift,.kt,.scala,.r" />
                            <label for="fileInput" class="file-input-label">📁 Code File</label>
                        </div>
                        <button id="sendButton" onclick="sendMessage()">Analyze</button>
                    </div>
                </div>
            </div>
        </div>
    </div>
    
    <script>
        let hosts = [], models = [], selectedModels = [], attachedFile = null, currentSessionId = null, isLoading = false;

        document.addEventListener('DOMContentLoaded', () => {
            loadInitialHosts();
            loadSessionList();
            handleNewSession();
            marked.setOptions({ 
                breaks: true, 
                gfm: true,
                highlight: function(code, language) {
                    if (Prism.languages[language]) {
                        return Prism.highlight(code, Prism.languages[language], language);
                    }
                    return code;
                }
            });
        });

        async function sendMessage() {
            const input = document.getElementById('messageInput');
            const prompt = input.value.trim();
            const promptType = document.getElementById('promptType').value;
            
            if ((!prompt && !attachedFile) || !selectedModels.length || isLoading) return;
            
            isLoading = true;
            input.value = '';
            document.getElementById('sendButton').disabled = true;
            
            addMessageToUI('user', prompt, { 
                file_name: attachedFile?.filename,
                file_info: attachedFile ? `${attachedFile.language}, ${attachedFile.lines} lines` : null
            });
            showLoadingIndicator(true);

            try {
                const formData = new FormData();
                formData.append('models', JSON.stringify(selectedModels));
                formData.append('prompt', prompt || 'Please analyze this code file');
                formData.append('sessionId', currentSessionId);
                formData.append('promptType', promptType);
                
                if (attachedFile && attachedFile.file) {
                    formData.append('file', attachedFile.file);
                }

                const response = await fetch('/api/analyze-code', {
                    method: 'POST',
                    body: formData
                });

                showLoadingIndicator(false);
                if (!response.ok) throw await response.json();
                
                const data = await response.json();
                data.responses.forEach(r => addMessageToUI('assistant', r.error || r.response, r));
                
            } catch (error) {
                console.error(error);
                addMessageToUI('assistant', `Error: ${error.message || error.error}`, { error: true });
            } finally {
                removeFile();
                isLoading = false;
                document.getElementById('sendButton').disabled = false;
                input.focus();
            }
        }

        async function loadInitialHosts() {
            try {
                hosts = await (await fetch('/api/hosts')).json();
                renderHosts();
                await updateModels();
            } catch (e) {
                console.error(e);
            }
        }

        async function addHost() {
            try {
                const url = document.getElementById('hostInput').value.trim();
                if (!url) return;
                
                const response = await fetch('/api/hosts', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ url })
                });
                
                if (!response.ok) {
                    const error = await response.json();
                    throw new Error(error.error || 'Failed to add host');
                }
                
                document.getElementById('hostInput').value = '';
                await loadInitialHosts();
            } catch (e) {
                alert(e.message);
            }
        }
        
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
            document.getElementById('hostHistory').style.display = 'none';
            document.getElementById('historyToggle').textContent = 'History';
        }
        
        function formatActualTime(isoString) {
            const date = new Date(isoString);
            return date.toLocaleString();
        }

        async function removeHost(url) {
            if (confirm(`Remove ${url}?`)) {
                await fetch(`/api/hosts/${encodeURIComponent(url)}`, { method: 'DELETE' });
                await loadInitialHosts();
            }
        }

        async function updateModels() {
            try {
                models = await (await fetch('/api/models')).json();
                renderModels();
            } catch (e) {
                console.error(e);
            }
        }

        function toggleModel(name, host) {
            selectedModels = selectedModels.some(m => m.name === name && m.host === host)
                ? selectedModels.filter(m => !(m.name === name && m.host === host))
                : [...selectedModels, { name, host }];
            renderSelectedModels();
            renderModels();
        }

        function handleNewSession() {
            currentSessionId = `session_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
            document.getElementById('chatMessages').innerHTML = '';
            document.getElementById('sessionSelect').value = '';
            removeFile();
        }

        async function loadSession() {
            const id = document.getElementById('sessionSelect').value;
            if (!id) return handleNewSession();
            
            currentSessionId = id;
            try {
                document.getElementById('chatMessages').innerHTML = '';
                const messages = await (await fetch(`/api/sessions/${id}`)).json();
                messages.forEach(m => addMessageToUI(m.role, m.content, m));
            } catch (e) {
                alert(e.message);
            }
        }

        async function loadSessionList() {
            try {
                const select = document.getElementById('sessionSelect');
                const current = select.value;
                select.innerHTML = '<option value="">New Session</option>';
                
                const sessions = await (await fetch('/api/sessions')).json();
                sessions.forEach(s => {
                    const o = document.createElement('option');
                    o.value = s.session_id;
                    o.textContent = new Date(s.last_message).toLocaleString();
                    select.appendChild(o);
                });
                
                if (current) select.value = current;
            } catch (e) {
                console.error(e);
            }
        }

        async function handleFileSelect(e) {
            const file = e.target.files[0];
            if (!file || file.size > 100 * 1024 * 1024) {
                if (file) alert('Max 100MB for code files');
                e.target.value = '';
                return;
            }

            const ext = file.name.toLowerCase().substring(file.name.lastIndexOf('.'));
            const languageMap = {
                '.js': 'JavaScript', '.ts': 'TypeScript', '.py': 'Python',
                '.java': 'Java', '.c': 'C', '.cpp': 'C++', '.h': 'C Header',
                '.hpp': 'C++ Header', '.html': 'HTML', '.css': 'CSS',
                '.json': 'JSON', '.xml': 'XML', '.yaml': 'YAML', '.yml': 'YAML',
                '.md': 'Markdown', '.sh': 'Shell', '.sql': 'SQL',
                '.go': 'Go', '.rs': 'Rust', '.php': 'PHP', '.rb': 'Ruby'
            };

            attachedFile = {
                file: file,
                filename: file.name,
                language: languageMap[ext] || 'Text',
                size: file.size,
                lines: null // Will be calculated server-side
            };

            document.getElementById('fileName').textContent = file.name;
            document.getElementById('fileInfo').textContent = `${attachedFile.language} • ${(file.size / 1024).toFixed(1)}KB`;
            document.getElementById('fileAttachment').style.display = 'flex';
            document.getElementById('messageInput').focus();
            
            e.target.value = '';
        }

        function removeFile() {
            attachedFile = null;
            document.getElementById('fileInput').value = '';
            document.getElementById('fileAttachment').style.display = 'none';
        }

        function addMessageToUI(role, content, details = {}) {
            const c = document.getElementById('chatMessages');
            const m = document.createElement('div');
            m.className = `message ${role} ${details.error ? 'error' : ''}`;
            
            let messageHTML = '';
            
            // Add file preview for user messages
            if (details.file_name && role === 'user') {
                messageHTML += `<div class="file-preview">📄 ${details.file_name}`;
                if (details.file_info) {
                    messageHTML += ` • ${details.file_info}`;
                }
                messageHTML += '</div>';
            }
            
            // Add model tag for assistant messages
            if (details.model && role === 'assistant') {
                messageHTML += `<div class="model-tag">
                    ${details.model}${details.host ? ' @ ' + new URL(details.host).hostname : ''}
                    ${details.promptType ? `<span class="prompt-type-indicator">${details.promptType.replace('_', ' ')}</span>` : ''}
                </div>`;
            }
            
            // Add message content with enhanced markdown and code highlighting
            messageHTML += `<div class="message-content">${details.error ? content : marked.parse(content || '')}</div>`;
            
            m.innerHTML = messageHTML;
            c.appendChild(m);
            c.scrollTop = c.scrollHeight;
            
            // Re-highlight code blocks
            Prism.highlightAllUnder(m);
            
            if (role === 'assistant') setTimeout(loadSessionList, 1000);
        }

        function showLoadingIndicator(show) {
            const c = document.getElementById('chatMessages');
            let l = document.getElementById('loading-indicator');
            if (show && !l) {
                l = document.createElement('div');
                l.id = 'loading-indicator';
                l.className = 'loading';
                l.innerHTML = '<div class="spinner"></div>';
                c.appendChild(l);
                c.scrollTop = c.scrollHeight;
            } else if (!show && l) {
                l.remove();
            }
        }

        function renderHosts() {
            document.getElementById('hostList').innerHTML = hosts.map(h =>
                `<div class="host-item ${h.status}">
                    <div><span class="host-status ${h.status}"></span>${h.url}</div>
                    <button onclick="removeHost('${h.url}')" style="background: #dc2626; color: white; border: none; border-radius: 4px; padding: 4px 8px; cursor: pointer; font-size: 11px;">×</button>
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

        function handleKeyPress(e) {
            if (e.key === 'Enter' && !e.shiftKey) {
                e.preventDefault();
                sendMessage();
            }
        }

        // VS Code integration
        function openInVSCode(filePath, lineNumber = null) {
            fetch('/api/vscode/open-file', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ filePath, lineNumber })
            }).catch(err => console.error('Failed to open VS Code:', err));
        }
    </script>
</body>
</html>
EOF
print_success "public/index.html created"

# Create uninstall script
print_info "Creating uninstall script..."
cat > uninstall.sh << 'EOF'
#!/bin/bash
print_info() { echo -e "\033[34mℹ $1\033[0m"; }
print_success() { echo -e "\033[32m✓ $1\033[0m"; }

print_info "Stopping Multi-Ollama Code Interface service..."
sudo systemctl stop multi-ollama-code 2>/dev/null || true
sudo systemctl disable multi-ollama-code 2>/dev/null || true
sudo rm -f /etc/systemd/system/multi-ollama-code.service
sudo systemctl daemon-reload

print_info "Removing installation directory..."
rm -rf ~/multi-ollama-code-server

print_success "Multi-Ollama Code Interface uninstalled successfully"
EOF
chmod +x uninstall.sh
print_success "uninstall.sh created"

# Create systemd service
print_info "Creating systemd service..."
sudo tee /etc/systemd/system/multi-ollama-code.service > /dev/null << EOF
[Unit]
Description=Multi-Ollama Code-Focused Interface
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=10
Environment=NODE_ENV=production
Environment=PORT=3001

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the service
print_info "Enabling and starting the service..."
sudo systemctl daemon-reload
sudo systemctl enable multi-ollama-code
sudo systemctl start multi-ollama-code

# Wait a moment for the service to start
sleep 3

# Check service status
if sudo systemctl is-active --quiet multi-ollama-code; then
    print_success "Multi-Ollama Code Interface is running successfully!"
    print_info "Access the interface at: http://localhost:3001"
    print_info "Service status: sudo systemctl status multi-ollama-code"
    print_info "View logs: sudo journalctl -u multi-ollama-code -f"
    print_info "To uninstall: bash $INSTALL_DIR/uninstall.sh"
else
    print_error "Service failed to start. Check logs with: sudo journalctl -u multi-ollama-code -f"
    exit 1
fi

print_success "🎉 Multi-Ollama Code-Focused Interface deployment completed!"
print_info "Features included:"
print_info "  • Code-focused analysis prompts (Analyzer, Debugger, Reviewer, Architect)"
print_info "  • Syntax highlighting with Prism.js"
print_info "  • Enhanced file handling for 20+ programming languages"
print_info "  • VS Code integration capabilities"
print_info "  • Larger context windows and lower temperature for precise code analysis"
print_info "  • Enhanced error handling and debugging support"
EOF

chmod +x deploy-code-focused.sh
print_success "Created deploy-code-focused.sh"

<function_calls>
<invoke name="TodoWrite">
<parameter name="todos">[{"id": "1", "content": "Create new deployment script with code-focused interface", "status": "completed", "priority": "high"}, {"id": "2", "content": "Design Claude Code-style system prompts for coding analysis", "status": "completed", "priority": "high"}, {"id": "3", "content": "Add VS Code integration capabilities", "status": "completed", "priority": "high"}, {"id": "4", "content": "Implement syntax highlighting and code execution features", "status": "completed", "priority": "medium"}]