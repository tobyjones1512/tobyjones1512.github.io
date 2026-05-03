#!/usr/bin/env python3
"""
Simple Python HTTP server for testing the Toby Jones website locally.
Run with: python3 server.py
Then visit: http://localhost:8000
"""

import http.server
import socketserver
import os

class MyHTTPRequestHandler(http.server.SimpleHTTPRequestHandler):
    # Add CORS headers for local testing
    def end_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        super().end_headers()
    
    # Handle OPTIONS requests for CORS
    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()

    # Set proper MIME types
    extensions_map = {
        '.html': 'text/html',
        '.css': 'text/css',
        '.js': 'application/javascript',
        '.json': 'application/json',
        '.png': 'image/png',
        '.jpg': 'image/jpeg',
        '.jpeg': 'image/jpeg',
        '.gif': 'image/gif',
        '.svg': 'image/svg+xml',
        '.ico': 'image/x-icon',
        '.pdf': 'application/pdf',
        '.zip': 'application/zip',
        '.mp4': 'video/mp4',
        '.woff': 'font/woff',
        '.woff2': 'font/woff2',
        '.ttf': 'font/ttf',
        '.eot': 'application/vnd.ms-fontobject',
    }

if __name__ == '__main__':
    # Change to the directory containing this script
    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    
    PORT = 8000
    handler = MyHTTPRequestHandler
    
    with socketserver.TCPServer(("", PORT), handler) as httpd:
        print(f"""
╔══════════════════════════════════════════════════════════════════════╗
║                    Toby Jones Website Server                     ║
╠══════════════════════════════════════════════════════════════════════╣
║                                                              ║
║  Server running at:                                          ║
║  → http://localhost:{PORT}                                  ║
║                                                              ║
║  Press Ctrl+C to stop the server                           ║
║                                                              ║
╚══════════════════════════════════════════════════════════════════════╝
        """)
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\n\nServer stopped.")
