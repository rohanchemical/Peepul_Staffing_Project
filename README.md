# Peepul · People & Resource Planning

MIT-licensed React, TypeScript, Vite, Recharts, Lucide and Supabase/PostgreSQL dashboard. Supabase holds operational data and identities; this public GitHub repository holds source code and schema migrations only. Employee data, passwords, tokens and source workbooks must never be committed.

## Capabilities

- Email/password login and `superadmin` username alias. Microsoft Azure OAuth/PKCE is wired into the login; organisation-owned Entra configuration is required to activate it.
- Four server-enforced roles: Superadmin, Data Administrator, Senior Leadership and Programme Manager. Programme Managers access their assigned programme only. Salary-cost access and leadership approval authority require explicit grants.
- Superadmin **Users & access → Add user** creates a confirmed account, assigns its programme/role and shows a generated temporary password once. No invitation email is sent. Share those details securely. The first login must change the temporary password before data becomes accessible. Reset passwords, deactivate accounts and update access from the same view. The account endpoint prevents changing one's own administrative access.
- Data Administration is the editable source: programmes/functions, six-role staffing plans, workforce ratios/surge, dated people roster, authorised grade-cost assumptions, annual budgets, twelve-month phasing, actuals/commitments/forecasts, grants and period closing.
- Source saves refresh linked staffing, promotion/hiring, budget, monthly and funding views. Workbook promotion paths and senior-priority hiring rules are calculated from source records, rather than imported cached totals.
- Annual original/revised budgets, budget versus actual, remaining commitments and year-end projections. Missing actuals or forecasts prevent a complete EAC. Future forecasts include commitments: use the larger per month, never add them twice.
- Programme-specific illustrative annual templates (₹240 lakh, seven categories, twelve months) are generated on demand and isolated using `is_sample`. These values are fictional and never count as operational Peepul data. No real financial records are invented.
- Scenario playground: role-specific hires, bounded promotions, planned exits, hiring timing, pay/travel/technology changes and funding/budget assumptions. Explore 27 combinations, save outcome/input snapshots and compare them. Scenarios and transfer tests do not change source records or authorise personnel decisions.
- Audited source updates, budget approvals, monthly closing, CSV exports and quality checks. Closed actuals cannot be changed, moved or reclassified; reopening requires approval authority.

## Access

| Role | Scope | Source entry | Users | Approvals |
|---|---|---|---|---|
| Superadmin | All programmes | Yes | Create/manage/reset/deactivate | Yes |
| Data Administrator | All programmes | Yes; costs only when granted | No | May close actuals; cannot approve/reopen |
| Senior Leadership | All programmes | Read only | No | Only when explicitly granted |
| Programme Manager | Assigned programme | Read only | No | No |

New Microsoft sign-ins receive an inactive membership. Superadmins activate and assign access. Roles never come from user-editable identity metadata. All operational tables use RLS. Secret service credentials remain exclusively in Supabase's Edge Function environment; the function verifies every bearer token using `auth.getUser` and checks current membership on every request. The gateway's `verify_jwt=false` supports the project's key configuration; it does not remove application authentication.

## Run and validate

Node 24+ recommended for the test runner; Node 22.12+ supports the frontend build.

```sh
npm ci
cp .env.example .env
npm run dev
npm run build
node --experimental-strip-types scripts/model.test.ts
node scripts/edge.test.mjs
```

The model tests cover the workbook promotion pathway, staffing conservation, cap-limited hiring, dated roster, phasing, incomplete forecasts and commitment treatment. Endpoint tests run against isolated authentication/database mocks; they do not create live administrators. The existing `scripts/verify-access.mjs` is an optional destructive-to-test-account integration check: it changes the supplied account password, so never use it with a personal administrator account.

## Supabase and deployment

Apply tracked migrations in order, then deploy `supabase/functions/people-account/index.ts`. A trusted project owner must provision the first administrator separately. New accounts are then created through the application. The initial `superadmin` alias maps to `superadmin@staffing.peepulindia.org`; it is not a mailbox. Keep its user-chosen password outside GitHub. Use named individual administrators for daily operations.

Frontend build: `npm run build`; static directory: `dist`. The existing Site association is preserved in `.openai/hosting.json`. Deployment to an alternative static host is supported. Update the exact production origin in the Edge Function's `allowedOrigins` and the Supabase Auth redirect allow-list when moving hosts. Public configuration can be supplied using `.env.example`; never place server secrets in Vite variables. `public/_headers` contains the CSP and security headers.

## Microsoft activation

1. Register a Web application in Peepul's Microsoft Entra tenant.
2. Set callback URI to `https://yfhdcrhocslhhlmgpexl.supabase.co/auth/v1/callback`.
3. In Supabase Authentication → Sign-in / Providers → Azure, enter the client ID, client-secret value and organisation tenant URL directly. Do not commit or share the secret in frontend code.
4. Follow Supabase's current Azure documentation for verified email claims. The app requests the `email` scope.
5. Set Supabase Site URL and allowed redirect to the deployed app origin.
6. Test with an organisation account, then activate its membership through Users & access.

## Source and planning assumptions

The connected database contains the supplied workbook's five programmes, thirty six-role source rows and 154 imported roster records. Imported roster IDs are synthetic (`WORKBOOK-…`); joining dates remain unknown. Aggregate baseline counts drive headcount until an administrator deliberately enables roster-based counting for a programme. Counts and FTE are distinct. Unknown central-function data is not manufactured.

Original within-layer junior/senior ratios (1, 3, 2) and surge allowances (4, 2, 0) are retained. Cross-layer 1:3:9 is an **unratified planning assumption** until approved. Individual promotion readiness and CEO exceptions remain human decisions. Old pilot summary/layer/monthly tables are retained for migration history; the current dashboard derives results from the new source tables.

## Operational limits

Microsoft login remains pending tenant configuration. End-to-end authenticated browser user creation has not been tested against the owner's live account; endpoint authorisation and payload behaviour are covered by isolated tests. Free hosted services have usage quotas and may pause. Supabase's leaked-password protection is currently disabled; review the provider's availability/settings before broader rollout. Set up independent encrypted backups and test restoration before treating this workspace as the sole operational record.
