Elixir Burrito TUI for the weftspun agent fleet: `status` and workspace `gates`.

# transport-shepherd

    shepherd status                # any side: show fleet + own state
    shepherd gates <name> [args]   # run a workspace gate (see `shepherd gates`)

The enrol / rotate / migrate / revoke ceremony was trimmed after per-agent `BAO_TOKEN` + `bao login -no-store` closed the stale-token failure mode RFD 2195 was written against. If those commands are needed again, retrofit from RFD 2195 DETAILS §"stale token file".

## Side

This project sits on the **1-transport** side of the hexagon. `status` moves fleet + own state between the peer's box, the coordinator's box, and the Bao coordination store; `gates` runs the workspace gates ported from `weftspun/request-for-discussion`'s `scripts/`. No compute, no data-model, no rendering.

## Runtime

Elixir 1.18 or later, compiled to a self-contained binary via [Burrito](https://github.com/burrito-elixir/burrito). Ships as one file per target platform (macOS ARM64, Windows x86_64), no Erlang runtime dependency on the host. Bao HTTP client via `Req`.

## Status

**Skeleton.** `gates` is real and lands the 17 bucket-A gate ports task #83 shipped; `status` is scaffolded. `docs/design.md` retains the RFD 2195 DETAILS gotcha internalisation for the ceremony that used to sit here.

## Licence

Dual-licensed under Apache-2.0 or MIT at your option; `SPDX-License-Identifier: Apache-2.0 OR MIT`.
