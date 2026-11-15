import {RotaAPI} from '../rota/api.js';
export const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export async function privateSession(root,onReady){
 const api=new RotaAPI(window.SGTP_ROTA_CONFIG);let busy=false;
 function login(note=''){root.innerHTML=`<section><h2>Committee sign-in</h2><p>Only authorised club coordinators or finance members can access private records.</p><p role="status">${esc(note)}</p><form id="privateLogin"><label for="email">Email address</label><input id="email" name="email" type="email" autocomplete="email" required><button>Send sign-in link</button></form><p>Open the latest link from your email. Closing or refreshing this page ends the session.</p></section>`;root.querySelector('form').onsubmit=async e=>{e.preventDefault();if(busy)return;busy=true;const b=root.querySelector('button');b.disabled=true;try{const redirect=new URL(location.href);redirect.hash='';await api.fetch('/auth/v1/otp?redirect_to='+encodeURIComponent(redirect.href),{email:new FormData(e.target).get('email').trim(),create_user:false});login('Email requested. Open the latest sign-in link.')}catch(err){login(err.message)}finally{busy=false}}}
 try{if(await api.restoreFromLink()){await onReady(api);return}}catch(e){login(e.message);return}login();
}
