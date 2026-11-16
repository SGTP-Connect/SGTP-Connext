import {test} from 'node:test';import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';import {PGlite} from '@electric-sql/pglite';
test('guest requests are private, verified approvals share capacity; finance stays private and cup-free',async()=>{
 const db=new PGlite();try{
 await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key);create function auth.uid() returns uuid language sql as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;create function auth.jwt() returns jsonb language sql as $$select '{"email":"test@example.test"}'::jsonb$$;grant usage on schema public,auth to authenticated,anon;`);
 for(const file of ['001_rota.sql','002_guest_rota.sql','003_finance.sql','002_guest_rota.sql','003_finance.sql'])await db.exec(await readFile(new URL('../database/'+file,import.meta.url),'utf8'));
 const admin='00000000-0000-0000-0000-000000000001',member='00000000-0000-0000-0000-000000000002';await db.query('insert into auth.users values($1),($2)',[admin,member]);await db.query("insert into public.rota_members values($1,'Coordinator',true,false),($2,'Member',false,false)",[admin,member]);
 async function as(role,id,fn){await db.exec('set role '+role);await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id||'']);try{return await fn()}finally{await db.exec('reset role')}}
 const adm=fn=>as('authenticated',admin,fn),anon=fn=>as('anon',null,fn),mem=fn=>as('authenticated',member,fn);
 const action=(op,args)=>db.query('select public.rota_action($1,$2::jsonb)',[op,JSON.stringify(args)]);
 await adm(()=>action('create',{role:'Bar',day:'2099-01-03',start:'14:00',end:'18:00',capacity:1}));const sid=(await db.query("select id from rota_shifts where role='Bar'")).rows[0].id;
 const req=(phone,key,age=true)=>db.query('select public.rota_guest_request($1,$2,$3,$4,$5,$6)',[sid,'Example Volunteer',phone,'later',age,key]);
 const key='00000000-0000-0000-0000-000000000010';await anon(()=>assert.rejects(req('07700900000',key,false),/18/));await anon(()=>req('07700900000',key));await anon(()=>req('+44 7700 900000',key));assert.equal((await db.query('select count(*)::int n from rota_guest_requests')).rows[0].n,1);
 await anon(()=>assert.rejects(db.query('select * from rota_guest_requests'),/permission denied/));await mem(()=>assert.rejects(db.query('select rota_guest_admin()'),/Coordinator/));
 const id=(await db.query('select id from rota_guest_requests')).rows[0].id;
 const review=(contact,age)=>db.query("select rota_guest_review($1,'confirmed',$2,$3)",[id,contact,age]);await adm(()=>assert.rejects(review(false,true),/Contact/));await adm(()=>assert.rejects(review(true,false),/18/));await adm(()=>review(true,true));
 await mem(()=>assert.rejects(action('request',{shift_id:sid,expenses:'claim',age_confirmed:true}),/filled/));
 const snap=(await adm(()=>db.query('select rota_snapshot() d'))).rows[0].d;assert.equal(snap.shifts.find(s=>s.id===sid).filled,1);
 await adm(()=>action('close',{shift_id:sid}));assert.equal((await db.query('select status from rota_guest_requests')).rows[0].status,'cancelled');
 const pub=(await anon(()=>db.query('select rota_public_shifts() d'))).rows[0].d;assert.ok(!JSON.stringify(pub).includes('mobile'));assert.ok(!JSON.stringify(pub).includes('Example Volunteer'));
 // A rota coordinator is not automatically a finance member.
 await adm(()=>assert.rejects(db.query('select finance_snapshot()'),/Finance/));await anon(()=>assert.rejects(db.query('select finance_snapshot()'),/permission denied/));await mem(()=>assert.rejects(db.query('select * from finance_players'),/permission denied/));
 await db.query('insert into finance_members values($1)',[admin]);const fin=(op,args)=>db.query('select finance_action($1,$2::jsonb)',[op,JSON.stringify(args)]);
 await adm(()=>fin('player',{name:'Player A',fee_pence:8000}));await adm(()=>fin('player',{name:'Player B',fee_pence:4000}));const players=(await db.query('select * from finance_players order by name')).rows;
 const mid='00000000-0000-0000-0000-000000000020';const draft={id:mid,day:'2026-01-01',opponent:'Example FC',type:'league',league_number:1,lines:[{player_id:players[0].id,appearance:'starter',deduction_pence:1000,reason:'Agreed deduction'},{player_id:players[1].id,appearance:'used',deduction_pence:0}]};
 await adm(()=>fin('save_match',draft));let m=(await db.query('select * from finance_matches where id=$1',[mid])).rows[0];assert.equal(Number(m.cost_pence),9000);assert.equal(m.status,'draft');
 await adm(()=>assert.rejects(fin('approve',{id:mid}),/changed/));await adm(()=>fin('approve',{id:mid,expected_updated_at:m.updated_at}));m=(await db.query('select * from finance_matches where id=$1',[mid])).rows[0];
 await adm(()=>assert.rejects(fin('save_match',{...draft,expected_updated_at:m.updated_at}),/locked/));await adm(()=>assert.rejects(fin('paid',{id:mid,expected_updated_at:m.updated_at,paid_pence:10000}),/between/));await adm(()=>fin('paid',{id:mid,expected_updated_at:m.updated_at,paid_pence:4500}));m=(await db.query('select * from finance_matches where id=$1',[mid])).rows[0];await adm(()=>assert.rejects(fin('reopen',{id:mid,expected_updated_at:m.updated_at}),/Reconcile/));
 const cup={...draft,id:'00000000-0000-0000-0000-000000000021',type:'cup',lines:draft.lines.map(l=>({...l,deduction_pence:0}))};await adm(()=>fin('save_match',cup));const cm=(await db.query('select * from finance_matches where id=$1',[cup.id])).rows[0];assert.equal(Number(cm.cost_pence),0);assert.equal(cm.lines.length,2);assert.equal(cm.league_number,null);
 await adm(()=>assert.rejects(fin('save_match',{...draft,id:'00000000-0000-0000-0000-000000000022'}),/unique/));
 await adm(()=>fin('player',{id:players[0].id,name:'Player A',fee_pence:10000}));assert.equal((await db.query('select lines from finance_matches where id=$1',[mid])).rows[0].lines[0].fee_pence,8000);
 await adm(()=>assert.rejects(fin('save_match',{...draft,id:'00000000-0000-0000-0000-000000000023',league_number:2,lines:[draft.lines[0],draft.lines[0]]}),/duplicates/));
 assert.ok((await db.query('select count(*)::int n from finance_audit')).rows[0].n>=6);
 }finally{await db.close()}
});
