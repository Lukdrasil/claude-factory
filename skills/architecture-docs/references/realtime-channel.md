---
written_against: "web research 2026-08"
---

`written_against` names the product and default state this rubric was checked against — nginx and
AWS ALB idle-timeout defaults, SignalR's and Socket.IO's backplane adapters, the SSE support in
the major LLM APIs. A vendor page that contradicts it means this file is stale and needs
re-research, not that the solution drifted.

# Realtime channel — WebSockets, SSE, or polling, and how it survives scale-out

Load this when the UI needs live updates — notifications, dashboards, chat, progress, token
streams — and the transport and its scale-out story are being chosen. `communication.md` owns the
protocol and contract of the ordinary request/response edges; this file covers the one edge that
stays open. `machine-topology.md` establishes whether there is more than one instance, which is
the question that decides whether a backplane exists; `edge-proxy.md` owns the proxy in front,
whose idle timeouts and buffering settings decide whether the channel survives at all;
`llm-features.md` owns the LLM feature whose token stream is usually the first SSE consumer here.

Outputs land in `03-containers.md` (the channel as an edge, and the backplane as a unit), in
`06-deployment.md` (the proxy timeout and buffering settings, and where the backplane runs) and in
an ADR per `templates.md`. Every choice below reaches the human as options with consequences plus
your recommendation, per `approaches.md`.

Choose by message direction and infrastructure honesty. WebSockets for bidirectional traffic —
chat, collaboration, games. SSE for server-to-client streams — notifications, dashboards, LLM
tokens; every major LLM API streams over SSE. Plain polling when updates are infrequent enough
that a 30-second GET is simply the truth.

Two facts govern everything after that. The moment you run more than one instance, WebSockets need
a backplane — Redis pub/sub via the SignalR backplane or the Socket.IO Redis adapter — so a message
published on one node reaches sockets on another; sticky sessions alone only pin clients, they do
not route broadcasts. And every long-lived connection has to outlive the proxy idle timeouts in
its path — nginx `proxy_read_timeout` is 60s, the AWS ALB default is 60s — so heartbeats must fire
well inside the shortest timeout in the chain.

## Choosing by driver

| Signal in the repo or the interview | Where it leads |
|---|---|
| The client sends frequently too — chat, cursors, collaborative editing, games | WebSockets; full duplex is the point, and SSE would need a parallel POST channel |
| Server-to-client only: notifications, progress bars, dashboards, LLM token streams | SSE — plain HTTP, auto-reconnect with `Last-Event-ID` built into `EventSource`, easiest through proxies once buffering and timeouts are configured |
| Updates arrive every 30s or more and a minute of staleness is fine | plain short polling — boring, cacheable, stateless, works through everything; do not build a socket tier for it |
| More than one app instance, whether a pair or an autoscale group | a shared pub/sub backplane (Redis) via the SignalR Redis backplane or the Socket.IO Redis adapter, or an external realtime service |
| A .NET stack | SignalR, which handles transport negotiation and reconnect, with Azure SignalR Service if you do not want to own connection scale |
| No ops capacity but hard realtime requirements | managed realtime (Azure Web PubSub or SignalR Service, Ably, Pusher) — connections terminate outside your fleet |

## Raw WebSockets (ws, ASP.NET WebSockets, Gorilla-style)

- **Use when** the traffic is bidirectional and latency-sensitive, and you are willing to own
  reconnect, heartbeat and fan-out yourself.
- **Pros** the lowest overhead per message — 1,000 events is roughly 119 KB against about 885 KB
  for long-polling — and full duplex; total protocol control, with binary frames and custom
  subprotocols.
- **Cons** you hand-roll everything frameworks give away free: reconnect with backoff,
  missed-message replay, heartbeats, auth refresh mid-connection. Scale-out is entirely on you —
  backplane, connection draining on deploys, per-node connection limits.
