# Contributing to Multi-Ollama Web Interface

Thank you for your interest in contributing to Multi-Ollama Web Interface! This document provides guidelines and information for contributors.

## 🚀 Getting Started

### Prerequisites
- Linux environment (Arch, Ubuntu/Debian, or Fedora)
- Node.js 20+
- Git
- Basic knowledge of JavaScript, HTML/CSS, and shell scripting

### Development Setup

1. **Fork and clone the repository**
   ```bash
   git clone https://github.com/your-username/multi-ollama-web.git
   cd multi-ollama-web
   ```

2. **Set up development environment**
   ```bash
   # Run deployment script for your distro
   ./deploy-arch.sh    # or deploy-ubuntu.sh / deploy-fedora.sh
   ```

3. **For development testing**
   ```bash
   # Quick redeploy cycle (Arch only)
   ./test-cycle.sh
   ```

## 📋 Development Guidelines

### Code Style
- **Shell Scripts**: Follow bash best practices, use proper error handling
- **JavaScript**: Use modern ES6+ features, prefer const/let over var
- **HTML/CSS**: Semantic markup, consistent indentation (2 spaces)
- **Comments**: Document complex logic and API endpoints

### File Structure
```
multi-ollama-web/
├── deploy-arch.sh      # Arch Linux deployment
├── deploy-ubuntu.sh    # Ubuntu/Debian deployment  
├── deploy-fedora.sh    # Fedora deployment
├── test-cycle.sh       # Development testing script
├── uninstall.sh        # Cleanup script
├── CLAUDE.md          # AI assistant instructions
├── README.md          # Main documentation
├── CONTRIBUTING.md    # This file
├── LICENSE            # MIT license
└── .gitignore         # Git ignore rules
```

### Adding New Features

1. **Backend Changes** (in deployment scripts):
   - Modify the `server.js` section in deployment scripts
   - Add new API endpoints following REST conventions
   - Update database schema if needed
   - Test with multiple Ollama hosts

2. **Frontend Changes** (in deployment scripts):
   - Modify the `public/index.html` section
   - Follow existing CSS class naming conventions
   - Ensure responsive design compatibility
   - Test with multiple models selected

3. **Configuration Changes**:
   - Update all three deployment scripts consistently
   - Test on each supported distribution
   - Update documentation accordingly

## 🧪 Testing

### Manual Testing
```bash
# Test deployment
./deploy-arch.sh        # (or your distro)

# Test the interface
# 1. Open http://localhost:3000
# 2. Add a remote host
# 3. Select multiple models
# 4. Test multi-round conversations
# 5. Upload a file
# 6. Test web search
# 7. Check host history

# Test cleanup
~/multi-ollama-server/uninstall.sh
```

### Distribution Testing
- Test all three deployment scripts
- Verify service installation and startup
- Check systemd service integration
- Validate package manager compatibility

## 🐛 Bug Reports

When reporting bugs, please include:

1. **Environment Information**:
   - Linux distribution and version
   - Node.js version
   - Ollama version
   - Browser used

2. **Steps to Reproduce**:
   - Detailed steps to trigger the issue
   - Expected vs actual behavior
   - Any error messages

3. **Logs**:
   ```bash
   # Service logs
   sudo journalctl -u multi-ollama -n 50
   
   # Browser console errors
   # (F12 → Console tab)
   ```

## 💡 Feature Requests

We welcome feature suggestions! Please:

1. Check existing issues first
2. Describe the use case clearly
3. Explain why it would benefit users
4. Consider implementation complexity
5. Be open to discussion and iteration

## 🔄 Pull Request Process

1. **Create a feature branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make your changes**
   - Follow coding standards
   - Update documentation if needed
   - Test thoroughly

3. **Commit with clear messages**
   ```bash
   git commit -m "Add: Brief description of feature"
   # or
   git commit -m "Fix: Brief description of bug fix"
   ```

4. **Push to your fork**
   ```bash
   git push origin feature/your-feature-name
   ```

5. **Create Pull Request**
   - Provide clear description
   - Reference any related issues
   - Include testing details

### PR Review Criteria
- Code quality and style consistency
- Functionality works as described
- No breaking changes (or properly documented)
- Documentation updated if needed
- Tested on multiple distributions (when applicable)

## 🏗️ Architecture Notes

### Backend Structure
The backend is embedded within the deployment scripts as a complete Node.js/Express application:

- **Host Management**: Dynamic Ollama instance discovery
- **Model Handling**: Multi-model response aggregation
- **File Processing**: Upload handling with automatic cleanup
- **Database**: SQLite for chat history and sessions
- **Streaming**: Server-Sent Events for real-time responses

### Frontend Structure
Single-page application with vanilla JavaScript:

- **Real-time Updates**: EventSource for live streaming
- **State Management**: Simple global variables
- **UI Components**: Modular functions for rendering
- **Responsive Design**: CSS Grid and Flexbox

### Deployment Strategy
Self-contained deployment scripts that:

- Install all dependencies
- Generate complete application code
- Configure systemd service
- Handle multiple Linux distributions

## 📝 Documentation

When contributing, please update relevant documentation:

- **README.md**: For user-facing changes
- **CONTRIBUTING.md**: For development process changes
- **Code Comments**: For complex logic
- **CLAUDE.md**: For AI assistant context (if needed)

## 🤝 Community

- Be respectful and constructive
- Help others when possible
- Share knowledge and best practices
- Follow the project's code of conduct

## 📞 Getting Help

- **GitHub Issues**: For bugs and feature requests
- **Discussions**: For questions and ideas
- **Code Review**: Ask questions during PR review

Thank you for contributing to Multi-Ollama Web Interface! 🎉