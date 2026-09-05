# transport-shepherd design

The one-command-per-operation surface is above; this document is the
operational model behind each command and the RFD 2195 DETAILS gotchas
retained as reference for the ceremony that used to live here.

## Operating model

Two roles at runtime:

- **peer**: a box the workspace runs on (HERD, HERO, SIDEKICK, ANCHOR
  today, plus the assist pool). Runs `status` and `gates`.
- **coordinator**: the box that holds the Bao admin token. Runs `status`
  and `gates` too; the coordinator-half responsibilities the trimmed
  commands had (signing, publishing bundles, applying tuples) are done
  by hand through the Bao CLI now.

Both halves are the same binary. Which half runs is decided by the
presence of an admin-scope Bao token; the peer half never holds one.

## Per-command state machines

### status (any)

Reads own alias against `sys/auth` to confirm the cert-auth accessor
still matches the token's, then walks the agents/ KV subtree to render
last-heartbeat times per CN.

### gates (any)

Dispatches to `Shepherd.Gates.<Name>.run/1`. Each gate ships its own
`--self-test`; the dispatcher lists gates when called with no argument.

## Error taxonomy

Every step either succeeds, times out, or returns a Bao error code.
The classes the CLI recognises:

- **transient** (5xx, connect_timeout, DNS): retry with backoff up to 4
  attempts, then surface with the last error.
- **permission** (403): stop, print the token accessor and policy path
  in effect, and exit non-zero — the CLI cannot escalate itself.
- **shape** (malformed CSR, unreadable cert, wrong CA chain): stop, do
  not retry, exit non-zero.

## RFD 2195 gotchas the trimmed commands internalised

Kept as reference for retrofit. Still true about the ceremony that
existed:

- Bundle install writes leaf-and-chain concatenated in the order Bao's
  `bao login -method=cert` requires (leaf first, then intermediates,
  root optional). Getting the order wrong reads as an mTLS handshake
  failure at first use.
- `bao login -method=cert` needs the four Bao env vars (`BAO_ADDR`,
  `BAO_CLIENT_CERT`, `BAO_CLIENT_KEY`, `BAO_CACERT`) present in its
  process env, not just exported in the parent shell. Shepherd exports
  them into the subprocess environment explicitly.
- The templated policy `agents/{{identity.entity.aliases…}}` resolves
  only when the alias accessor matches the cert-auth mount accessor;
  every dedicated cert-auth entry today shares one mount accessor, but
  a rotation that recreates the mount would silently orphan the row.
  Shepherd reads `sys/auth` before each write and refuses if the
  accessor changed underfoot.
- ReBAC tuple keys carry the CN verbatim. A migrate that renames CN
  without rewriting tuples leaves the peer authenticated but
  unauthorised for anything relationship-gated.
- The identity group reconciler wants entity IDs, not names. The peer
  half of migrate holds a name; the coordinator half looks the ID up
  and writes the group.
- A 403 on the agent's own row is almost never the policy. `agents-rw`
  grants `create, read, update, delete` on
  `agents/data/{{identity.entity.aliases.<cert accessor>.name}}`, and
  the alias name is the certificate CN. What produces the 403 is a
  stale `~/.bao-token`: `bao` prefers the file over a fresh login, cert
  tokens live 8 h, and on a shared-`$HOME` box it is one file for
  every agent, so the last `bao login` by any of them wins for all.
  On 2026-09-04 one agent's file held another agent's identity and the
  delete-and-relogin fix held for thirty minutes. So shepherd never
  reads or writes `~/.bao-token`: every login is `-no-store` into the
  agent's own credentials directory, `BAO_TOKEN` is required in the
  environment, and `status` asserts `entity_id` against the agent's
  own alias before anything else. Nothing is writable *under* a row
  (`…/heartbeats/<ts>` is `deny`); the row is the row.

## Non-goals

- Not a general Bao client; only the calls `status` needs.
- Not a policy editor; changes to `agents-rw` or `mps-admin` are done
  by hand through `weftspun/dot-claude` review.
- Not a group definer; groups are declared in RFD 2202 and reconciled
  by hand for now.
