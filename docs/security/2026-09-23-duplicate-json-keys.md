# Duplicate keys in a signed JSON body

**Date:** 2026-09-23 · **Status:** NOT EXPLOITABLE

## Why this was looked at

Dependabot proposed `json` 3.0 (PR #4). It cannot be merged yet, because Rails 8.1.3.1
passes parser options positionally and json 3.0 accepts keywords only, so the app does not
boot; the fix is `rails/rails@cc07aa315`, backported to `8-1-stable` and not yet released.
Reading its changelog raised a separate question: json 3.0 rejects duplicate keys by
default, and the `json` 2.21.2 this node runs **accepts them silently, keeping the last**:

```ruby
JSON.parse('{"a":1,"a":2}')   # => {"a"=>2}, no warning
```

Signed contributions arrive as JSON. If the signature were checked over one reading of a
body and a different reading were recorded, a relayer could slip unsigned content into the
log under someone else's key.

## Scope

The three paths on which a client signature is verified over JSON from outside:
`ContributionsController#envelope_from_body` → `Contributions::ValidateEnvelope`,
`Api::V1::TasksController` → `Contributions::SignedRequest.verify!`, and
`Api::V1::AdminController` → `Admin::Request.verify!`. Not covered: the MCP and OAuth
endpoints, which carry no client signature, and any mirror or external verifier, which
reads stored envelopes rather than request bodies.

## What was checked

Every path does the same three things, in order:

1. **Parses the raw body once**, with Ruby's `json`.
2. **Verifies the signature over `Crypto::CanonicalJson` of what was parsed**, not over the
   raw bytes (`Contributions::Envelope.signed_bytes`, `SignedRequest.verify!`,
   `Admin::Request.verify!`).
3. **Acts only on the parsed object.** A contribution stores it, so the recorded envelope
   is exactly the object whose canonical form was verified, and `Ledger::Verify` recomputes
   from that stored form. A lease or an admin request stores nothing signed; it acts on the
   `payload` of the same parsed, verified body.

There is one parser and one reading, so there is nothing for two readings to disagree
about. Canonical JSON (RFC 8785) cannot contain a duplicate key, so a signer can only ever
have signed an object with one value per key. A duplicate-key body therefore verifies only
if its last-wins reading **is** the signed object, and then that object is what is
recorded. A forged value placed first is overwritten by the signed one. A forged value
placed last changes the parsed object, so it fails `PAYLOAD_HASH_MISMATCH`, or
`SIGNATURE_INVALID` if the forger recomputes the hash too.

The one thing a relayer can do is add junk alongside a signed field. It changes nothing
recorded: the envelope hash, idempotency key and stored envelope are all computed from the
parsed object.

## Evidence

`spec/requests/api/v1/contributions_spec.rb`, "a body carrying a signed field twice":

- a genuine envelope with a second, forged `payload` spliced in **before** the signed one
  is accepted, stores the signed payload, verifies (`client_signature_ok`, `chain_ok`),
  and creates no claim from the forged text;
- the same forgery spliced in **after** is refused with `PAYLOAD_HASH_MISMATCH`, and a
  forged payload with its own matching hash is refused with `SIGNATURE_INVALID`; nothing is
  appended in either case;
- each spliced body is asserted to carry the key twice, so the test cannot pass by never
  sending the duplicate.

## What would make this wrong

- **A second parser.** Anything that reads the raw body with a first-wins or different
  parser and acts on it — a proxy, a WAF rule, a logging pipeline that routes on a field —
  reintroduces a differential. `rate_limit_key` in the contributions controller parses the
  body a second time, with the same library and therefore the same reading; it decides only
  the rate-limit bucket.
- **Verifying raw bytes but storing a parse, or the reverse.** The guarantee rests on the
  signed bytes and the stored object coming from the same parsed value.

## After json 3.0

Duplicate keys will be refused at parse time (`allow_duplicate_key: false`), so the first
case becomes a `SCHEMA_INVALID` rather than an accepted contribution. That is a tightening,
not a fix: nothing here depends on it, and the spec's first case will need its expectation
changed to a refusal when the upgrade lands.
