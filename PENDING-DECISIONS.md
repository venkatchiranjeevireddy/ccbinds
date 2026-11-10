# Pending decisions and external setup

The implementation must not invent CCB policy, prices, endorsements, partner names, legal status or official statistics. These decisions affect database semantics, public claims and user access.

| Decision | Why it matters | Options to consider | Suggested default pending approval | Current status |
|---|---|---|---|---|
| Member/Client subscription plans, price, cadence, renewal and refund rules | Determines entitlements, checkout, billing disclosures and lifecycle | Free-only launch; manual invoicing; recurring plans through an Indian payment provider | Keep the 7-day trial and basic profile access; do not charge until written plan/refund rules are approved | Schema and trial exist; paid billing is off |
| Payment gateway and settlement account | Required only if CCB later enables paid plans | Razorpay or another provider CCB can contract with | Keep payments off for the current phase | Deferred; no payment gateway needed now |
| Email sender/provider, templates and sender domain | Needed only for app-generated email announcements and status notices | Supabase Auth SMTP; transactional mail provider | Keep in-app notifications for now; select an email sender later if needed | Deferred; event publishing currently sends in-app notices only, no announcement email |
| Membership categories, eligibility, benefits, fees and review | Controls membership intake and public membership claims | Admin-managed categories and review queue; direct enrollment only if rules allow | Application plus Admin review until CCB confirms otherwise | Application workflow exists; official rules/content missing |
| Training experience scope | Full course delivery is outside the current phase | Revisit lessons/materials, cohorts/sessions, completion tracking and certificates later | Keep current published Programs and enrollment; show full courses as coming soon | Deferred; coming-soon note added; no course system needed now |
| Member-to-Client contact mechanism and data sharing | Protects personal contact data and sets expected response behavior | Platform enquiry; reveal opted-in email; internal messaging | Use the platform enquiry and do not expose personal email by default | Enquiry form/inbox exists; broader contact rules pending |
| External Event RSVP policy | Defines who receives links and when RSVP closes | Admin-managed HTTPS form; audience can be Members, Clients or both | CCB publishes event details and redirects to external RSVP | Implemented in source and included in the consolidated SQL setup; hosted state is not independently verified |
| Event status and media approval | Controls public pages and media visibility | Draft/published/completed/cancelled; public media IDs attached from private R2 | Publish only HTTPS RSVP URLs and media explicitly marked public | Event media/gallery source is implemented and included in the consolidated SQL setup; hosted state is not independently verified |
| Meta/Instagram permissions, use cases and app owner | Private analytics require official OAuth, eligible accounts and approval | No integration; creator-authorized approved Meta app | Keep URLs-only until the organisation owns an approved Meta application | Not connected |
| Client verification and opportunity moderation | Determines marketplace trust and publication risk | Verify all clients; verify only high-risk; publish immediately; Admin review | Require Admin review before marking a Client verified; decide publication policy before launch | Verification schema exists; policy pending |
| Admin MFA, seat count and credential rotation | Protects privileged access | MFA via identity provider; additional factor; separate hardware-backed process | Add MFA before production; provision only named Admins and rotate credentials on role change | Custom ID/password, bcrypt and 7-day session exist; MFA absent |
| Privacy notice, retention, export/deletion and incident process | Required for responsible handling of user, event and contact data | Retain only operationally needed fields; policy/legal review | Approve privacy and retention rules before opening public signup | Not implemented/approved |
| Hosting, domain, Cloudflare Workers/Pages adapter and production routes | Needed when publishing the app to a live domain | Cloudflare Workers/OpenNext; another Next-compatible host; split frontend/API only if needed | Test locally first; configure production hosting only when ready to deploy | Deferred; local development does not require deployment setup |
| Official CCB copy, legal details, leaders, partners, events and assets | Prevents false public statements and placeholder media | Supply approved copy/media; omit unknown claims | Publish only verified details; leave unknown fields absent | Must be supplied/approved by CCB |
| Search scale and social insight audience | Affects indexes, privacy and future infrastructure | PostgreSQL filters; separate search only after measured need; sharing to all entitled clients vs selected clients | Keep PostgreSQL search, paginate, and require explicit creator sharing | Client discovery and Member opportunity feeds are server-paginated; migration 018 adds indexed Member opportunity search and filters; long personal activity pagination and social insights remain incomplete |

## External setup checklist

### Supabase

- The connected project has email and Google providers enabled, and public content tables are reachable.
- An earlier read-only check of `SUPABASE_SECRET_KEY` returned HTTP 401 on PostgREST and Auth Admin API requests. If connections still fail, replace it with a current server secret/service-role key from the **same project**; then restart the app. Do not share it in chat.
- The screenshots showed the base schema and `admin_id` / `password_hash` Admin columns. The user reports that `supabase/ccb-current-db-setup.sql` has since succeeded; hosted migration state has not been independently rechecked. Do not rerun that bundle. Run `supabase/ccb-opportunity-search-update.sql` once to enable Member opportunity search (migration 018).
- Keep Admin rows private and insert password hashes using the bcrypt example in migration 005.
- Local callback: `http://localhost:3000/auth/callback`. Configure the matching Supabase redirect and Google Cloud callback. Add the production callback only after domain selection.

### Cloudflare

- The configured Turnstile server secret was accepted by Cloudflare; a deliberately invalid token was rejected as expected. Add `localhost` and the production hostname to the widget's domains and confirm its site key matches `NEXT_PUBLIC_TURNSTILE_SITE_KEY`.
- A signed HEAD probe of a nonexistent R2 key returned 404, confirming current R2 credentials can reach the bucket without reading/writing objects. Keep public bucket access disabled and retain the current CORS origin/PUT/Content-Type configuration.
- Use scoped credentials and keep all R2 values server-only.

### Local and production

- Copy `.env.example` to `.env.local`; supported server-key variable names are `SUPABASE_SECRET_KEY` and the legacy `SUPABASE_SERVICE_ROLE_KEY`.
- Use `npm.cmd run dev` from PowerShell. Production hosting, domain, OAuth/Turnstile hostname, secrets and R2 CORS must be configured together after choosing the supported runtime.

Keep `.env.local` private. Never paste credentials into chat or commit them.





- Search implementation: Client creator discovery and Member opportunity search both use database-backed filters and pagination. Migration 018 supplies indexed keyword/taxonomy search for opportunities.
