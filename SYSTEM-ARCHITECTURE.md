# System architecture

## Current topology

```mermaid
flowchart LR
  Visitor[Public visitor] --> Next[Next.js public site]
  Member[Member / Influencer] --> Next
  Client[Client / Business] --> Next
  Admin[Privately provisioned Admin] --> Next
  Next --> Auth[Supabase Auth]
  Next --> DB[(Supabase PostgreSQL + RLS)]
  Next --> R2[Private Cloudflare R2]
  Admin --> AdminAPI[Admin session protected route handlers]
  Member --> MediaAPI[Authenticated media route handlers]
  Client --> MediaAPI
  MediaAPI --> DB
  MediaAPI --> R2
  AdminAPI --> DB
  AdminAPI --> R2
  Google[Google OAuth] --> Auth
  Turnstile[Cloudflare Turnstile] --> Next
```

The public pages, Member workspace, Client workspace, and Admin console share a Next.js app and Supabase project but have separate route groups and authorization. Member and Client authenticate with Supabase Auth. Admin uses a separate manually provisioned ID/password table and a signed seven-day HttpOnly cookie. The Admin session is not a Supabase end-user session.

## Private media flow

```mermaid
sequenceDiagram
  participant U as Member or Client browser
  participant N as Next.js media endpoint
  participant S as Supabase Auth/Postgres
  participant R as Private R2
  U->>N: Request signed upload parameters (Supabase session)
  N->>S: Verify user and role
  N->>R: Sign scoped object PUT
  N-->>U: Short-lived PUT URL
  U->>R: Upload bytes
  U->>N: Complete upload
  N->>R: Verify object exists and metadata
  N->>S: Store owner, object key and visibility
  U->>N: Request media by id
  N->>S: Apply RLS and ownership/visibility authorization
  N->>R: Sign short-lived GET only if allowed
  N-->>U: Redirect to signed GET
```

Objects remain private. R2 credentials and Supabase service credentials run server-side only. Admin media routes use the separate Admin session. Worker deployment is not active; Next.js route handlers implement the current backend boundary. If production hosting requires Workers, preserve these authorization checks when adapting the handlers.

## Trust boundaries

- Supabase Auth proves the identity of Member and Client sessions; database role/profile and RLS govern data access.
- Admin identity is independently checked against `admin_accounts`; password hashes are bcrypt and sessions are signed with `ZADMIN_SESSION_SECRET`.
- Public content is read only when published. Public-member discovery excludes private contact data and depends on profile visibility and Client entitlement.
- Ticket tokens are random opaque values; only SHA-256 hashes are persisted. Ticket verification and check-in are backend operations, and attendance is atomic.
- RLS is not replaced by hiding interface controls. Migrations 0006–0011 add explicit workflow functions and safe-profile policies; review the policies on the target Supabase project before production.

## External services not connected

Payments, outbound email/SMS, official Meta/Instagram data access, Cloudflare deployment, domain and production callback URLs remain pending. Do not substitute browser-side secrets or trust a payment success redirect.


## Authentication and role routing

```mermaid
sequenceDiagram
  participant U as User
  participant W as Next.js auth page
  participant T as Cloudflare Turnstile
  participant S as Supabase Auth
  participant D as PostgreSQL profile/RLS
  U->>W: Choose Member or Client
  W->>T: Render widget
  T-->>W: Verified token
  U->>W: Submit email/password or Google
  W->>S: Sign in/up with selected role metadata and token
  S-->>W: Session or OAuth callback
  W->>D: Read account_type from profile
  D-->>W: Authoritative role
  W-->>U: Route to matching dashboard
```

The chosen role guides signup, but the database profile decides access. OAuth callback does not grant Admin role. Admin login uses a separate endpoint/table/cookie and is not part of this sequence.

## Member and Client data flows

```mermaid
flowchart LR
  M[Member] --> MP[Edit Member profile and portfolio]
  MP --> RLS1[Owned writes under RLS]
  MP --> O[Browse published opportunities]
  O --> APP[Submit/withdraw application]
  APP --> RC[Owning Client reviews]
  RC --> H[Status change RPC/history]
  H --> M
  C[Client] --> D[Discover public Members]
  D --> S[Save profile or submit enquiry]
  C --> W[Create opportunity draft]
  W --> P[Entitled publish transition]
  P --> O
  C --> Q[Separate CCB service request]
  Q --> AD[Admin intake queue]
```

## Event and ticket flow

```mermaid
sequenceDiagram
  participant A as Admin
  participant DB as Supabase
  participant U as Signed-in attendee
  participant Q as QR scanner/Admin API
  A->>DB: Publish event, form fields, policy and capacity
  U->>DB: Call register_for_event RPC with fields
  DB->>DB: Validate window, capacity, policy, duplicate and values
  DB->>DB: Store registration and SHA-256 token hash
  DB-->>U: Return opaque token once for QR display
  U->>DB: Optional ticket rotation or cancellation
  DB->>DB: Rotate hash or revoke ticket
  Q->>DB: check_in_event_ticket(token)
  DB->>DB: Lock ticket, validate eligibility, insert unique attendance
  DB-->>Q: Return check-in result or reject duplicate
```

## Entitlement flow

```mermaid
flowchart LR
  Signup[Member/Client role established] --> Trial[Seven-day trial row]
  Trial --> Feature[Role-specific entitlement rows]
  Request[Protected action] --> Identity[Verify session and database role]
  Identity --> Entitlement[Check has_entitlement and dates]
  Entitlement -->|enabled and active| Allow[Continue action]
  Entitlement -->|missing or expired| Deny[Reject in database]
  Admin[Admin plan configuration] --> Paid[Future verified payment/webhook]
  Paid --> Subscription[Future subscription state]
  Subscription --> Entitlement
```

No paid provider is wired; the lower payment path is future architecture, not an active checkout.

## Component boundaries and operations

- **Public UI:** renders approved static content plus published database listings; anonymous RLS grants do not include private identity or workflow records.
- **Member/Client UI:** presents role-specific actions and reads/writes through session-bound Supabase clients under RLS; high-risk lifecycle changes use RPCs.
- **Admin UI:** sends resource operations to `/api/zadmin/*`; endpoints revalidate the distinct Admin session, then use the server-only Supabase key. Do not infer Admin authorization from a browser role.
- **Media API:** `/api/media` creates caller-scoped R2 PUT signatures, verifies size/type and file signature at completion, stores metadata through the caller's Supabase session, and returns a short-lived read only after RLS allows the media row.
- **Event check-in API:** requires Admin cookie and sends token to a service-only RPC; the token hash is compared atomically in Postgres.
- **Infrastructure:** Cloudflare R2 and Turnstile are configured; production Next hosting, Worker adapter, custom domain, monitoring and CI/CD are not.







