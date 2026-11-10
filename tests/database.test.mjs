import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
test('database authorisation, booking capacity and privacy',async()=>{
 const db=new PGlite();
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
 await as(admin,()=>action('create',shift));const sid=(await as(admin,snap)).shifts[0].id;
 await as(alice,()=>action('request',{shift_id:sid}));await as(alice,()=>action('request',{shift_id:sid}));await as(bob,()=>action('request',{shift_id:sid}));
 const a=await as(alice,snap);assert.equal(a.requests.length,1);assert.equal(a.requests[0].name,'Alice');assert.equal(a.shifts[0].filled,0);
 await as(alice,()=>assert.rejects(action('approve',{shift_id:sid,user_id:alice}),/Coordinator/));
 await as(admin,()=>action('approve',{shift_id:sid,user_id:alice}));
 await as(admin,()=>assert.rejects(action('approve',{shift_id:sid,user_id:bob}),/full/));
 assert.equal((await as(admin,snap)).shifts[0].filled,1);
 await as(bob,()=>action('withdraw',{shift_id:sid,user_id:alice}));assert.equal((await as(alice,snap)).requests[0].status,'confirmed');
 await as(alice,()=>action('withdraw',{shift_id:sid}));
 await as(bob,()=>action('request',{shift_id:sid}));await as(admin,()=>action('approve',{shift_id:sid,user_id:bob}));
 await as(admin,()=>action('close',{shift_id:sid}));assert.equal((await as(bob,snap)).requests[0].status,'cancelled');await as(alice,()=>assert.rejects(action('request',{shift_id:sid}),/cancelled/));
 await db.exec('set role anon');await assert.rejects(db.exec('select public.rota_snapshot()'),/permission denied/);await db.exec('reset role');
 await as(admin,()=>assert.rejects(action('create',{...shift,capacity:0}),/Check/));
 await db.close();
});
