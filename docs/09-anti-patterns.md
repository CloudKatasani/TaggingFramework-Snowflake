# 9. Anti-Patterns

Failure modes seen repeatedly in large Snowflake estates, and what this framework
does about each. Where a mitigation is mechanical rather than procedural, that is
stated — procedural mitigations decay, mechanical ones do not.

---

### AP-01 · Tags nobody reads

**Symptom.** 180 tags, of which eleven appear in any report, policy or job.
Stewards spend hours filling in metadata that changes nothing.

**Why it happens.** Tags are cheap to create and every one is *useful in
principle*. Nobody is ever asked to name the system that will read it.

**Cost.** Stewardship effort spent on nothing, and — worse — the credibility of
the tags that do matter is diluted. When most tags are decorative, all tags are
treated as decorative.

**Mitigation (mechanical).** `drives` is a required, non-empty field;
`validate_catalog.py` fails the build without it. `VW_TAG_ADOPTION` reports usage
per tag and the quarterly review retires the `UNUSED` and `MARGINAL` ones.

---

### AP-02 · Free text where a vocabulary belongs

**Symptom.** `cost_center` contains `CC-1234`, `cc1234`, `1234`, `Marketing` and
`TBD`. The chargeback report shows five cost centres where there is one.

**Why it happens.** Free text is faster to ship and never rejects an input.

**Cost.** The tag cannot drive automation at all. Every consumer has to normalise,
each does it differently, and the numbers stop reconciling.

**Mitigation.** Three explicit value sources with enforcement attached to each
(§8.2). `VW_TAG_ADOPTION` flags `HIGH CARDINALITY - not automatable` when a
free-text tag's distinct values approach its assignment count — at which point it
is a comment field, not a tag.

---

### AP-03 · Tagging every column

**Symptom.** A mandate that every column carries `data_classification_enterprise`. Three
hundred million findings. The programme is abandoned in month four.

**Why it happens.** Column level is where masking happens, so it feels like the
right level to demand everything.

**Mitigation.** Column obligations are scoped to columns in tables already flagged
as regulated or sensitive (`VW_COLUMN_IN_SCOPE`, §3.4). Everything else inherits.
Two mandatory column tags, not seventeen.

---

### AP-04 · Tag proliferation by dimension

**Symptom.** `PROD_DATA_OWNER`, `DEV_DATA_OWNER`, `EU_DATA_OWNER`,
`EU_PROD_DATA_OWNER`. Twelve tags expressing one concept across two dimensions.

**Why it happens.** A tag holds one value, so people encode the second dimension
in the name.

**Mitigation.** Dimensions are separate tags, never name components (§8.1). Where
a genuine multi-value need exists, the governing-value + scope-table pattern
(§2.3) is used — once, deliberately.

---

### AP-05 · `CREATE OR REPLACE TAG`

**Symptom.** A routine deployment silently removes every assignment of a tag
across the estate and detaches its masking policy. Nothing errors. Data that was
masked yesterday is in clear today.

**Why it happens.** `CREATE OR REPLACE` is the idiom for every other Snowflake
object and it is what a deployment script naturally contains.

**Cost.** Potentially the most serious failure in this list, and the hardest to
notice — the tag still exists, so nothing looks missing.

**Mitigation (mechanical).** The generator emits only
`CREATE TAG IF NOT EXISTS` + `ALTER TAG`. `scripts/lint_sql.py` fails CI on any
`CREATE OR REPLACE TAG` or `DROP TAG` anywhere in the repository.

---

### AP-06 · Declared but not enforced

**Symptom.** `MASKING_REQUIRED = YES` on 4,000 columns; masking policies attached
to 300. Compliance reports green because they measure tags, not policies.

**Why it happens.** The declaration and the enforcement are different objects, and
only the declaration is tagged.

**Cost.** False assurance, which is worse than known non-compliance: the
organisation makes decisions — sharing, access, audit responses — on the basis of
a control that is not there.

**Mitigation.** `SP_DETECT_POLICY_DRIFT` compares declared bindings against
`ACCOUNT_USAGE.POLICY_REFERENCES` hourly; divergence is CRITICAL and pages.
`VW_COMPLIANCE_EVIDENCE.CONTROL_STATE` answers declared-vs-enforced per object.

---

### AP-07 · Clone-propagated tags

**Symptom.** UAT objects tagged `ENVIRONMENT = PROD`. UAT compute billed to the
production cost centre. The promotion gate believes UAT objects passed production
review.

**Why it happens.** `CLONE` copies tags, which is correct for almost every tag and
exactly wrong for `environment`.

**Mitigation.** `SP_REMEDIATE_CLONE_TAGS` as a mandatory final step of every clone
runbook; `environment` has `override_rule: none` so the value cannot be
locally patched around. `data_quality_tier` carried in by clone raises a finding —
certification is earned, not copied (§4.6).

---

### AP-08 · Classification by classifier alone

**Symptom.** `data_classification_regulatory` (PII) is whatever Snowflake's classifier last decided. A steward's
considered override is reverted overnight. Encoded identifiers and free-text notes
containing personal data are never flagged.

**Why it happens.** Auto-classification is genuinely good, and treating it as the
answer removes a large manual workload.

**Cost.** Nobody is accountable for a probabilistic inference. "The classifier said
so" is not a defensible position in a regulatory conversation.

**Mitigation.** Classifier output is a *proposal*: auto-applied only where no human
has ruled, never overwriting `HUMAN_OVERRIDE` (§6.4). Overrides without a recorded
reason are surfaced for review, which keeps the override path honest.

---

### AP-09 · Nearest-wins for security tags

