import {test} from 'node:test';import assert from 'node:assert/strict';import {PGlite} from '@electric-sql/pglite';import {readFile} from 'node:fs/promises';
test('friendlies are shared safely, managers can only edit assigned teams, and stale edits are rejected',async()=>{
const db=new PGlite();try{
await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key);create function auth.uid() returns uuid language sql as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;create function auth.jwt() returns jsonb language sql as $$select '{}'::jsonb$$;grant usage on schema public,auth to anon,authenticated;`);
for(const f of ['001_rota.sql','004_friendlies.sql','004_friendlies.sql'])await db.exec(await readFile(new URL('../database/'+f,import.meta.url),'utf8'));
const uid='00000000-0000-0000-0000-000000000001',id='00000000-0000-0000-0000-000000000002';await db.query('insert into auth.users values($1)',[uid]);await db.query("insert into team_managers values($1,'U14 Blues')",[uid]);await db.query("select set_config('request.jwt.claim.sub',$1,false)",[uid]);await db.exec('set role authenticated');
const d={id,team:'U14 Blues',opponent:'Test FC',day:'2099-01-01',kickoff:'10:30',side:'Away',venue:'Test pitch',status:'Scheduled'};const save=v=>db.query('select friendly_save($1::jsonb)',[JSON.stringify(v)]);
await assert.rejects(save({...d,team:'U18'}),/assigned team/);await save(d);await save({...d,updated_at:(await db.query('select friendly_manager() d')).rows[0].d.fixtures[0].updated_at,status:'Postponed'});
await assert.rejects(save(d),/changed/);await assert.rejects(db.query('select * from team_managers'),/permission denied/);
await db.exec('reset role;set role anon');await assert.rejects(save(d),/permission denied/);const rows=(await db.query('select friendly_list() d')).rows[0].d;assert.equal(rows.length,1);assert.equal(rows[0].status,'Postponed');assert.equal(rows[0].kind,'Friendly');assert.ok(!('created_by' in rows[0]));await assert.rejects(db.query('select friendly_manager()'),/permission denied/);
await db.exec('reset role;');await db.query('delete from team_managers where user_id=$1',[uid]);await db.exec('set role authenticated');await assert.rejects(save({...d,team:'U14 Blues'}),/assigned team/);
}finally{await db.close()}});
