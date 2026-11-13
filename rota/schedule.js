import {londonDay} from './model.js';
export const templates=[
 {kind:'saturday-kitchen-am',role:'Kitchen · Saturday morning',start:'09:00',end:'13:00',capacity:2,staffing:'ideal',conditional:false},
 {kind:'saturday-kitchen-pm',role:'Kitchen · Saturday afternoon',start:'14:00',end:'18:00',capacity:2,staffing:'minimum',conditional:true},
 {kind:'saturday-bar-pm',role:'Bar · Saturday afternoon',start:'14:00',end:'18:00',capacity:1,staffing:'minimum',conditional:true},
 {kind:'sunday-kitchen-am',role:'Kitchen · Sunday morning',start:'09:00',end:'13:00',capacity:2,staffing:'minimum',conditional:false}
];
export function weekends(){const d=new Date(londonDay()+'T12:00:00Z');d.setUTCDate(d.getUTCDate()+(d.getUTCDay()===0?-1:(6-d.getUTCDay()+7)%7));return Array.from({length:6},(_,i)=>{const n=new Date(d);n.setUTCDate(d.getUTCDate()+i*7);return n.toISOString().slice(0,10)})}
export function hasHomeGame(fixtures,day){return fixtures.some(f=>f.day===day&&f.side==='Home'&&f.status==='Scheduled'&&['Men’s First Team','Men’s Development Team'].includes(f.team))}
export function syncSchedule(data){for(const sat of weekends()){const d=new Date(sat+'T12:00:00Z');d.setUTCDate(d.getUTCDate()+1);for(const t of templates){const day=t.kind.startsWith('sunday')?d.toISOString().slice(0,10):sat;const active=!t.conditional||hasHomeGame(data.fixtures,day);let s=data.shifts.find(s=>s.day===day&&s.kind===t.kind);if(!s){s={...t,day,id:day+'-'+t.kind,fixture_active:active};data.shifts.push(s)}else{s.fixture_active=active}if(!active)data.requests.filter(r=>r.shift_id===s.id&&['confirmed','pending'].includes(r.status)).forEach(r=>r.status='cancelled')}}}
