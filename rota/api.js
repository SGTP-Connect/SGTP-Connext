export class RotaAPI {
 constructor(config){this.url=config.url.replace(/\/$/,'');this.key=config.publishableKey;this.session=null}
 async fetch(path,body,token){let res;try{res=await fetch(this.url+path,{method:'POST',headers:{apikey:this.key,'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{})},body:JSON.stringify(body),signal:AbortSignal.timeout(15000)})}catch{throw Error('Could not reach the club rota. Check your connection and try again.')}const data=await res.json().catch(()=>null);if(!res.ok){if(res.status===401){this.session=null;throw Error('Your sign-in has expired. Please sign in again.')}throw Error(data?.msg||data?.message||data?.error_description||'That action could not be completed. Please try again.')}return data}
 async sendCode(email){const redirect=new URL('./',location.href);redirect.search='';redirect.hash='';await this.fetch('/auth/v1/otp?redirect_to='+encodeURIComponent(redirect.href),{email,create_user:true})}
 async restoreFromLink(loc=location,hist=history){
  const params=new URLSearchParams(loc.hash.slice(1));
  if(!['access_token','refresh_token','error','error_description'].some(k=>params.has(k)))return false;
  hist.replaceState(null,'',loc.pathname+loc.search);
  this.session=null;
  if(params.has('error')||params.has('error_description'))throw Error('This sign-in link has expired or is invalid. Please request a new email.');
  const access=params.get('access_token'),refresh=params.get('refresh_token');
  if(!access)throw Error('The email link did not include a sign-in token. Please request a new email and open it in Safari.');
  let res;try{res=await fetch(this.url+'/auth/v1/user',{headers:{apikey:this.key,Authorization:'Bearer '+access},signal:AbortSignal.timeout(15000)})}catch{throw Error('Could not verify your sign-in. Check your connection and request a new email.')}
  const user=await res.json().catch(()=>null);
  if(!res.ok||!user?.id)throw Error('This sign-in link has expired or is invalid. Please request a new email.');
  // Read expiry only after Supabase has verified this token. URL expiry fields are optional.
  let expiry;try{const payload=access.split('.')[1].replace(/-/g,'+').replace(/_/g,'/');expiry=Number(JSON.parse(atob(payload)).exp)*1000}catch{}
  if(!Number.isFinite(expiry)||expiry<=Date.now())throw Error('This sign-in link has expired or is invalid. Please request a new email.');
  this.session={access_token:access,refresh_token:refresh,user,expires:expiry};return true;
 }
 async verify(email,token){const s=await this.fetch('/auth/v1/verify',{email,token,type:'email'});if(!s?.access_token)throw Error('Sign-in could not be verified.');this.session={...s,expires:Date.now()+s.expires_in*1000}}
 async token(){if(!this.session)throw Error('Sign in first.');if(Date.now()>this.session.expires-60000){if(!this.session.refresh_token){this.session=null;throw Error('Your sign-in has expired. Please sign in again.')}const s=await this.fetch('/auth/v1/token?grant_type=refresh_token',{refresh_token:this.session.refresh_token});this.session={...s,expires:Date.now()+s.expires_in*1000}}return this.session.access_token}
 async rpc(name,args={}){return this.fetch('/rest/v1/rpc/'+name,args,await this.token())}
 async load(){return this.rpc('rota_snapshot')}
 async enrol(name){return this.rpc('rota_enrol',{p_name:name})}
 async act(op,args){return this.rpc('rota_action',{p_op:op,p_args:args})}
 async logout(){try{if(this.session)await this.fetch('/auth/v1/logout',{},this.session.access_token)}finally{this.session=null}}
}
