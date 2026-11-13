let sheet;
const units=p=>(p.starts||0)+(p.benchUsed||0)===p.appearances?(p.starts||0)+(p.benchUsed||0)/2:null;
function render(){
 const term=document.querySelector('#search').value.toLowerCase().trim();
 const list=sheet.players.filter(p=>p.name.toLowerCase().includes(term));
 const body=document.querySelector('#rows');body.replaceChildren();
 for(const p of list){const row=document.createElement('tr');for(const value of [p.name,p.appearances,p.starts,p.benchUsed,p.benchUnused,units(p)]){const cell=document.createElement('td');cell.textContent=value===null?'—':value;row.append(cell)}body.append(row)}
 document.querySelector('#count').textContent=`${list.length} of ${sheet.players.length} published players`;
 document.querySelector('#empty').hidden=list.length>0;
}
document.querySelector('#search').addEventListener('input',()=>{if(sheet)render()});
document.querySelector('#download').addEventListener('click',()=>{
 const rows=[['Player','Appearances','Starts','Used substitute','Unused substitute','Provisional fee units','Checked date','Review status'],...sheet.players.map(p=>[p.name,p.appearances,p.starts,p.benchUsed,p.benchUnused,units(p),sheet.checked,'Awaiting reconciliation'])];
 const csv=rows.map(r=>r.map(v=>'"'+String(v??'').replaceAll('"','""')+'"').join(',')).join('\r\n');
 const url=URL.createObjectURL(new Blob(['\ufeff'+csv],{type:'text/csv;charset=utf-8'}));const a=document.createElement('a');a.href=url;a.download='SGTP-first-team-2026-27.csv';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
});
fetch('appearances.json',{cache:'no-store'}).then(r=>{if(!r.ok)throw Error();return r.json()}).then(data=>{sheet=data;render();document.querySelector('#status').textContent=`Published totals checked ${sheet.checked}. Latest result listed: ${sheet.latestResult}.`;document.querySelector('#download').disabled=false}).catch(()=>{document.querySelector('#status').textContent='The sheet could not load. Please refresh or use the FA Full-Time link below.'});