- **Typical mistakes** no application-level ping, so ALB and nginx idle timeouts (60s default)
  silently kill quiet connections — heartbeat every 25-30s, always under the shortest timeout in
  the chain; broadcast loops over a local connection list on a multi-instance deploy, so users on
  other nodes never get the message; forgetting the proxy upgrade config, since nginx needs
  `proxy_http_version 1.1` plus the `Upgrade`/`Connection` headers or the handshake 400s.

## SignalR (with a Redis backplane or Azure SignalR Service)

- **Use when** the backend is .NET and you want negotiation, reconnect, groups and fallback handled
  by the framework.
- **Pros** automatic transport negotiation (WebSockets, then SSE, then long-poll) and client
  reconnect are built in; the first-party Redis backplane (`AddStackExchangeRedis`) handles
  scale-out and Azure SignalR Service offloads connections entirely; the groups and users
  abstraction beats a hand-rolled socket registry.
- **Cons** the negotiate handshake and the chosen transport must hit the same server, so sticky
  sessions (ARR affinity) are required on multi-instance unless you `SkipNegotiation` with
  WebSockets only or use the Azure service; the default protocol is chatty, and the backplane adds
  Redis as a hard dependency.
- **Typical mistakes** adding the Redis backplane but skipping sticky sessions, so negotiation
  lands on node A and the WebSocket upgrade on node B and the connection fails intermittently;
  assuming the backplane persists messages, when Redis pub/sub is fire-and-forget — a node that is
  down misses the message, so clients need reconcile-on-reconnect; running it on serverless or
  consumption plans that cannot hold connections.

## Socket.IO (with the Redis adapter)

- **Use when** the backend is Node and you want rooms, acknowledgements, auto-reconnect and an HTTP
  long-poll fallback for hostile networks.
- **Pros** rooms, acks and reconnection with buffered emits out of the box; the Redis adapter
  (`@socket.io/redis-adapter`) makes cross-node emits transparent; connection state recovery can
  replay missed events after short disconnects.
- **Cons** it is not a plain WebSocket — the protocol is custom, and non-JS clients need
  Socket.IO-specific libraries; the HTTP polling fallback mode requires sticky sessions at the load
  balancer, and the framing carries extra overhead.
- **Typical mistakes** multi-instance without sticky sessions while the polling fallback is
  enabled, so the session id is unknown on the other node and you get constant 400s — either enable
  stickiness or force `transports: ['websocket']`; treating the Redis adapter as durable delivery,
  when like SignalR it is pub/sub fan-out, not a queue.

## Server-Sent Events (SSE / EventSource)

- **Use when** the push is one-way: notifications, live dashboards, job progress, LLM token
  streaming. The 2026 default for server-to-client.
- **Pros** plain HTTP, so it goes through firewalls and proxies that fight WebSocket upgrades, and
  it is trivially load-balanced because any node can serve a stream; `EventSource` auto-reconnects
  and sends `Last-Event-ID`, so resume semantics are in the spec and you just replay from the id;
  scale-out fan-out still goes via Redis pub/sub, but no sticky sessions are needed since the
  channel is one-way.
- **Cons** server-to-client only, so client actions go over normal fetch or POST; frames are
  text-only, needing base64 for binary, and on HTTP/1.1 the browser's six-connections-per-origin
  cap bites — run HTTP/2, where it is a non-issue.
- **Typical mistakes** nginx defaults kill it: a 60s `proxy_read_timeout` drops idle streams and
  buffering batches events into 15-20s bursts — set `proxy_buffering off` (or send
  `X-Accel-Buffering: no`), `proxy_read_timeout 3600s`, `gzip off` for the stream, plus app-level
  keepalive comments roughly every 30s; sending no event ids, so `Last-Event-ID` reconnect resumes
  nothing and clients silently lose events dropped during the gap; response compression middleware
  buffering the stream, which is common in .NET and YARP setups.

## Plain short polling (GET every N seconds)

- **Use when** the update cadence is minutes-ish, or the audience is tiny. Also the honest choice
  when the platform — strict corporate proxies, PHP-fpm-style workers — cannot hold connections.
