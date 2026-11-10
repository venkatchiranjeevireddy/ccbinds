# CCB India development roadmap

This roadmap is ordered by dependencies. Code presence does not mean a hosted migration or a live provider setting is complete. Current evidence is summarized in [README](README.md); unresolved product choices are in [PENDING-DECISIONS](PENDING-DECISIONS.md).

## Current implementation

- Responsive public pages, allowlisted content routes, published data feeds and public intake forms.
- Supabase email/Google Member and Client flows, visible Turnstile form gate, separate role dashboards.
- Admin ID/password console with bcrypt-backed account table, Turnstile verification, seven-day session and CRUD modules.
- RLS schema for profiles, taxonomy, discovery, opportunities, applications, events, intake, content, subscriptions, payments, reviews, notifications and audit.
- Private R2 profile/logo and Member portfolio media upload, metadata, read authorization and short-lived URLs.
- Server-paginated Admin lists, Client discovery and Member opportunity feed; directory includes taxonomy, availability, experience, rate and rating filters.
- Database functions/migrations for trials, entitlements, publishing, applications, external event RSVP, taxonomy and notifications.
- TypeScript, production build and local route smoke checks pass. Connected Supabase Auth settings, public tables, R2 signing and Turnstile verification endpoint respond.

## Immediate setup blockers

1. Replace the current server-only Supabase key: read-only REST/Admin probes returned HTTP 401 for `SUPABASE_SECRET_KEY`; this prevents Admin and privileged server calls.
2. Apply SQL migrations 006 through 017 in order after confirming 001–005 are installed. The live `application_status_history` table is absent, confirming migration 009 is not installed.
3. Provision Admin IDs/password hashes with migration 005's SQL example, then sign in and verify the Admin console using the corrected server key.
4. Test a real Member and Client account after confirming Auth email verification and redirect behavior; no test accounts were created as part of this work.

## Phases and acceptance criteria

### Phase 1 — Foundation and live permission verification

**Work:** correct the server key, apply remaining migrations, provision Admins, review role policies and RPC grants. Confirm no service credential is browser-exposed.

**Accept when:** Member/Client Auth succeeds; Member cannot read another account's private rows; Client cannot manage another Client's opportunity; Admin can use Admin APIs but has no public signup; expired entitlements deny restricted actions; every migration is recorded as applied.

### Phase 2 — Public website and approved content

**Work:** CCB supplies verified legal/organizational copy, official contacts, approved leadership/partner details, events, and final images. Replace temporary manifest assets and preview mobile/tablet/desktop.

**Accept when:** every claim has CCB approval; public routes load published records only; unpublished data, private R2 objects and private intake records are not accessible to visitors.

### Phase 3 — Identity and profiles

**Work:** verify role selection, Google callback, email confirmation, display name, Member/Client profile editing, visibility, R2 profile photos/logos and private portfolio attachments.

**Accept when:** both roles can create/update their own profiles; unauthorized role edits fail in Postgres; file type/signature/size/owner checks reject invalid uploads; a private object cannot be read by another account or anonymous visitor.

### Phase 4 — Taxonomy, discovery and saved profiles

**Work:** Admin maintains the shared categories, roles, skills, tools and aliases from migrations 017; validate text, location, category, skill, experience and availability filters; complete server pagination for long personal activity lists.

**Accept when:** Member and Client/opportunity filters share the same taxonomy; discovery and Admin list count/page navigation matches database results; search history is owner-only; private contacts remain hidden.

### Phase 5 — Opportunities and applications

**Work:** exercise draft, publication, deadline, close/reopen, applications, withdraw, Client review, status timeline, completion and reviews.

**Accept when:** only the owning Client can change lifecycle/applicant state; Members cannot apply after deadline or without entitlement; duplicate applications/reviews fail; each status change is timestamped and visible to participants; only completed-engagement participants may review.

### Phase 6 — Admin operations and organizational intake

**Work:** run real Admin workflows for Members/Clients, taxonomy, membership applications, memberships, service/partnership enquiries, articles, awards and media. Define auditable staff procedure.

**Accept when:** Admin changes persist and audit records identify the Admin; internal notes are never returned to applicants; applicant records have tested participant/admin-only reads.

### Phase 7 - Programs and external Event RSVP

**Work:** validate event media, external HTTPS RSVP URLs, public/unlisted visibility, registration closure, completed/cancelled states, selected notification audience, and CCB event detail links. Existing native registrations remain historical only.

**Accept when:** invalid RSVP URLs cannot publish; closed events have no active RSVP button; event announcements reach selected in-app audiences; cancelled/completed events are clearly represented in Admin.

### Phase 8 — Notifications, subscription billing and payments

**Work:** choose email provider/templates; choose pricing/provider/refund/renewal policies; implement server order creation and signed idempotent webhooks. Add notification delivery preferences/retries only after provider choice.

**Accept when:** email failure does not lose in-app notices; payment success requires verified webhook; duplicate webhook cannot double grant access; cancellation/refund/past-due transitions are reconciled; Admin cannot fabricate browser-side payment success.

### Phase 9 — Advanced social and trust features

**Work:** obtain Meta app/permission review if needed; implement creator-authorized token handling and scoped insight sharing; define client verification, review moderation and reporting.

**Accept when:** no analytics are returned without provider permission and Member consent; tokens remain server-only; sync is timestamped; revocation removes future access.

### Phase 10 — Production readiness

**Work:** choose domain and a supported Cloudflare-compatible Next runtime, configure production callbacks/secrets/CORS, add monitoring/backups/restore, privacy/export/deletion and Admin MFA. Run role-based, responsive, accessibility, load and security checks.

**Accept when:** a restore exercise succeeds; R2 remains private; secrets are rotated and server-only; production OAuth/Turnstile URLs match; no known cross-role/private-data leak exists; error/incident ownership is documented.

## Dependencies and decision gates

- Phase 1 is required before any authenticated end-to-end acceptance.
- Phase 2 requires approved CCB text/media and must precede public launch.
- Phases 4–7 need taxonomy and event/membership rules from CCB.
- Phase 8 cannot be completed until the provider, price, renewal, cancellation and refund rules are approved.
- Phase 9 requires official Meta approval and explicit creator-sharing rules.
- Phase 10 depends on chosen hosting/domain and privacy/MFA/retention policy.

No phase should create fictional seed data to make an empty dashboard appear active.





## External Event RSVP and taxonomy changes

Migration 016 uses Admin-managed external RSVP URLs and keeps old registration history untouched. Migration 017 seeds the supplied taxonomy and adds stable-ID roles, tools, aliases, category relationships, suggestions, opportunity targeting, preferences, and rule-based matching. Validate the new Member and Client flows after applying those migrations.
