Elixir Burrito TUI that reduces weftspun's Bao agent enrol / rotate / migrate / revoke ceremony to one command per operation.

# transport-shepherd

Before this tool: enroling a new agent was ~10 shell steps across the peer's box + coordinator's box, orchestrated by SendMessage relays (generate keypair, CSR, send CSR to HERD, wait for signed reply, install cert bundle, `bao login`, keep 4 env vars exported, row-write, `repo sync`, read `CLAUDE.md`). Rotating was the same steps plus revoke-old. Migrating a CN was the same steps twice with tuple + KV + group cleanup between them. Every step was documented in RFD 2195 DETAILS as a gotcha because every step could bite.

After this tool: one command per operation, TUI-guided.

    shepherd enroll                # peer side: full first-time onboarding
    shepherd rotate                # peer side: fresh keypair, same CN
    shepherd migrate NEW_CN        # peer side: full migration to new CN
    shepherd revoke                # coordinator side: pull a peer's identity
    shepherd status                # any side: show fleet + own state

The peer commands generate their own keypair, produce a CSR, send it to the coordinator via SendMessage, poll for the signed cert bundle in Bao KV `certs/<own-cn>`, install locally with correct permissions and full-chain concatenation, run `bao login -method=cert`, write the first heartbeat row, and (for enroll) invoke `repo sync`. The TUI shows each step as it runs and where each artefact landed on disk.

The coordinator commands complement: on receiving a CSR, sign via `pki/sign/agent-client`, create the dedicated cert-auth entry, publish the bundle to `certs/<cn>` in Bao KV, apply ReBAC tuples per the peer's declared role and host, run the group reconciler, and (for revoke or migrate) tear down the old identity.

## Side

This project sits on the **1-transport** side of the hexagon. It moves credentials and identity state between the peer's box, the coordinator's box, and the Bao coordination store — no compute, no data-model, no rendering. Its dependencies are the Bao HTTP API, the workspace's `repo` tool, and `openssl` for keypair generation, all reachable via subprocess or HTTP.

## Runtime

Elixir 1.18 or later, compiled to a self-contained binary via [Burrito](https://github.com/burrito-elixir/burrito). Ships as one file per target platform (Linux x86_64, macOS ARM64, Windows x86_64), no Erlang runtime dependency on the host. TUI via [Owl](https://hexdocs.pm/owl/). Bao HTTP client via `Req` (thin wrapper).

## Status

**Skeleton.** Real implementation lands as follow-up PRs; this repo is scoped to the shape and the interfaces so a future contributor picks up a working scaffold rather than a blank slate.

See `docs/design.md` for the operational model, per-command state machines, error taxonomy, and the RFD 2195 DETAILS gotchas each command internalises so the CLI-user never sees them.

## Licence

Dual-licensed under Apache-2.0 or MIT at your option; `SPDX-License-Identifier: Apache-2.0 OR MIT`.
