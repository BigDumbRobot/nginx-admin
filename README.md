# Nginx Admin

Bring remote performers' video streams into OBS, from the Mac menu bar. No Terminal, no config files.

Each performer streams (from OBS, a Blackmagic ATEM, vMix, etc.) to your Mac with their own
stream key. Nginx Admin runs the receiving server in Docker, shows who's live and how healthy
their connection is, and lets you add, disable and kick performers with a click. In OBS, each
performer is a Media Source, so switching between them is just a scene change.

- **Status at a glance**: the menu bar icon is green with a count when performers are live,
  orange when the server is ready and waiting, and red when something needs attention.
- **One key per performer**: hard-to-guess keys are created for you, with a ready-to-send setup
  message (server, key, recommended encoder settings). Unknown keys are rejected.
- **Connection health**: live bitrate and a 3-minute graph per performer, with an **Unstable**
  warning when their upload is struggling, before the audience notices.
- **Recovers from stuck sessions**: dead connections are dropped automatically after 10 seconds,
  and **Fresh Restart** clears everything in a few seconds.
- **Notifications** when performers go live or stop, when a stream turns unstable, when an
  unknown key tries to connect, and if the server goes down.
- **Browser dashboard** at `http://localhost:8090` for a second screen.

Requires macOS 14.2 or later (Apple silicon or Intel) and [Docker Desktop](https://www.docker.com/products/docker-desktop/).

## Download

**[Download the latest version](https://github.com/BigDumbRobot/nginx-admin/releases/latest)**:
get the `.dmg` file under *Assets*.

1. Install and open **Docker Desktop** once (accept its prompts). In its settings, turn on
   **Start Docker Desktop when you sign in**.
2. Open the `.dmg` and drag **Nginx Admin** into **Applications**.
3. Open **Nginx Admin** from Applications. The first time, macOS blocks it, because the app isn't
   registered with Apple. To allow it once:
   - **macOS 15 or later**: click **Done** on the warning, then open **System Settings →
     Privacy & Security**, scroll down to *"Nginx Admin" was blocked*, click **Open Anyway** and
     enter your password.
   - **macOS 14**: right-click (or Control-click) the app in Applications, choose **Open**, then
     **Open** again.
4. Look for the video-camera icon in the menu bar and press **Start Server**. The first start
   downloads the server software (about 340 MB), so give it a few minutes.
5. In **Settings**, enter the address performers stream to (e.g. `rtmp://your.address:1935/live`)
   and turn on **Open Nginx Admin at login**.

> Can't see the icon? A full menu bar hides icons behind the camera notch. Hold **⌘** and drag
> other icons out of the menu bar to make room.

The app sets up its server files in `~/Library/Application Support/Nginx Admin` (changeable in
Settings; **Folder** at the bottom of the panel shows it in Finder). Your stream keys and settings
are kept in its `data` folder. Nothing runs or opens a port until you press **Start Server**. To
have the server start whenever the app opens, turn that on in Settings.

**Updating**: download the new `.dmg`, quit Nginx Admin, and drag the new version into
Applications. Your keys and settings are kept. The new server files are applied the next time you
press Start or Fresh Restart. A server file you edited by hand is saved next to the new one as
`<name>.backup-<version>`.

## Uninstall

Open the panel → **Settings** → **Uninstall…**. It removes the server (its containers, network
and the ~1.3 GB Docker downloaded for it), the server folder, the login item and the app's
settings, then moves the app to the Trash. Tick **Keep stream keys** if you might reinstall.
Docker Desktop itself stays installed.

**Don't just drag the app to the Trash.** The server keeps running inside Docker without it, with
port 1935 still open. If you already did, paste this into Terminal to remove what's left:

```sh
docker rm -f rtmp rtmp-admin
docker network rm nginxadmin_default rtmp-server_default 2>/dev/null
docker rmi tiangolo/nginx-rtmp:latest python:3.12-alpine
rm -rf ~/Library/"Application Support/Nginx Admin"
defaults delete io.github.bigdumbrobot.NginxAdmin 2>/dev/null
rm -f ~/Library/Preferences/io.github.bigdumbrobot.NginxAdmin.plist
```

If you had turned on *Open Nginx Admin at login*, also remove it under **System Settings →
General → Login Items**.

### Building it yourself

Needs Xcode command line tools (`xcode-select --install`):

```sh
git clone https://github.com/BigDumbRobot/nginx-admin.git ~/rtmp-server
~/rtmp-server/NginxAdmin/build.sh --install     # build and install to /Applications
~/rtmp-server/NginxAdmin/build.sh --release     # make the .dmg and .zip in NginxAdmin/dist/
```

## Using it

**Add a performer**: Keys tab → type their name → **Add Key** → **Copy Setup Message** and send it.
They set their encoder to:

- Server: `rtmp://your.address:1935/live`
- Stream key: the key you sent them

**In OBS**: add a **Media Source** per performer, uncheck *Local File*, set the input to
`rtmp://localhost:1935/live/<their key>`, and check *Restart playback when source becomes active*.

**During a show**: the Live tab shows each performer's bitrate, resolution, audio, uptime and
whether OBS is pulling their stream. **Kick** disconnects one performer; **Fresh Restart** drops
every connection (handy before a show, or if something is stuck).

## Letting performers reach you

Performers connect to your Mac through your router:

- **Port forwarding**: forward TCP port **1935** to your Mac's local IP address.
- **A stable address** (recommended): home IP addresses change. A free dynamic DNS name from
  [DuckDNS](https://www.duckdns.org) or [No-IP](https://www.noip.com) keeps the address working.

The dashboard (8090) and stat page (8080) only listen on this Mac and are never exposed.

## Recommended performer settings

| | |
|---|---|
| Video | 1080p30 at 4–6 Mbps CBR, or 720p30 at 2.5–4 Mbps |
| Keyframe interval | 2 seconds |
| Audio | AAC, 48 kHz, 128–160 kbps |
| Connection | Wired Ethernet; video bitrate at most ~60% of their measured upload |

## How it works

```
performers ──RTMP :1935──▶ rtmp (nginx-rtmp, 1 worker) ──▶ OBS Media Sources
                                │  on_publish: is this key allowed?
                                ▼
                           rtmp-admin (Python, stdlib only) ◀── Nginx Admin.app
                           keys, activity log, dashboard :8090
```

| File | What it is |
|---|---|
| `compose.yaml` | The two containers. `rtmp-admin` shares `rtmp`'s network, so they talk over 127.0.0.1 |
| `nginx.conf` | RTMP server: one worker, idle-publisher drop, key check on publish |
| `admin/app.py` | Key store, publish authorization, activity log, JSON API, dashboard |
| `admin/static/index.html` | Browser dashboard |
| `stat.xsl` | Styles nginx's raw stat page at `http://localhost:8080` |
| `NginxAdmin/` | The SwiftUI menu bar app (`build.sh` builds it and bundles the files above) |
| `data/` | Created at runtime: `keys.json`, `settings.json`, `events.jsonl`. Not in git |

Notes:

- nginx-rtmp allows one publisher per stream name, so a shared key makes the second person get
  `already publishing`. That's why every performer gets their own key.
- A single nginx worker is deliberate. Multiple workers with `rtmp_auto_push` copy every stream
  between workers and are a known source of instability.
- If the `rtmp` container restarts by itself, `rtmp-admin` notices within 20 seconds and restarts
  too, to rejoin its network.

## License

MIT. See [LICENSE](LICENSE). Uses [nginx-rtmp-module](https://github.com/arut/nginx-rtmp-module)
via the [tiangolo/nginx-rtmp](https://hub.docker.com/r/tiangolo/nginx-rtmp) image (pulled at runtime, not included).