- **Pros** zero infrastructure demands: stateless, cacheable via ETag and 304, works behind every
  proxy ever made, and trivially horizontally scaled. The failure mode is graceful staleness rather
  than dropped connections.
- **Cons** the latency floor is the poll interval, and at high user counts it is a self-inflicted
  DDoS; it carries the most bytes per delivered event of any option, because of headers on every
  request.
- **Typical mistakes** polling every 2s "to feel realtime", at which point build SSE — polling
  below roughly 10s at scale is the worst of both worlds; no jitter on the interval, giving
  thundering-herd synchronisation after deploys and outages; skipping ETag and `If-None-Match`, so
  every empty poll ships a full payload.

## Managed realtime service (Azure SignalR / Web PubSub, Ably, Pusher, Momento)

- **Use when** realtime matters but connection ops do not fit the team, or the backend is
  serverless and cannot hold sockets.
- **Pros** connections, scale-out and global presence are someone else's pager, and the backend
  just POSTs events to an API; it solves the serverless-cannot-hold-sockets problem cleanly.
- **Cons** per-connection and per-message pricing compounds at scale, and the client protocol is
  vendor lock-in; it adds another external dependency in the auth path, for token issuance.
- **Typical mistakes** proxying every message through your own API "for control", which rebuilds
  the connection tier you paid to avoid; ignoring egress and message quotas until the first viral
  event.

## What holds whatever you pick

- Direction decides: bidirectional means WebSockets, server-push-only means SSE, slow cadence means
  polling. Do not buy WebSocket ops for a notification feed.
- One instance is the only world where in-process connection lists work. From two instances up,
  broadcasts must go through a shared backplane — Redis pub/sub via the SignalR backplane or the
  Socket.IO adapter — or a managed service.
- Sticky sessions and backplanes solve different problems: stickiness pins a client's handshake to
  one node, the backplane routes messages across nodes. SignalR multi-instance and
  Socket.IO-with-polling need both; pure WebSocket or SSE need only the backplane.
- The heartbeat interval must be comfortably under the shortest idle timeout in the chain — nginx
  `proxy_read_timeout` 60s, AWS ALB 60s default. Pick 25-30s pings or raise the timeouts, and
  measure the whole chain, not one hop.
- For SSE behind nginx or YARP: buffering off, compression off for the stream, a long read timeout,
  and event ids sent so `Last-Event-ID` reconnects can actually replay.
- Redis pub/sub backplanes are fire-and-forget fan-out, not durable queues. Clients must reconcile
  state on reconnect — fetch-since-id — or you will lose events on every deploy.
- Serverless request/response platforms cannot hold sockets. Use SSE via streaming responses where
  supported, or a managed realtime service.

## When the evidence is thin

If nothing recorded distinguishes the options, recommend SSE from a single instance with event ids
on every message and the proxy's buffering and read timeout set explicitly. Name the trigger that
would change it — the first client-to-server message that is not a fetch, the second app instance,
a serverless host that cannot hold the response open — as a row in `07-risks.md`.

## Recording the choice

1. Put the options to the human against the affected `QS-` and `C-` ids: the transport, whether a
   backplane exists, and whether sticky sessions are required.
2. State the recurring cost of each — the Redis instance, the managed service's per-connection
   pricing, the poll volume at expected user counts — and what reversing it later costs.
3. Write the accepted choice as an ADR under `docs/adr/`, the rejected ones as alternatives with
   the reason each lost, and reference it from `03-containers.md` and `06-deployment.md`.
4. The measurable outcomes become rows in `04-quality-scenarios.md` with a number and a unit: the
   heartbeat interval against the shortest proxy timeout, the delivery latency the UI promises, and
   the concurrent-connection ceiling per node.
5. A backplane treated as durable delivery, a reconnect path with no reconcile step, and a proxy
   timeout nobody has measured end to end are rows in `07-risks.md`. Anything the human leaves open
   is a `TODO(question)` per `templates.md`.
