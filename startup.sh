#!/bin/bash
set -euo pipefail

APP_DIR="/opt/event-horizon"
APP_USER="root"

apt-get update -y
apt-get install -y python3 python3-venv

mkdir -p "${APP_DIR}"

python3 -m venv "${APP_DIR}/venv"
"${APP_DIR}/venv/bin/pip" install --upgrade pip
"${APP_DIR}/venv/bin/pip" install flask gunicorn

cat > "${APP_DIR}/app.py" <<'PYAPP'
import socket
import urllib.request
from datetime import datetime, timezone
from flask import Flask, jsonify, Response

app = Flask(__name__)

METADATA_BASE = "http://metadata.google.internal/computeMetadata/v1"
METADATA_HEADER = {"Metadata-Flavor": "Google"}

FLIGHT_DATA = {
    "vessel": "Endurance-01",
    "target": "Gargantua",
    "distance_to_singularity": "0.002 LY",
    "time_dilation_factor": "1 hour : 7 years",
    "hull_integrity": "98.4%",
    "oxygen_supply": "84%",
    "mission": "Blackhole Slingshot",
    "platform": "GCP Compute VM",
}


def utc_now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def metadata_get(path, default="unknown"):
    try:
        req = urllib.request.Request(f"{METADATA_BASE}/{path}", headers=METADATA_HEADER)
        with urllib.request.urlopen(req, timeout=2) as response:
            value = response.read().decode("utf-8").strip()
            return value if value else default
    except Exception:
        return default


def safe_split_last(value):
    if not value or value == "unknown":
        return "unknown"
    return value.split("/")[-1]


def instance_metadata():
    zone_full = metadata_get("instance/zone")
    zone = safe_split_last(zone_full)
    region = zone.rsplit("-", 1)[0] if "-" in zone else "unknown"

    return {
        "service": "Interstellar Event Horizon",
        "time_utc": utc_now(),
        "project_id": metadata_get("project/project-id"),
        "project_number": metadata_get("project/numeric-project-id"),
        "instance_id": metadata_get("instance/id"),
        "instance_name": metadata_get("instance/name"),
        "hostname": socket.gethostname(),
        "zone": zone,
        "region": region,
        "machine_type": safe_split_last(metadata_get("instance/machine-type")),
        "network": {
            "vpc": safe_split_last(metadata_get("instance/network-interfaces/0/network")),
            "subnet": safe_split_last(metadata_get("instance/network-interfaces/0/subnetwork")),
            "internal_ip": metadata_get("instance/network-interfaces/0/ip"),
            "external_ip": metadata_get("instance/network-interfaces/0/access-configs/0/external-ip"),
        },
    }


@app.route("/healthz")
def healthz():
    return Response("ok\n", status=200, mimetype="text/plain")


@app.route("/metadata")
def metadata():
    return jsonify(instance_metadata())


@app.route("/api/status")
def status():
    data = FLIGHT_DATA.copy()
    data["status"] = "online"
    data["render_engine"] = "HTML5 Canvas"
    data["time_utc"] = utc_now()
    return jsonify(data)


