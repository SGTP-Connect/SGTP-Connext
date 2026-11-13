import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
test('database authorisation, booking capacity and privacy',async()=>{
 const db=new PGlite();try{
 await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key);create function auth.uid() returns uuid language sql as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;create function auth.jwt() returns jsonb language sql as $$select '{"email":"test@example.test"}'::jsonb$$;grant usage on schema public,auth to authenticated,anon;`);
 await db.exec(await readFile(new URL('../database/001_rota.sql',import.meta.url),'utf8'));
 const admin='00000000-0000-0000-0000-000000000001',alice='00000000-0000-0000-0000-000000000002',bob='00000000-0000-0000-0000-000000000003';
 await db.query('insert into auth.users values($1),($2),($3)',[admin,alice,bob]);
 async function as(id,fn){await db.exec('set role authenticated');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);try{return await fn()}finally{await db.exec('reset role')}}
 async function action(op,args){await db.query('select public.rota_action($1,$2::jsonb)',[op,JSON.stringify(args)])}
 async function snap(){return (await db.query('select public.rota_snapshot() as data')).rows[0].data}
 for(const [id,name] of [[admin,'Coordinator'],[alice,'Alice'],[bob,'Bob']])await as(id,()=>db.query('select public.rota_enrol($1)',[name]));
 await db.query('update public.rota_members set coordinator=true where user_id=$1',[admin]);
 const shift={role:'Kitchen',day:'2099-01-03',start:'08:30',end:'11:30',capacity:1};
 await as(alice,async()=>{await assert.rejects(action('create',shift),/Coordinator/);await assert.rejects(db.exec('update public.rota_members set coordinator=true'),/permission denied/);await assert.rejects(db.exec('select * from public.rota_members'),/permission denied/)});
 await as(admin,()=>action('create',shift));const sid=(await as(admin,snap)).shifts.find(s=>s.role==='Kitchen').id;
 await as(alice,()=>action('request',{expenses:'claim',age_confirmed:true,shift_id:sid}));await as(alice,()=>action('request',{expenses:'claim',age_confirmed:true,shift_id:sid}));await as(bob,()=>action('request',{expenses:'claim',age_confirmed:true,shift_id:sid}));
 const a=await as(alice,snap);assert.equal(a.requests.length,1);assert.equal(a.requests[0].name,'Alice');assert.equal(a.shifts.find(s=>s.id===sid).filled,0);
 await as(alice,()=>assert.rejects(action('approve',{age_verified:true,shift_id:sid,user_id:alice}),/Coordinator/));
 await as(admin,()=>action('approve',{age_verified:true,shift_id:sid,user_id:alice}));
 await as(admin,()=>assert.rejects(action('approve',{age_verified:true,shift_id:sid,user_id:bob}),/full/));
 assert.equal((await as(admin,snap)).shifts.find(s=>s.id===sid).filled,1);
 await as(bob,()=>action('withdraw',{shift_id:sid,user_id:alice}));assert.equal((await as(alice,snap)).requests[0].status,'confirmed');
 await as(alice,()=>action('withdraw',{shift_id:sid}));
 await as(bob,()=>action('request',{expenses:'claim',age_confirmed:true,shift_id:sid}));await as(admin,()=>action('approve',{age_verified:true,shift_id:sid,user_id:bob}));
 await as(admin,()=>action('close',{shift_id:sid}));assert.equal((await as(bob,snap)).requests[0].status,'cancelled');await as(alice,()=>assert.rejects(action('request',{expenses:'claim',age_confirmed:true,shift_id:sid}),/cancelled/));
 await db.exec('set role anon');await assert.rejects(db.exec('select public.rota_snapshot()'),/permission denied/);await db.exec('reset role');
 await as(admin,()=>assert.rejects(action('create',{...shift,capacity:0}),/Check/));
 // Fixture-driven shifts: exact templates, either team, de-duplication and cancellation.
 const initial=await as(admin,snap);const saturday=initial.shifts.find(s=>s.kind==='saturday-kitchen-am').day;
 const fixture={team:'Men’s First Team',opponent:'Test visitors',day:saturday,side:'Home',status:'Scheduled'};
 await as(alice,()=>assert.rejects(action('fixture',fixture),/Coordinator/));
 await as(admin,()=>action('fixture',fixture));
 let state=await as(admin,snap);let pm=state.shifts.filter(s=>s.day===saturday&&s.conditional&&!s.cancelled);assert.equal(pm.length,2);assert.equal(pm.find(s=>s.kind==='saturday-bar-pm').capacity,1);assert.equal(pm[0].start,'14:00');assert.equal(pm[0].end,'18:00');
 const fid=state.fixtures[0].id;const bar=pm.find(s=>s.kind==='saturday-bar-pm');
 await as(alice,()=>assert.rejects(action('request',{shift_id:bar.id,expenses:'claim',age_confirmed:false}),/18/));
 await as(alice,()=>assert.rejects(action('request',{shift_id:bar.id,age_confirmed:true}),/expenses/));
 await as(alice,()=>action('request',{expenses:'claim',age_confirmed:true,shift_id:bar.id}));await as(admin,()=>assert.rejects(action('approve',{shift_id:bar.id,user_id:alice}),/18/));assert.equal((await as(alice,snap)).requests.find(r=>r.shift_id===bar.id).expenses,'claim');await as(admin,()=>action('approve',{age_verified:true,shift_id:bar.id,user_id:alice}));
 await as(admin,()=>action('fixture',{...fixture,team:'Men’s Development Team'}));
 await as(admin,()=>action('fixture',{...fixture,fixture_id:fid,status:'Postponed'}));
 state=await as(admin,snap);assert.equal(state.shifts.filter(s=>s.day===saturday&&s.conditional&&!s.cancelled).length,2);
 const dev=state.fixtures.find(f=>f.team==='Men’s Development Team');
 await as(admin,()=>action('fixture',{...dev,fixture_id:dev.id,status:'Cancelled'}));
 state=await as(admin,snap);assert.equal(state.shifts.filter(s=>s.day===saturday&&s.conditional&&!s.cancelled).length,0);assert.equal(state.requests.find(r=>r.shift_id===bar.id).status,'cancelled');assert.equal(state.shifts.find(s=>s.day===saturday&&s.kind==='saturday-kitchen-am').cancelled,false);
 await as(alice,()=>assert.rejects(action('request',{expenses:'claim',age_confirmed:true,shift_id:bar.id}),/cancelled/));
 await as(admin,()=>action('fixture',{...fixture,fixture_id:fid,side:'Away'}));assert.equal((await as(admin,snap)).shifts.filter(s=>s.day===saturday&&s.conditional&&!s.cancelled).length,0);
 }finally{await db.close();}
});
