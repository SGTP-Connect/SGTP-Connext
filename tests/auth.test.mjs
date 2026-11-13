import {test} from 'node:test';
import assert from 'node:assert/strict';
import {RotaAPI} from '../rota/api.js';
const access='header.'+Buffer.from(JSON.stringify({exp:Math.floor(Date.now()/1000)+3600})).toString('base64url')+'.signature';
const config={url:'https://example.supabase.co',publishableKey:'public-test'};
test('email callback clears URL before validation and accepts only verified users',async()=>{
 const api=new RotaAPI(config);let cleared=false;
 const loc={hash:'#access_token='+access+'&refresh_token=refresh&expires_in=3600',pathname:'/rota/',search:''};
 globalThis.fetch=async(url,opts)=>{assert.ok(cleared);assert.equal(url,config.url+'/auth/v1/user');assert.equal(opts.headers.Authorization,'Bearer '+access);return {ok:true,json:async()=>({id:'verified-user'})}};
 assert.equal(await api.restoreFromLink(loc,{replaceState(a,b,path){assert.equal(path,'/rota/');cleared=true}}),true);
 assert.equal(api.session.user.id,'verified-user');
});
test('expired, incomplete and rejected links never create sessions',async()=>{
 for(const hash of ['#error=access_denied','#access_token=test','#access_token=test&refresh_token=refresh&expires_in=3600']){
  const api=new RotaAPI(config);let cleared=false;globalThis.fetch=async()=>({ok:false,json:async()=>({})});
  await assert.rejects(api.restoreFromLink({hash,pathname:'/rota/',search:''},{replaceState(){cleared=true}}));assert.ok(cleared);assert.equal(api.session,null);
 }
});
test('email request targets current rota without queries or fragments',async()=>{
 globalThis.location={href:'https://preview.example/rota/?demo=0#ignored'};
 globalThis.fetch=async(url,opts)=>{assert.equal(new URL(url).searchParams.get('redirect_to'),'https://preview.example/rota/');assert.equal(JSON.parse(opts.body).email,'test@example.com');return {ok:true,json:async()=>({})}};
 await new RotaAPI(config).sendCode('test@example.com');
});

test('verified token expiry works without optional URL expiry or refresh fields',async()=>{
 for(const suffix of ['', '&expires_at=9999999999', '&refresh_token=refresh']){
  const api=new RotaAPI(config);globalThis.fetch=async()=>({ok:true,json:async()=>({id:'verified-user'})});
  await api.restoreFromLink({hash:'#access_token='+access+suffix,pathname:'/rota/',search:''},{replaceState(){}});
  assert.equal(api.session.access_token,access);assert.ok(api.session.expires>Date.now());
 }
});
test('malformed expiry is rejected even if user endpoint returns a user',async()=>{
 const api=new RotaAPI(config);globalThis.fetch=async()=>({ok:true,json:async()=>({id:'verified-user'})});
 await assert.rejects(api.restoreFromLink({hash:'#access_token=malformed&expires_in=3600',pathname:'/rota/',search:''},{replaceState(){}}));assert.equal(api.session,null);
});
