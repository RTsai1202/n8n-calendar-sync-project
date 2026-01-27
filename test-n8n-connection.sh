#!/bin/bash

# Configuration
N8N_URL="https://<your-n8n-domain>"
MCP_TOKEN="<YOUR_N8N_MCP_TOKEN>"

# Check if placeholders are still present
if [[ "$N8N_URL" == "https://<your-n8n-domain>" ]] || [[ "$MCP_TOKEN" == "<YOUR_N8N_MCP_TOKEN>" ]]; then
  echo "Error: Please update the script with your actual n8n Instance URL and MCP Token."
  exit 1
fi

echo "Testing connection to n8n MCP server at $N8N_URL..."

# connection using supergateway
npx -y supergateway \
  --streamableHttp \
  "$N8N_URL/mcp-server/http" \
  --header "Authorization: Bearer $MCP_TOKEN"
