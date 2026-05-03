#!/bin/bash
echo "╔═══════════════════════════════════════════════════════╗"
echo "║                    Toby Jones Website Server                     ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo ""
echo "Starting server..."
echo ""
python3 "$(dirname "$0")/server.py"
