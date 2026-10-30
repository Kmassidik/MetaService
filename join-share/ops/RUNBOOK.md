# join-share: runbook (what is needed to go live, in order)

Everything automatic is already tested on the Mini by `ops/live/wg-lab.sh` (network and firewall) and `ops/live/join-e2e.sh` (the whole join, in a container). The real laptops need the parts below, which only the owner of the router and of the Cloudflare account can do.

## 1. One time, on the Omada router (Kurnia)

Forward **UDP 51830** from the public address to the Mac Mini (`192.168.0.40`), the same way ports 22, 1001, 1002 and 1003 are forwarded today. Nothing else is opened. WireGuard does not answer a packet that has no valid key, so the port does not show itself to scanners.

## 2. One time, the join address (Kurnia)

The far PC downloads the join script over **https**. Add a hostname to the existing `metaservice` Cloudflare tunnel (Zero Trust, Networks, Tunnels, `metaservice`, Public hostname): for example `join.ruvio.site` pointing at `http://localhost:9110`. No Access policy (only the one-time link protects it). If you prefer another name, give it as `JOIN_SHARE_PUBLIC_URL` in step 3.

## 3. Install the hub on the Mini (done 2026-10-31, from `~/MetaService`; run it again after a `git pull` that changes `join-share/`)

```
ssh macmini 'cd ~/MetaService-join-share && git pull --ff-only \
  && JOIN_SHARE_ENDPOINT=202.72.223.27:51830 JOIN_SHARE_PUBLIC_URL=https://join.ruvio.site sh join-share/ops/install-hub.sh'
```

It builds, installs the narrow root helper and its sudoers line, writes `join-share/state/hub.env`, and starts the boot job `io.metaservice.joinshare`. `sh join-share/ops/install-hub.sh remove` takes it away again. The running MetaService and MAAS are not touched.

## 4. Open the admin page (Kurnia)

Double-click **`Join-a-PC-admin.command`** on the Desktop (a copy of `ops/open-admin.command`). It opens the SSH forward to the Mini, reads the admin key there and opens the page with the key in the address after `#`, so nothing is typed and the key is never sent to a server. Keep its window open while you use the page; closing it closes the forward. The admin page listens on the Mini's loopback only and is not part of the panel.

## 5. Join the laptops (Kurnia)

On the page press **Mac** then **Apple silicon** (your MacBook), copy the command, paste it in a terminal on the MacBook, answer `y`, type the macOS password once when `sudo` asks. The terminal shows a 6-digit code. Type it into the pending row on the admin page and press **Approve**. Repeat with **Linux** then **x86_64** on the Fedora laptop.

Within about a minute each laptop appears in **Machines** on `meta.ruvio.site` as ONLINE.

## Take a machine away

On the laptop: `sh ~/.metaservice-join/leave.sh`. In the panel: remove the machine as usual. On the admin page: **Remove** on the joined machine (closes its WireGuard peer).
