# Multi-Ollama Web Interface

A powerful web interface for running and comparing multiple Ollama AI models simultaneously. Features real-time streaming, multi-round conversations, file uploads, web search integration, and host connection history.

![Multi-Ollama Interface](https://img.shields.io/badge/version-v13-blue) ![License](https://img.shields.io/badge/license-MIT-green) ![Node.js](https://img.shields.io/badge/node.js-%3E%3D20-brightgreen)

## ✨ Features

### 🚀 Core Functionality
- **Multi-Model Chat**: Query multiple Ollama models simultaneously
- **Real-Time Streaming**: See responses as they're generated
- **Multi-Round Conversations**: Collaborative, debate, Socratic, and panel discussion modes
- **Host Management**: Connect to multiple Ollama instances across your network
- **Connection History**: Quick reconnection to previously used hosts

### 📁 File Support
- **File Uploads**: Support for text, code, images, and documents (up to 50MB)
- **Image Analysis**: Vision model integration for image understanding
- **Code Analysis**: Syntax highlighting and code discussion

### 🔍 Advanced Features
- **Web Search Integration**: DuckDuckGo search for enhanced responses
- **Consensus Generation**: Automatic synthesis of multiple model responses
- **Chat Sessions**: Persistent conversation history with SQLite storage
- **Seed Prompts**: System-wide prompts for consistent model behavior

### 🎨 User Experience
- **Dark Theme Interface**: Professional, modern design
- **Responsive Layout**: Works on desktop and mobile
- **Markdown Support**: Rich text formatting in responses
- **Export Options**: Download conversations in JSON or text format

## 🚀 Quick Start

### Choose Your Linux Distribution

#### Arch Linux
```bash
curl -fsSL https://raw.githubusercontent.com/your-username/multi-ollama-web/main/deploy-arch.sh | bash
```

#### Ubuntu/Debian
```bash
curl -fsSL https://raw.githubusercontent.com/your-username/multi-ollama-web/main/deploy-ubuntu.sh | bash
```

#### Fedora
```bash
curl -fsSL https://raw.githubusercontent.com/your-username/multi-ollama-web/main/deploy-fedora.sh | bash
```

### Manual Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/your-username/multi-ollama-web.git
   cd multi-ollama-web
   ```

2. **Run deployment script**
   ```bash
   # Make executable
   chmod +x deploy-*.sh
   
   # Run for your distribution
   ./deploy-arch.sh     # Arch Linux
   ./deploy-ubuntu.sh   # Ubuntu/Debian  
   ./deploy-fedora.sh   # Fedora
   ```

3. **Access the interface**
   ```
   http://localhost:3000
   ```

## 📋 Requirements

- **Node.js** 20+ (automatically installed)
- **Ollama** (automatically installed)
- **SQLite** (automatically installed)
- **Linux** (Arch, Ubuntu/Debian, or Fedora)
- **Sudo access** (for system service installation)

## 🔧 Configuration

### Adding Remote Hosts

1. Click **"Add"** in the Ollama Hosts section
2. Enter the host URL (e.g., `http://192.168.1.100:11434`)
3. The system will automatically detect available models

### Multi-Round Conversations

1. Set **"Rounds"** to desired number (1-10)
2. Choose conversation **"Mode"**:
   - **Collaborative**: Models build upon each other's responses
   - **Debate**: Models present different perspectives
   - **Socratic**: Models ask probing questions
   - **Panel**: Each model contributes unique viewpoints

### Host History

- All connection attempts are automatically saved
- Click **"History"** to see recent hosts
- One-click reconnection to previous hosts
- Shows connection status and model counts

## 🛠️ Management

### Service Control
```bash
# Check status
sudo systemctl status multi-ollama

# View logs
sudo journalctl -u multi-ollama -f

# Restart service
sudo systemctl restart multi-ollama

# Stop service
sudo systemctl stop multi-ollama
```

### Development Testing
```bash
# Quick redeploy for testing (Arch only)
./test-cycle.sh
```

### Uninstall
```bash
# From installation directory
~/multi-ollama-server/uninstall.sh
```

## 🏗️ Architecture

### Backend (Node.js/Express)
- **RESTful API** for all operations
- **SQLite Database** for chat history and sessions
- **File Processing** with automatic cleanup
- **Multi-Host Management** with health checking
- **Server-Sent Events** for real-time streaming

### Frontend (Vanilla JS)
- **Single-Page Application** with no external dependencies
- **Real-Time Updates** via EventSource API
- **Responsive Design** with CSS Grid/Flexbox
- **Markdown Rendering** with syntax highlighting

### Data Storage
- **Chat History**: SQLite database
- **Host Configuration**: JSON files
- **Settings**: YAML configuration
- **File Uploads**: Temporary processing with auto-cleanup

## 🔒 Security Notes

- **Local Network Use**: Designed for trusted networks
- **No Authentication**: Not intended for public exposure
- **File Processing**: Temporary files are automatically cleaned
- **Host Storage**: Connection history stored locally

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 🐛 Troubleshooting

### Common Issues

**Service won't start**
```bash
# Check Ollama status
sudo systemctl status ollama

# Check logs
sudo journalctl -u multi-ollama -n 50
```

**Models not showing**
- Verify Ollama is running: `ollama list`
- Check host connectivity in the web interface
- Ensure port 11434 is accessible

**File uploads failing**
- Check available disk space
- Verify file size is under 50MB
- Check file type is supported

### Getting Help

- Check the logs: `sudo journalctl -u multi-ollama -f`
- Verify Ollama installation: `ollama --version`
- Test host connectivity: `curl http://localhost:11434/api/tags`

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [Ollama](https://ollama.ai/) for the excellent AI model serving platform
- [Express.js](https://expressjs.com/) for the web framework
- [SQLite](https://sqlite.org/) for embedded database functionality
- [Marked](https://marked.js.org/) for Markdown rendering

## 🔄 Version History

- **v13**: Multi-round streaming, host history, improved context management
- **v12**: File upload enhancements, web search integration
- **v11**: Multi-host support, consensus generation
- **v10**: Initial multi-model support

---

**Made with ❤️ for the AI community**