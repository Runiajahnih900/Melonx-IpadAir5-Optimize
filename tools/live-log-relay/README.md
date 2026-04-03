# Live Log Relay (iPad -> Dev Machine)

This utility receives remote logs from MeloNX iPad builds and prints them live in your terminal.

## 1) Start receiver on your PC

From repository root:

```powershell
python tools/live-log-relay/live_log_server.py --host 0.0.0.0 --port 8787
```

Optional:

```powershell
python tools/live-log-relay/live_log_server.py --host 0.0.0.0 --port 8787 --out logs/live-relay.log
```

## 2) Configure app on iPad

Inside MeloNX settings:
- Enable `Remote Live Logs`
- Set `Remote Log Endpoint` to:

```text
http://<YOUR_PC_LAN_IP>:8787/log
```

Example:

```text
http://192.168.1.20:8787/log
```

## 3) Validate

- Start a game on iPad.
- Logs should appear live in the server terminal.

## Notes

- PC and iPad must be on the same network.
- If firewall blocks traffic, allow inbound TCP on port 8787.
- Endpoint must be `http` or `https`.
