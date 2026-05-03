# Local Testing Server

## Quick Start

### Mac/Linux:
```bash
./start-server.sh
```
Or:
```bash
python3 server.py
```

### Windows:
Double-click `start-server.bat` or run:
```cmd
start-server.bat
```

## Access the Website

Once running, visit: **http://localhost:8000**

## Pages to Test

- Home: http://localhost:8000/
- Software: http://localhost:8000/software/
- Filmmakers Kit: http://localhost:8000/software/filmmakers-kit/
- Scheduling: http://localhost:8000/software/scheduling/
- Budgeting: http://localhost:8000/software/budgeting/
- Call Sheets: http://localhost:8000/software/call-sheets/
- IPTV Manager: http://localhost:8000/software/IPTV Manager/
- Re-download: http://localhost:8000/software/redownload/

## Purchase Pages (for testing UI)

- Filmmakers Kit: http://localhost:8000/software/filmmakers-kit/purchase/
- Scheduling: http://localhost:8000/software/scheduling/purchase/
- Budgeting: http://localhost:8000/software/budgeting/purchase/
- Call Sheets: http://localhost:8000/software/call-sheets/purchase/
- IPTV Manager: http://localhost:8000/software/IPTV Manager/purchase/

## Notes

- The server includes CORS headers for local API testing
- Make sure to replace `__AUTHORIZENET_API_LOGIN_ID__`, `__AUTHORIZENET_CLIENT_KEY__`, and `__CHARGE_URL__` placeholders with real values for full functionality
- For Authorize.net testing, use sandbox credentials and test card numbers
- Screenshots and icons should be placed in `/assets/` folder
- Download ZIP files should be in `/downloads/` folder

## Stop Server

Press `Ctrl+C` in the terminal window.
