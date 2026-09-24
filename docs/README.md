# Suite documentation

Documents that span more than one member live here. A document about one member lives in that
member's `docs/`, indexed by the Documentation table of the member's own `README.md`, because every
member is also published as a repository of its own. The root [README.md](../README.md) is the
front door; the root [CLAUDE.md](../CLAUDE.md) is the working guide (rules, gates, generators).

## Which file do I want?

| If you are about to... | Read |
|---|---|
| sit down at an OXT engine | [OXT-PASS-RUNBOOK.md](OXT-PASS-RUNBOOK.md), then [OXT-ENGINE-NOTES.md](OXT-ENGINE-NOTES.md) |
| pick up open work, in code or on an engine | [WORK-PLAN.md](WORK-PLAN.md) |
| make, or look up, a call only the owner can make | [OPEN-DECISIONS.md](OPEN-DECISIONS.md) |
| wrap a new native library for OXT | [BINDING-PLAYBOOK.md](BINDING-PLAYBOOK.md) |
| work on the anonymous (Tor) transport of QuickShare or DHT Channels | [ONIONXT-INTEGRATION-PLAN.md](ONIONXT-INTEGRATION-PLAN.md) |
| publish a member, port a change made in its repository back here, or add or remove a member | [MEMBER-REPO-SPLIT.md](MEMBER-REPO-SPLIT.md) |
| build on Riptide, or interoperate with it | [RIPTIDE-SOCIAL-SPEC.md](RIPTIDE-SOCIAL-SPEC.md) (design), [RIPTIDE-PROTOCOL.md](RIPTIDE-PROTOCOL.md) (bytes) |
| find out what an extension does | the root [README.md](../README.md), then that member's `README.md` |
| learn the suite's rules, gates and generators | the root [CLAUDE.md](../CLAUDE.md) |

## The documents

- [OXT-PASS-RUNBOOK.md](OXT-PASS-RUNBOOK.md): how to run an engine session and what is still owed on one - the session plan, the open inventory with each row's green criterion and the labels it flips, install order and the exact `torrc`, what to record, the known traps, the tick sheet, and the closed engine record (section 8).
- [OXT-ENGINE-NOTES.md](OXT-ENGINE-NOTES.md): what the OXT engine actually does, each behaviour with its verbatim symptom, rule and gate, classed OBSERVED, INFERRED, DOCUMENTED or UNEVIDENCED and numbered stably because the tree cites it ("engine note 5.5").
- [WORK-PLAN.md](WORK-PLAN.md): the one live list of open work, per member and suite-wide - coding work, engine work (which session, what green looks like, which labels flip) and owner calls.
- [OPEN-DECISIONS.md](OPEN-DECISIONS.md): the owner decision log, D-01 onward, one row per decision (outcome, date, where it is recorded), plus the brief of any decision still open.
- [MEMBER-REPO-SPLIT.md](MEMBER-REPO-SPLIT.md): publishing every member into its own repository while development stays here (live since 2026-09-23) - the model, setup, porting a change back, the sibling layout, and what a departing member must be removed from.
- [BINDING-PLAYBOOK.md](BINDING-PLAYBOOK.md): wrapping a native C/C++ library for OXT the way the native members do - the house pattern, the three rules, the FFI contract, handles and records, threading, toolchain traps, the definition of done.
- [ONIONXT-INTEGRATION-PLAN.md](ONIONXT-INTEGRATION-PLAN.md), titled "Model C - the anonymous transport": the optional Tor onion path of QuickShare and DHT Channels (design, threat model, onboarding, the VERIFY register, decisions); code cites its section numbers.
- [RIPTIDE-SOCIAL-SPEC.md](RIPTIDE-SOCIAL-SPEC.md): the design authority for Riptide Social - rails, rules, the security model, the phase roadmap with dated status, decisions; code cites its section numbers.
- [RIPTIDE-PROTOCOL.md](RIPTIDE-PROTOCOL.md): the implementation-neutral wire specification, normative for the bytes, with a conformance bundle (`riptide/docs/protocol-vectors.json`) re-executed on every push.

One capstone spec lives in its member: [holde-em/holdem-spec.md](../holde-em/holdem-spec.md), the
design of serverless Texas Hold'em.

Every open item in these documents is a claim about the tree on the day it was written: check it
against the tree before spending an engine minute on it. Dated records and quoted member accounts
keep their original member-root-relative path spellings; resolve those under the member their
context names.
