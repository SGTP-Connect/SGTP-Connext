export class RotaAPI {
 constructor(config){this.url=config.url.replace(/\/$/,'');this.key=config.publishableKey;this.session=null}
 async fetch(path,body,token){let res;try{res=await fetch(this.url+path,{method:'POST',headers:{apikey:this.key,'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{})},body:JSON.stringify(body),signal:AbortSignal.timeout(15000)})}catch{throw Error('Could not reach the club rota. Check your connection and try again.')}const data=await res.json().catch(()=>null);if(!res.ok){if(res.status===401){this.session=null;throw Error('Your sign-in has expired. Please sign in again.')}throw Error(data?.msg||data?.message||data?.error_description||'That action could not be completed. Please try again.')}return data}
 async sendCode(email){await this.fetch('/auth/v1/otp',{email,create_user:true})}
 async verify(email,token){const s=await this.fetch('/auth/v1/verify',{email,token,type:'email'});if(!s?.access_token)throw Error('Sign-in could not be verified.');this.session={...s,expires:Date.now()+s.expires_in*1000}}
 async token(){if(!this.session)throw Error('Sign in first.');if(Date.now()>this.session.expires-60000){const s=await this.fetch('/auth/v1/token?grant_type=refresh_token',{refresh_token:this.session.refresh_token});this.session={...s,expires:Date.now()+s.expires_in*1000}}return this.session.access_token}
 async rpc(name,args={}){return this.fetch('/rest/v1/rpc/'+name,args,await this.token())}
 async load(){return this.rpc('rota_snapshot')}
 async enrol(name){return this.rpc('rota_enrol',{p_name:name})}
 async act(op,args){return this.rpc('rota_action',{p_op:op,p_args:args})}
 async logout(){try{if(this.session)await this.fetch('/auth/v1/logout',{},this.session.access_token)}finally{this.session=null}}
}
