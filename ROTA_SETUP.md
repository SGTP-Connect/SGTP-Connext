# Volunteer rota — review branch

The existing Netlify production deploy is unchanged. This branch adds `/rota/` and links it from the app's Volunteer Hub. `/rota/?demo=1` is a fictional, in-memory preview. It never calls the live API or imports the old prototype's browser data.

## Implemented

- Mobile-friendly shift list, capacity indicators and personal booking status.
- New volunteers request a shift; coordinators approve or decline.
- Trusted returning volunteers can confirm immediately; trust is assigned in the database, never by a typed name or a client-side role selector.
- Create shifts, withdraw places and cancel a whole shift.
- Email-code authentication adapter and shared database RPCs.
- Database authorisation, private volunteer names, unique requests, and per-shift row locking to prevent overbooking.

## Club shift rules

The coordinator view maintains a six-week rolling schedule (including the current Sunday on Sundays):

| Shift | Time | People | Rule |
| --- | --- | --- | --- |
| Saturday morning kitchen | 09:00–13:00 | Ideally 2 | Every weekend |
| Saturday afternoon kitchen | 14:00–18:00 | Minimum 2 | Either senior team scheduled at home that Saturday |
| Saturday afternoon bar | 14:00–18:00 | Minimum 1 | Either senior team scheduled at home that Saturday |
| Sunday morning kitchen | 09:00–13:00 | 2 | Every weekend |

Coordinators record verified matches under **Senior fixtures**. Saving a fixture recalculates afternoon cover automatically. Two home games on the same day still create only one kitchen and one bar shift. Postponing, cancelling, moving or switching the last home fixture to away makes the old afternoon shifts unavailable and cancels their bookings; the coordinator must notify affected people directly. If the game returns, cancelled bookings are not silently reconfirmed. Morning shifts remain regular.

There is **no live FA sync** and no connection to the older app's fictional browser-only fixtures. Missing senior fixture records mean "not recorded", not proof there is no game. The UI flags this explicitly. Connect a verified senior fixture source before relying on automatic imports. The demo starts with a clearly fictional home game to demonstrate the rule.

## Required before real use

No Supabase project has been created or connected. Sign-in and real shared bookings are intentionally disabled in `rota/config.js`. Do not advertise this as a live booking system yet.

1. Create a club-owned Supabase project (choose the region and review the service terms/pricing in the club's account).
2. Run the current `database/001_rota.sql` once in its SQL editor. This creates only rota tables and RPCs; it seeds no people or shifts.
3. Enable email authentication and configure production SMTP. Configure **both** the signup confirmation and magic-link email templates to include `{{ .Token }}` as the sign-in code. The app uses codes, not email links. Check delivery, expiry and rate limits before inviting volunteers.
4. Put the HTTPS project URL and **public publishable key** in `rota/config.js`. Never put service-role keys, passwords or SMTP credentials in this repository.
5. Sign in as the intended coordinator and enter their name. In the SQL editor, identify that exact account in `auth.users` and set `rota_members.coordinator=true` for its UUID. Do not use client-editable user metadata for permissions. Set `trusted=true` only for club-approved returning volunteers. Names alone must not determine trust.
6. Check on two separate devices: request, refresh, approve, refresh, withdraw; check that another volunteer cannot see names or approve requests. Exercise concurrent final-place approvals against the hosted database. Check expired and incorrect codes, refresh-token renewal, unavailable network and sign-out.
7. Review privacy text, club contact arrangements and the database retention process before collecting names. This feature stores only account identity, display name and booking state. It does not accept child registration, medical data or welfare reports.
8. Review the branch and approve publication. Keep Netlify auto-publishing locked; merge/deploy only under the agreed approval process. When manually publishing, select the reviewed commit and leave the lock in place.

## Limitations

- Live email delivery and multi-device integration have not been tested because the service is not configured.
- Sessions are in memory only: reload/close signs the user out locally. Sign-out attempts server revocation too; if offline, the local session is still cleared and the existing token expires normally.
- Refresh retrieves new shared state; no background realtime subscription.
- No booking notification emails. Volunteers check My shifts; coordinators must communicate same-day changes directly.
- No UI for assigning coordinator/trusted status in this first release; controlled database administration only.
- No shift editing: cancel the old shift and create a replacement, then contact affected volunteers.
- Existing prototype executive figures and weekend coverage still use fictional data, not the new shared rota.

## Verification

Run `npm install` then `npm test`. PGlite tests execute the migration and RPCs in an embedded PostgreSQL engine with a small auth shim. They cover table grants, anonymous access, role escalation, volunteer privacy, approval capacity, cancellation and withdrawal ownership. They do not substitute for hosted Auth, PostgREST or genuine concurrent connection tests.

Browser QA exercised the setup-disabled state, demo request, coordinator approval and volunteer confirmation. JavaScript syntax checks passed. Production remains untouched.

Fixture update verification: 12 tests pass, including regular timings, either senior team at home, away/postponed games, cancellation of booked afternoon shifts, and no duplicate cover when both teams play at home. Browser QA confirmed postponing the demo home game leaves only morning cover. The migration is still an initial schema for an unconfigured service, not an upgrade script for an already deployed database.

## Simple guided forms

The club home now shows three role-relevant actions. Registration, fixture, training and other multi-field forms use one question per screen, Back/Continue controls and a final editable summary. Rota coordinator tools sit under Manage rota; shift and fixture editors have focused screens. Demo explanations remain available in expandable sections.

Browser QA checked required-field validation, registration completion, retained answers when going Back, summary editing, shift creation and invalid finish-time recovery without losing answers. The fixture editor displayed one question at a time. All 12 rota/database tests and JavaScript syntax checks passed. This does not enable live accounts or FA fixture synchronisation.

Bar shifts now require an explicit 18+ declaration and coordinator age check before approval, including returning volunteers. Requests require an explicit expenses preference (claim if available, or volunteer without claiming); no payment, donation transaction or amount is promised. Preferences are visible to the volunteer and coordinators. These controls are in both the demo model and prepared database RPCs. Browser QA completed a bar request with the no-claim preference, showing it retained under My shifts and awaiting approval. All 14 tests pass, including missing age/expense rejection at the database layer. The SQL remains an initial migration for the unconfigured service.
