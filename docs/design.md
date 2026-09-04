# transport-shepherd design

The one-command-per-operation surface is above; this document is the
operational model behind each command and the RFD 2195 DETAILS gotchas
each command internalises so the CLI-user never sees them.

## Operating model

Two roles at runtime:

- **peer**: a box the workspace runs on (HERD, HERO, SIDEKICK, ANCHOR
  today, plus the assist pool). Runs `enroll`, `rotate`, `migrate`.
- **coordinator**: the box that holds the Bao admin token. Runs
  `revoke`. Also runs the signing half of every peer command, addressed
  by a SendMessage relay from the peer's shepherd invocation.

Both halves are the same binary. Which half runs is decided by argv
plus the presence of an admin-scope Bao token; the peer half never
holds one.

## Per-command state machines

### enroll (peer)

    read/confirm CN
    generate keypair under ~/.shepherd/<cn>/{key.pem,cert.pem,chain.pem}
    build CSR
    hand CSR to coordinator (SendMessage; the coordinator command
      handles: sign, publish bundle to Bao KV certs/<cn>, create
      cert-auth entry, apply ReBAC tuples for declared role+host, run
      group reconciler)
    poll certs/<cn> until the signed bundle appears (backoff 2/4/8/16 s)
    install cert bundle (0600 on key, 0644 on cert + chain)
    bao login -method=cert (stash token at ~/.bao-token)
    write first heartbeat row to agents/<cn>.agents.weftspun
    repo sync at workspace root

### rotate (peer)

Same as enroll except CN comes from ~/.shepherd/current and the last
step is a coordinator-side revoke of the old serial rather than a
`repo sync`.

### migrate (peer, `shepherd migrate NEW_CN`)

The two ceremony most likely to leave a half-migrated fleet, so the
state machine is explicit about the ordering:

    resolve NEW_CN + read old CN from ~/.shepherd/current
    generate fresh keypair under ~/.shepherd/<NEW_CN>/
    build CSR for NEW_CN
    hand CSR + migration intent to coordinator, which:
      signs against NEW_CN,
      creates cert-auth entry for NEW_CN,
      migrates ReBAC tuples (rewrite subject/object where they matched old CN),
      reconciles identity groups (add NEW_CN's entity to the groups
        old CN was in; do not remove old CN yet — it stays alive
        through the changeover)
    poll certs/<NEW_CN> for signed bundle
    install bundle
    bao login as NEW_CN
    write heartbeat row at NEW_CN
    coordinator: tear down old cert-auth entry, revoke old serial,
      remove old CN's entity from groups, delete agents/<old-cn>.…
    update ~/.shepherd/current to NEW_CN

### revoke (coordinator, `shepherd revoke CN`)

    read cert-auth entry (serial, accessor)
    delete cert-auth entry
    revoke PKI serial
    drop ReBAC tuples where subject or object == CN
    remove entity from all identity groups
    delete Bao KV rows for certs/CN and agents/CN.agents.weftspun

## Error taxonomy

Every step either succeeds, times out, or returns a Bao error code.
The classes the CLI recognises:

- **transient** (5xx, connect_timeout, DNS): retry with backoff up to 4
  attempts, then surface with the last error.
- **permission** (403): stop, print the token accessor and policy path
  in effect, and exit non-zero — the CLI cannot escalate itself.
- **conflict** (existing cert-auth entry, existing tuple, existing
  group membership): idempotent skip with a `→ already present` note.
- **shape** (malformed CSR, unreadable cert, wrong CA chain): stop, do
  not retry, exit non-zero.

## RFD 2195 gotchas each command internalises

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
  tokens live 8 h, and the file survives rotate and migrate. On
  2026-09-04 one agent's file held another agent's identity and a
  second held a token minted before its group mapping attached. Every
  peer command deletes `~/.bao-token` before `bao login`, and `status`
  asserts `entity_id` against the agent's own alias before anything
  else. Nothing is writable *under* a row (`…/heartbeats/<ts>` is
  `deny`); the row is the row.

## Non-goals

- Not a general Bao client; only the calls the shepherd commands need.
- Not a policy editor; changes to `agents-rw` or `mps-admin` are done
  by hand through `weftspun/dot-claude` review.
- Not a group definer; `shepherd` reconciles memberships, but the
  groups themselves are declared in RFD 2202.