**Symptom.** A column inside a `RESTRICTED` table is tagged `PII = NO` to silence
a false positive. The masking policy stops applying to it. Nobody notices.

**Why it happens.** Nearest-wins is the intuitive inheritance rule and it is
correct for descriptive tags, so it gets applied uniformly.

**Cost.** This is the most common way tag-based masking is defeated in practice,
and it is usually done by someone acting in good faith.

**Mitigation.** `override_rule: more_restrictive_only` on every control tag,
enforced on **both** paths: `SP_APPLY_TAG` rejects the weakening assignment, and
`VW_EFFECTIVE_TAG` resolves by ordinal severity even if one were made outside the
procedure. The read path does not trust the write path (§4.3).

---

### AP-10 · Governance in a spreadsheet

**Symptom.** The authoritative tag list is a spreadsheet. The deployed tags
diverged from it eight months ago and nobody knows in which direction.

**Mitigation.** `config/tag_catalog.yaml` is the source of truth; SQL, Terraform
variables and documentation are generated; CI fails when any generated artifact is
stale. Divergence is not detected — it is impossible.

---

### AP-11 · Permanent exceptions

**Symptom.** An exception register with 400 entries, the oldest from 2019, most
with no expiry. Compliance reports 99%.

**Mitigation.** `EXPIRES_AT` is `NOT NULL`. Expiry re-raises the finding at HIGH
rather than closing it. Renewal requires fresh justification, not a date change.
`OPEN_EXCEPTIONS` sits on the executive dashboard next to the compliance
percentage, because the two numbers only mean something together (§8.5).

---

### AP-12 · Granting `APPLY TAG` broadly

**Symptom.** Every steward holds `APPLY TAG ON ACCOUNT` — because Snowflake offers
no narrower scope — and can therefore retag any object in the account, including
another domain's `RESTRICTED` columns.

**Why it happens.** It is the only way to let stewards do their job with raw
grants, and Snowflake provides no database-scoped alternative.

**Mitigation.** `APPLY TAG` is granted to exactly one role. `SP_APPLY_TAG` is an
owner's-rights procedure that lends the privilege out subject to registered domain
ownership, value validation and override rules, and logs every change with a
mandatory reason (§5, `sql/40_procedures/00_apply_tag.sql`).

---

### AP-13 · Tagging views and forgetting CTAS

**Symptom.** A carefully classified table is copied by `CREATE TABLE AS SELECT`
into an untagged table. Masking does not follow. The copy is shared externally.

**Why it happens.** Tags are object metadata; CTAS creates a new object.

**Mitigation.** Partial, and stated as such: the nightly scan finds untagged
tables within 24 hours, and the classifier re-detects the PII in the same window.
CI/CD tags objects at creation for anything deployed through the pipeline.
Ad-hoc CTAS in a personal schema remains a genuine residual risk, which is why
non-production databases are excluded from sharing eligibility entirely (§4.5).

---

### AP-14 · Measuring tag count as coverage

**Symptom.** "We are 94% tagged." The 6% untagged is the entire finance domain.

**Why it happens.** A single account-wide percentage is the easiest number to
produce and the easiest to report upward.

**Mitigation.** `COMPLIANCE_SCORE_HISTORY` records coverage by `operating_company` and
`domain`, not only account-wide, and `VW_COMPLIANCE_DASHBOARD` shows the 30-day
delta per scope. A stalled domain is visible rather than averaged away.

---

### AP-16 · Split classification without a contradiction check

**Symptom.** A table is tagged `data_classification_regulatory = PCI` and
`data_classification_enterprise = PUBLIC`. Both mandatory tags are present, so
coverage reports 100%. The masking policy reads the enterprise classification,
sees `PUBLIC`, and returns cardholder data in clear.

**Why it happens.** Splitting classification into an enterprise level and a
regulatory category is the right model — they answer different questions — but it
creates a state where two individually-valid values are jointly impossible. Every
coverage metric is blind to it, because coverage metrics count presence.

**Cost.** The worst combination available: a real exposure that reports as fully
compliant. It survives audits precisely because the dashboard is green.

**Mitigation (mechanical).** Contradiction rules (§3.3b). XR-001 fires CRITICAL
on regulated data classified `NONE` or `PUBLIC`; `VW_COMPLIANCE_EVIDENCE`
surfaces it as its own `CONTROL_STATE`. Conditional rules catch absence,
contradiction rules catch presence-and-wrong, and a framework with only the first
kind is blind to this entire class.

---

### AP-17 · One tag key, two platforms, two buckets

**Symptom.** The AWS cost report shows `operating_company` and
`Operating_Company` as separate dimensions. Snowflake shows one. The
cross-platform reconciliation is out by 30% and nobody can find where.

**Why it happens.** AWS tag keys are case-sensitive; Snowflake folds unquoted
identifiers to upper case. A key written inconsistently in Terraform is two tags
on AWS and one in Snowflake, and neither platform reports an error.

**Mitigation (mechanical).** One canonical lowercase key in the catalog, with the
folded Snowflake identifier derived rather than typed. `validate_catalog.py`
fails the build if two canonical keys fold to the same Snowflake identifier, and
`CONTROL.TAG_CATALOG` stores both forms so each join uses the right one (§12.1).

---

### AP-15 · The big-bang rollout

**Symptom.** Six months of design, then a mandate that all 4,000 databases be
fully tagged by quarter end. Nothing is tagged by quarter end.

**Mitigation.** The phased roadmap in §11, top-down so inheritance does most of
the work, prioritised by consumption so the first visible win arrives in week one
(§6.7). Sponsorship is renewed by demonstrated value, not by plan adherence.