@app.route("/")
def index():
    return r"""
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Event Horizon | Interstellar Flight</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">

  <style>
    :root {
      --text: #f8fafc;
      --muted: #a8b3c7;
      --blue: #0ea5ff;
      --blue-soft: rgba(14,165,255,.18);
      --panel: rgba(2, 6, 23, .62);
      --border: rgba(148, 163, 184, .25);
      --green: #22c55e;
    }

    * { box-sizing: border-box; }

    html, body {
      width: 100%;
      height: 100%;
      margin: 0;
      overflow: hidden;
      background: #000;
      color: var(--text);
      font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    }

    canvas {
      position: fixed;
      inset: 0;
      width: 100%;
      height: 100%;
      display: block;
      background: #000;
    }

    .shade {
      position: fixed;
      inset: 0;
      z-index: 2;
      pointer-events: none;
      background:
        radial-gradient(circle at 67% 42%, transparent 22%, rgba(0,0,0,.18) 58%, rgba(0,0,0,.84) 100%),
        linear-gradient(90deg, rgba(0,0,0,.55), rgba(0,0,0,.05) 45%, rgba(0,0,0,.20));
    }

    .grain {
      position: fixed;
      inset: 0;
      z-index: 3;
      pointer-events: none;
      opacity: .10;
      mix-blend-mode: soft-light;
      background-image:
        radial-gradient(circle, rgba(255,255,255,.25) 0 1px, transparent 1px),
        radial-gradient(circle, rgba(255,255,255,.16) 0 1px, transparent 1px);
      background-size: 3px 3px, 7px 7px;
      animation: grain 1.1s steps(5) infinite;
    }

    @keyframes grain {
      0% { transform: translate(0,0); }
      25% { transform: translate(-1%, .5%); }
      50% { transform: translate(.7%, -1%); }
      75% { transform: translate(-.4%, -.6%); }
      100% { transform: translate(0,0); }
    }

    .top-clock {
      position: fixed;
      right: 42px;
      top: 32px;
      z-index: 6;
      padding: 12px 18px;
      border: 1px solid var(--border);
      border-radius: 18px;
      background: rgba(2, 6, 23, .58);
      backdrop-filter: blur(14px);
      color: #e2e8f0;
      font-size: 14px;
      letter-spacing: .04em;
      box-shadow: 0 18px 50px rgba(0,0,0,.35);
    }

    .hud {
      position: fixed;
      z-index: 6;
      left: 36px;
      top: 42px;
      width: min(445px, calc(100vw - 72px));
      padding: 34px;
      border: 1px solid var(--border);
      border-radius: 16px;
      background: linear-gradient(140deg, rgba(2,6,23,.78), rgba(2,6,23,.34));
      backdrop-filter: blur(18px);
      box-shadow: 0 26px 90px rgba(0,0,0,.50);
    }

    .live {
      display: inline-flex;
      align-items: center;
      gap: 12px;
      color: var(--blue);
      font-size: 13px;
      letter-spacing: .12em;
      text-transform: uppercase;
      font-weight: 800;
    }

    .dot {
      width: 12px;
      height: 12px;
      border-radius: 999px;
      background: var(--green);
      box-shadow: 0 0 22px var(--green);
      animation: pulse 1.8s ease-in-out infinite;
    }

    @keyframes pulse {
      0%,100% { transform: scale(.72); opacity: .65; }
      50% { transform: scale(1.12); opacity: 1; }
    }

    h1 {
      margin: 22px 0 14px;
      font-size: clamp(52px, 7vw, 78px);
      line-height: .87;
      letter-spacing: -.06em;
      font-weight: 900;
      text-transform: uppercase;
    }

    .subtitle {
      color: var(--blue);
      font-size: 20px;
      letter-spacing: .12em;
      text-transform: uppercase;
      font-weight: 800;
      margin-bottom: 26px;
    }

    .rule {
      height: 1px;
      background: rgba(148,163,184,.25);
      margin: 0 0 24px;
    }

    .sub {
      margin: 0;
      color: var(--muted);
      font-size: 17px;
      line-height: 1.6;
      max-width: 330px;
    }

    .links {
      display: grid;
      grid-template-columns: 1fr;
      gap: 10px;
      margin-top: 36px;
      max-width: 184px;
    }

    .links a {
      display: flex;
      align-items: center;
      gap: 12px;
      color: var(--blue);
      text-decoration: none;
      border: 1px solid rgba(148,163,184,.18);
      background: rgba(0,0,0,.20);
      padding: 16px 24px;
      border-radius: 8px;
      font-size: 18px;
      font-weight: 800;
      clip-path: polygon(0 0, 92% 0, 100% 22%, 100% 100%, 0 100%);
    }

    .system {
      position: fixed;
      z-index: 6;
      left: 36px;
      bottom: 132px;
      width: min(445px, calc(100vw - 72px));
      padding: 26px 34px;
      border: 1px solid var(--border);
      border-radius: 16px;
      background: rgba(2,6,23,.58);
      backdrop-filter: blur(14px);
      box-shadow: 0 26px 90px rgba(0,0,0,.35);
    }

    .system-title {
      color: var(--blue);
      text-transform: uppercase;
      font-weight: 900;
      letter-spacing: .08em;
      margin-bottom: 18px;
    }

    .badge {
      display: inline-flex;
      align-items: center;
      gap: 10px;
      color: #d1d5db;
    }

    .badge span {
      background: rgba(34,197,94,.32);
      color: #dcfce7;
      border-radius: 999px;
      padding: 6px 12px;
      font-size: 13px;
      font-weight: 900;
      text-transform: uppercase;
    }

    .metrics {
      position: fixed;
      right: 42px;
      bottom: 70px;
      z-index: 6;
      display: grid;
      grid-template-columns: repeat(4, 158px);
      gap: 18px;
    }

    .metric {
      height: 185px;
      border: 1px solid var(--border);
      border-radius: 16px;
      background: rgba(2,6,23,.50);
      backdrop-filter: blur(14px);
      display: grid;
      place-items: center;
      text-align: center;
      padding: 22px 14px;
      box-shadow: 0 22px 70px rgba(0,0,0,.35);
    }

    .icon {
      width: 56px;
      height: 56px;
      display: grid;
      place-items: center;
      border-radius: 14px;
      background: var(--blue-soft);
      color: var(--blue);
      font-size: 29px;
      margin-bottom: 14px;
    }

    .metric span {
      display: block;
      color: var(--blue);
      text-transform: uppercase;
      letter-spacing: .06em;
      font-size: 12px;
      font-weight: 900;
      margin-bottom: 10px;
    }

    .metric strong {
      display: block;
      color: white;
      font-size: 16px;
      line-height: 1.25;
      font-weight: 850;
    }

    .footer {
      position: fixed;
      left: 0;
      right: 0;
      bottom: 18px;
      z-index: 6;
      text-align: center;
      color: rgba(226,232,240,.56);
      font-size: 16px;
      letter-spacing: .02em;
    }

    @media (max-width: 980px) {
      .hud { top: 18px; left: 18px; padding: 22px; }
      .system { left: 18px; bottom: 20px; padding: 18px; }
      .metrics {
        right: 18px;
        bottom: 20px;
        grid-template-columns: repeat(2, minmax(130px, 1fr));
        width: min(360px, calc(100vw - 36px));
      }
      .metric { height: 120px; }
      .footer, .top-clock { display: none; }
    }
  </style>
</head>

<body>
  <canvas id="space"></canvas>
  <div class="shade"></div>
  <div class="grain"></div>

  <div class="top-clock" id="clock">UTC --:--:--</div>

  <section class="hud">
    <div class="live"><span class="dot"></span>Live Simulation</div>
    <h1>Event<br>Horizon</h1>
    <div class="subtitle">Interstellar Flight</div>
    <div class="rule"></div>
    <p class="sub">
      A real-time gravitational flight simulation rendered directly from this GCP instance.
      The starship orbits the black hole in a non-repeating trajectory.
    </p>

    <div class="links">
      <a href="/healthz">⌁ /healthz</a>
      <a href="/metadata">▤ /metadata</a>
      <a href="/api/status">◇ /api/status</a>
    </div>
  </section>

  <section class="system">
    <div class="system-title">System Status</div>
    <div class="badge"><span>Online</span> All systems nominal</div>
  </section>

  <section class="metrics">
    <div class="metric">
      <div class="icon">🚀</div>
      <span>Mission</span>
      <strong>Blackhole<br>Slingshot</strong>
    </div>
    <div class="metric">
      <div class="icon">◌</div>
      <span>Flight Mode</span>
      <strong>Non-Repeating<br>Orbit</strong>
    </div>
    <div class="metric">
      <div class="icon">▭</div>
      <span>Render Engine</span>
      <strong>HTML5<br>Canvas</strong>
    </div>
    <div class="metric">
      <div class="icon">☁</div>
      <span>Platform</span>
      <strong>GCP Compute<br>VM</strong>
    </div>
  </section>

  <div class="footer">◉ &nbsp; Interstellar Event Horizon &nbsp; • &nbsp; Running on Google Cloud Platform</div>

<script>
const canvas = document.getElementById("space");
const ctx = canvas.getContext("2d", { alpha: false });
const clock = document.getElementById("clock");

let w = 0, h = 0, dpr = 1;
const TAU = Math.PI * 2;
const trails = [];

function resize() {
  dpr = Math.min(window.devicePixelRatio || 1, 2);
  w = innerWidth;
  h = innerHeight;
  canvas.width = Math.floor(w * dpr);
  canvas.height = Math.floor(h * dpr);
  canvas.style.width = w + "px";
  canvas.style.height = h + "px";
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
}
addEventListener("resize", resize);
resize();

function rand(seed) {
  const x = Math.sin(seed * 999.91) * 43758.5453;
  return x - Math.floor(x);
}

const stars = Array.from({ length: 700 }, (_, i) => {
  const a = rand(i + 10) * TAU;
  const r = Math.pow(rand(i + 20), .58);
  return {
    x: Math.cos(a) * r,
    y: Math.sin(a) * r,
    size: .35 + rand(i + 30) * 1.7,
    phase: rand(i + 40) * TAU,
    depth: .45 + rand(i + 50) * 1.7
  };
});

const disk = Array.from({ length: 1200 }, (_, i) => ({
  a: rand(i + 100) * TAU,
  r: 95 + Math.pow(rand(i + 200), .68) * 430,
  speed: .12 + rand(i + 300) * .35,
  size: .45 + rand(i + 400) * 2.2,
  heat: rand(i + 500),
  phase: rand(i + 600) * TAU
}));

function tickClock() {
  clock.textContent = "◷  UTC   " + new Date().toISOString().slice(11, 19);
}
setInterval(tickClock, 1000);
tickClock();

function background(t) {
  const g = ctx.createRadialGradient(w * .68, h * .38, 0, w * .68, h * .42, Math.max(w, h) * .94);
  g.addColorStop(0, "#24303a");
  g.addColorStop(.22, "#111827");
  g.addColorStop(.62, "#04070d");
  g.addColorStop(1, "#000");
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, w, h);

  ctx.save();
  ctx.globalCompositeOperation = "screen";
  const wash = ctx.createLinearGradient(0, 0, w, h);
  wash.addColorStop(0, "rgba(56,189,248,.05)");
  wash.addColorStop(.55, "rgba(255,220,180,.07)");
  wash.addColorStop(1, "rgba(245,158,11,.04)");
  ctx.fillStyle = wash;
  ctx.fillRect(0, 0, w, h);
  ctx.restore();
}

function drawStars(t) {
  const cx = w * .62, cy = h * .48;
  ctx.save();
  for (const s of stars) {
    const x = cx + s.x * w * .76 + Math.sin(t * .006 * s.depth + s.phase) * 9;
    const y = cy + s.y * h * .82 + Math.cos(t * .004 * s.depth + s.phase) * 6;
    const blink = .35 + Math.abs(Math.sin(t * (.5 + s.depth) + s.phase)) * .65;
    ctx.beginPath();
    ctx.fillStyle = `rgba(226,232,240,${Math.min(.72, .12 + blink * .25 * s.depth)})`;
    ctx.arc(x, y, s.size * blink, 0, TAU);
    ctx.fill();
  }
  ctx.restore();
}

function drawDisk(cx, cy, t) {
  ctx.save();
  ctx.translate(cx, cy);
  ctx.rotate(-0.19);
  ctx.scale(1, .33);
  ctx.globalCompositeOperation = "lighter";

  for (const p of disk) {
    const a = p.a + t * p.speed / Math.sqrt(p.r * .016) + Math.sin(t * .03 + p.phase) * .04;
    const r = p.r + Math.sin(t * .9 + p.phase) * 6;
    const x = Math.cos(a) * r * 1.95;
    const y = Math.sin(a) * r;
    const front = Math.sin(a) > 0 ? 1 : .30;
    const inner = Math.max(0, 1 - p.r / 530);
    const alpha = (.035 + p.heat * .18 + inner * .18) * front;
    const size = p.size * (1 + inner * 1.8) * (front ? 1 : .55);

    let color = `rgba(245,158,11,${alpha})`;
    if (p.heat > .72) color = `rgba(255,245,220,${alpha * 1.2})`;
    if (p.heat < .18) color = `rgba(56,189,248,${alpha * .75})`;

    ctx.beginPath();
    ctx.fillStyle = color;
    ctx.ellipse(x, y, size * 3.1, size, 0, 0, TAU);
    ctx.fill();
  }

  for (let i = 0; i < 9; i++) {
    const r = 82 + i * 45;
    ctx.beginPath();
    ctx.strokeStyle = `rgba(255,230,190,${.105 - i * .008})`;
    ctx.lineWidth = 17 - i;
    ctx.ellipse(0, 0, r * 2.06, r, 0, 0, TAU);
    ctx.stroke();
  }

  ctx.restore();
  ctx.globalCompositeOperation = "source-over";
}

function drawBlackHole(cx, cy, t) {
  drawDisk(cx, cy, t);

  ctx.save();
  const glow = ctx.createRadialGradient(cx, cy, 85, cx, cy, 410);
  glow.addColorStop(0, "rgba(0,0,0,0)");
  glow.addColorStop(.22, "rgba(255,245,220,.42)");
  glow.addColorStop(.34, "rgba(245,158,11,.13)");
  glow.addColorStop(.72, "rgba(56,189,248,.035)");
  glow.addColorStop(1, "rgba(0,0,0,0)");
  ctx.fillStyle = glow;
  ctx.beginPath();
  ctx.arc(cx, cy, 410, 0, TAU);
  ctx.fill();

  ctx.shadowColor = "rgba(255,245,220,.95)";
  ctx.shadowBlur = 44;
  ctx.strokeStyle = "rgba(255,245,220,.93)";
  ctx.lineWidth = 4;
  ctx.beginPath();
  ctx.arc(cx, cy, 122 + Math.sin(t * 1.3) * .7, 0, TAU);
  ctx.stroke();

  ctx.shadowColor = "#000";
  ctx.shadowBlur = 62;
  ctx.fillStyle = "#000";
  ctx.beginPath();
  ctx.arc(cx, cy, 120, 0, TAU);
  ctx.fill();

  ctx.restore();
}

function computeShip(t) {
  const cx = w * .62, cy = h * .48;
  const theta = t * .31 + Math.sin(t * .043) * .44;
  const orbit = Math.min(w, h) * .33;
  return {
    x: cx + Math.cos(theta) * orbit * 1.72,
    y: cy + Math.sin(theta) * orbit * .43,
    scale: .45 + ((Math.sin(theta) + 1) / 2) * .72,
    behind: Math.sin(theta) < -.15,
    heading: theta + Math.PI / 2
  };
}

function drawTrail(ship) {
  trails.push({ x: ship.x, y: ship.y, s: ship.scale });
  if (trails.length > 120) trails.shift();

  ctx.save();
  ctx.globalCompositeOperation = "lighter";
  for (let i = 1; i < trails.length; i++) {
    const a = trails[i - 1], b = trails[i];
    const life = i / trails.length;
    ctx.beginPath();
    ctx.strokeStyle = `rgba(56,189,248,${life * .16})`;
    ctx.lineWidth = Math.max(.6, b.s * life * 3.2);
    ctx.moveTo(a.x, a.y);
    ctx.lineTo(b.x, b.y);
    ctx.stroke();
  }
  ctx.restore();
}

function drawShip(ship, t, opacity) {
  ctx.save();
  ctx.translate(ship.x, ship.y);
  ctx.rotate(ship.heading);
  ctx.scale(ship.scale, ship.scale);
  ctx.globalAlpha = opacity;

  ctx.shadowColor = "rgba(56,189,248,.95)";
  ctx.shadowBlur = 22;

  ctx.fillStyle = "rgba(225,232,240,.96)";
  ctx.beginPath();
  ctx.moveTo(0, -34);
  ctx.lineTo(14, 17);
  ctx.lineTo(0, 8);
  ctx.lineTo(-14, 17);
  ctx.closePath();
  ctx.fill();

  ctx.fillStyle = "rgba(56,189,248,.72)";
  ctx.beginPath();
  ctx.moveTo(-12, 10);
  ctx.lineTo(-48, 31);
  ctx.lineTo(-8, 23);
  ctx.closePath();
  ctx.fill();

  ctx.beginPath();
  ctx.moveTo(12, 10);
  ctx.lineTo(48, 31);
  ctx.lineTo(8, 23);
  ctx.closePath();
  ctx.fill();

  ctx.globalCompositeOperation = "lighter";
  const flame = 20 + Math.sin(t * 16) * 8;
  const g = ctx.createLinearGradient(0, 18, 0, 18 + flame);
  g.addColorStop(0, "rgba(255,255,255,.95)");
  g.addColorStop(.34, "rgba(56,189,248,.68)");
  g.addColorStop(1, "rgba(245,158,11,0)");
  ctx.fillStyle = g;
  ctx.beginPath();
  ctx.moveTo(-7, 18);
  ctx.lineTo(0, 18 + flame);
  ctx.lineTo(7, 18);
  ctx.closePath();
  ctx.fill();

  ctx.restore();
}

function drawFlares(cx, cy, t) {
  ctx.save();
  ctx.globalCompositeOperation = "screen";

  const y = cy + 38 + Math.sin(t * .14) * 2;
  const grad = ctx.createLinearGradient(0, y, w, y);
  grad.addColorStop(0, "rgba(255,255,255,0)");
  grad.addColorStop(.45, "rgba(255,230,190,.06)");
  grad.addColorStop(.55, "rgba(255,255,255,.25)");
  grad.addColorStop(.66, "rgba(56,189,248,.04)");
  grad.addColorStop(1, "rgba(255,255,255,0)");
  ctx.fillStyle = grad;
  ctx.fillRect(0, y - 2, w, 4);

  ctx.restore();
}

function render(ms) {
  const t = ms / 1000;
  const cx = w * .62;
  const cy = h * .48 + Math.sin(t * .03) * 5;

  background(t);
  drawStars(t);

  const ship = computeShip(t);
  drawTrail(ship);

  if (ship.behind) drawShip(ship, t, .30);

  drawBlackHole(cx, cy, t);
  drawFlares(cx, cy, t);

  if (!ship.behind) drawShip(ship, t, 1);

  requestAnimationFrame(render);
}
requestAnimationFrame(render);
</script>
</body>
</html>
    """


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80)
PYAPP

cat > /etc/systemd/system/event-horizon.service <<'SERVICE'
[Unit]
Description=Event Horizon Flask App
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/event-horizon
ExecStart=/opt/event-horizon/venv/bin/gunicorn --bind 0.0.0.0:80 --workers 2 --threads 4 --timeout 60 app:app
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable event-horizon
systemctl restart event-horizon

sleep 3
curl -fsS http://127.0.0.1/healthz
