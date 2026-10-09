#!/usr/bin/env python3
"""Dev server for the viewer page: serves IFCPreview/Web and maps /model.ifc to a file of your choice.
Usage: scripts/dev-server.py path/to/model.ifc [port]
Then open http://localhost:<port>/index.html?name=model.ifc&size=<bytes>
"""
import http.server, os, sys, functools

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'IFCPreview', 'Web')
model = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else None
port = int(sys.argv[2]) if len(sys.argv) > 2 else 8765

class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map,
                      '.wasm': 'application/wasm', '.js': 'text/javascript', '.mjs': 'text/javascript'}
    def translate_path(self, path):
        if path.split('?')[0] == '/model.ifc' and model:
            return model
        return super().translate_path(path)
    def end_headers(self):
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()

if model:
    print(f'model: {model} ({os.path.getsize(model)} bytes)')
print(f'http://localhost:{port}/index.html?name={os.path.basename(model) if model else "model.ifc"}&size={os.path.getsize(model) if model else 0}')
http.server.ThreadingHTTPServer(('127.0.0.1', port), functools.partial(Handler, directory=root)).serve_forever()
