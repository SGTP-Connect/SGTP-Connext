# Shared rota and private finance activation

Prepared for preview; live migrations and access are not yet verified. Demo links continue to use fictional, unsaved data.

1. Inspect the existing Supabase project and confirm migration 001 is present. Do not rerun 001 on an existing database. Apply 002_guest_rota.sql, then 003_finance.sql. Both new migrations are repeatable and preserve existing data.
2. Verify the owner's confirmed auth user, then explicitly grant the required coordinator role in rota_members and separately add the authorised user ID to finance_members. Never grant access from a public form, role dropdown, or unverified email claim. Other coordinators do not automatically receive finance access.
3. Allow exact preview auth redirects for /rota/manage.html, /rota/?admin=1 and /budget/live.html. Keep the existing /rota/ redirect. Production equivalents belong to a separate approved production rollout.
4. Confirm committee email delivery. Existing default-email restrictions may prevent other committee members signing in until custom SMTP is configured. Public volunteer requests do not use authentication email.
5. Sign in as coordinator and open the existing fixture/shift manager to check current fixtures and generate the schedule. Verify afternoon shifts against actual home fixtures; no live FA feed is wired into this migration.
6. Test public request, private review, combined capacity, cancellation and restricted finance access against the connected project. Verify unauthorised users cannot read names, phone numbers, rates or financial records. No public request automatically sends a notification: coordinators contact volunteers directly before approval.
7. Test a draft league match with known fees, approve it, then record payment. Cup fees must remain zero. No real fees or match sheets are pre-seeded. Budget commitments include approved unpaid costs; recording payment does not deduct twice.
8. Only after these checks, replace main demo links with shared routes and request production publishing approval.

The database tests use an isolated Postgres-compatible test database, not the live project. Run npm test. Tests cover anonymous table denial, coordinator/finance role separation, idempotent requests, capacity across old/new booking paths, age/contact checks, cancellation, fee snapshots, cup fees, approval locks, stale-edit rejection and audit records.
