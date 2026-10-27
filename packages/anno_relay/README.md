# anno relay

Forwards the game's state from the phone that runs it to the screen that
shows it. It does nothing else: it does not know the game's messages, keeps no
state past the sockets in a room, and has no dependencies.

```sh
dart run bin/relay.dart --port 8787          # loopback, behind a proxy
dart run bin/relay.dart --host 0.0.0.0        # proxy on another machine
dart compile exe bin/relay.dart -o anno-relay # one file to copy
```

`ANNO_RELAY_PORT` and `ANNO_RELAY_HOST` do the same as the two flags.

## The protocol

One WebSocket per device, one room per screen.

| Request | Means |
| --- | --- |
| `GET /` | Not an upgrade: answers 200 and the number of rooms, for a health check. |
| `GET /?` | The screen: opens a room and is told its code. |
| `GET /?room=ABC123` | The phone: joins that room, refused where there is none. |
| `GET /?room=ABC123&host=1` | The screen coming back to the room it had. |

The server sends `{"t":"room","code":…,"peers":n}` on arrival,
`{"t":"peers","count":n}` to the others whenever that number changes, and
`{"t":"refused","why":…}` before closing a socket it will not serve. Anything
else a device sends is forwarded verbatim to the others in its room and never
back to the sender.

A room dies with its last socket, so a code is good for one evening and not
for next week. The screen can come back to its code because the code only
exists in the room and on the phone - a television that reloads would
otherwise strand the phone that is holding it.

## Why it has to be wss

The page is served over https, and a browser refuses a plain WebSocket from
there. The certificate belongs in front of this: Caddy, or a Cloudflare
tunnel, which also saves the open port.

```
# Caddyfile
anno-relay.example.com {
  reverse_proxy 127.0.0.1:8787
}
```

```ini
# /etc/systemd/system/anno-relay.service
[Unit]
Description=anno relay
After=network.target

[Service]
ExecStart=/usr/local/bin/anno-relay --port 8787
Restart=always
User=anno
# It holds nothing and writes nothing.
ProtectSystem=strict
PrivateTmp=true
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
```

Then build the app with `--dart-define=ANNO_RELAY_URL=wss://anno-relay.example.com/`
(a repository variable `ANNO_RELAY_URL` for the Pages workflow). Without it the
app simply has no second screen in it.
