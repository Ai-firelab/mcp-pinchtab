# @aifirelab/mcp-pinchtab

MCP server for [Pinchtab](https://www.npmjs.com/package/pinchtab) -- browser automation for AI agents.

[![npm version](https://img.shields.io/npm/v/@aifirelab/mcp-pinchtab)](https://www.npmjs.com/package/@aifirelab/mcp-pinchtab)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)

## What it does

Bridges Claude (or any MCP client) to a local Pinchtab server for headless browser control. Provides 16 tools for navigating pages, clicking elements, filling forms, taking screenshots, and more.

- Works over stdio -- compatible with Claude Code, Claude Desktop, and any MCP client
- Uses Pinchtab's accessibility-tree snapshots for token-efficient page understanding
- All interactions use element refs (`e0`, `e1`, ...) from snapshots -- no CSS selectors needed

## Prerequisites

- **Node.js 18+**
- **Pinchtab** installed globally:
  ```bash
  npm i -g pinchtab
  ```

## Quick Start -- Claude Code

Add to your `.mcp.json`:

```json
{
  "mcpServers": {
    "pinchtab": {
      "type": "stdio",
      "command": "npx",
      "args": ["@aifirelab/mcp-pinchtab"]
    }
  }
}
```

## Quick Start -- Claude Desktop

Add to your `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "pinchtab": {
      "command": "npx",
      "args": ["@aifirelab/mcp-pinchtab"]
    }
  }
}
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PINCHTAB_URL` | `http://localhost:9867` | Override Pinchtab server URL |
| `PINCHTAB_BIN` | `pinchtab` (from PATH) | Override pinchtab binary path |

## Tools

| Tool | Description | Key Parameters |
|------|-------------|----------------|
| `navigate` | Navigate the browser to a URL | `url`, `newTab?` |
| `snapshot` | Get accessibility tree snapshot of the page (token-efficient) | `interactive?`, `compact?` |
| `click` | Click an element by ref | `ref`, `human?` |
| `type_text` | Type text character by character | `ref`, `text`, `human?` |
| `fill` | Instantly fill a form field (clears existing value) | `ref`, `value` |
| `press` | Press a keyboard key | `key`, `ref?` |
| `select` | Select an option from a dropdown | `ref`, `value` |
| `scroll` | Scroll the page or an element | `direction`, `amount?`, `ref?` |
| `hover` | Hover over an element | `ref` |
| `get_text` | Extract text content of the current page | -- |
| `screenshot` | Take a screenshot (base64 JPEG) | -- |
| `evaluate` | Execute JavaScript in the browser | `expression` |
| `list_tabs` | List all open browser tabs | -- |
| `close_tab` | Close the current or a specific tab | `tabId?` |
| `get_cookies` | Get all cookies for the current page | -- |
| `health` | Check if Pinchtab server is running | -- |

## License

MIT
