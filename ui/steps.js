// Progressive enhancement: original field names and submit handlers are retained.
export function enhanceForms(root=document){
 for(const form of root.querySelectorAll('form')){
  if(form.dataset.stepped)continue;
  const fields=[...form.querySelectorAll('input:not([type="hidden"]),select,textarea')];
  if(fields.length<2)continue;
  const submit=form.querySelector('button:not([type]),button[type="submit"],input[type="submit"]');
  if(!submit)continue;
  form.dataset.stepped='true';form.noValidate=true;
  const labels=fields.map((f,i)=>{
   let label=f.labels?.[0]||f.closest('.field')?.querySelector('label');
   if(!label&&f.previousElementSibling?.tagName==='LABEL')label=f.previousElementSibling;
   const text=label?.textContent?.trim()||f.name||'Your answer';
   f.id=f.id||form.id+'-answer-'+i;
   return {field:f,text};
  });
  const shell=document.createElement('div');shell.className='steps';
  const progress=document.createElement('p');progress.className='step-progress';progress.setAttribute('aria-live','polite');
  const heading=document.createElement('h3');heading.className='step-heading';heading.tabIndex=-1;
  const panel=document.createElement('div');panel.className='step-panel';
  const sections=labels.map(({field,text})=>{const section=document.createElement('div');const label=document.createElement('label');label.htmlFor=field.id;label.textContent=text;label.className='step-label';section.append(label,field);panel.append(section);return section});
  const summary=document.createElement('dl');summary.className='step-summary';panel.append(summary);
  const actions=document.createElement('div');actions.className='step-actions';
  const back=document.createElement('button');back.type='button';back.className='alt';back.textContent='Back';
  const next=document.createElement('button');next.type='button';next.textContent='Continue';
  submit.type='submit';actions.append(back,next,submit);shell.append(progress,heading,panel,actions);form.replaceChildren(shell);
  let step=0;
  function show(n,focus=false){step=n;sections.forEach((s,i)=>s.hidden=i!==step);summary.hidden=step<fields.length;back.hidden=step===0;next.hidden=step===fields.length;submit.hidden=step!==fields.length;progress.textContent=step<fields.length?`Question ${step+1} of ${fields.length}`:'Final check';heading.textContent=step<fields.length?labels[step].text:'Check your answers';
   if(step===fields.length){summary.replaceChildren();labels.forEach(({field,text},i)=>{const row=document.createElement('div');const term=document.createElement('dt');term.textContent=text;const answer=document.createElement('dd');answer.textContent=field.tagName==='SELECT'?field.selectedOptions[0]?.textContent:field.value||'Not provided';const edit=document.createElement('button');edit.type='button';edit.className='step-edit';edit.textContent='Change';edit.setAttribute('aria-label','Change '+text);edit.onclick=()=>show(i,true);row.append(term,answer,edit);summary.append(row)})}
   if(focus){heading.focus({preventScroll:true});form.scrollIntoView({block:'start',behavior:'smooth'})}
  }
  back.onclick=()=>show(Math.max(0,step-1),true);
  next.onclick=()=>{if(fields[step].reportValidity())show(step+1,true)};
  form.addEventListener('submit',e=>{if(step<fields.length){e.preventDefault();e.stopImmediatePropagation();next.click();return}const invalid=fields.findIndex(f=>!f.checkValidity());if(invalid!==-1){e.preventDefault();e.stopImmediatePropagation();show(invalid,true);fields[invalid].reportValidity()}},true);
  form.stepper={get step(){return step},show};show(0);
  // The club overview opens a task before revealing its questions.
  if(!location.pathname.includes('/rota/')){
   const card=form.closest('.card');const app=document.getElementById('app');
   if(card&&app){const launch=document.createElement('button');launch.type='button';launch.textContent=({registrationForm:'Register a player',fixtureForm:'Add a fixture',trainingForm:'Add training',announcementForm:'Write an announcement',shiftForm:'Create a shift'})[form.id]||'Get started';form.hidden=true;form.before(launch);
    const exit=document.createElement('button');exit.type='button';exit.className='alt focus-back';exit.textContent='‹ Back';exit.hidden=true;form.before(exit);
    launch.onclick=()=>{launch.hidden=true;exit.hidden=false;form.hidden=false;[...app.children].forEach(n=>{if(n!==card){n.dataset.stepHidden=String(n.hidden);n.hidden=true}});show(0,true)};
    exit.onclick=()=>{form.hidden=true;exit.hidden=true;launch.hidden=false;[...app.children].forEach(n=>{if(n.dataset.stepHidden!==undefined){n.hidden=n.dataset.stepHidden==='true';delete n.dataset.stepHidden}});launch.focus()};
   }
  }
 }
}
export function watchForms(){enhanceForms();new MutationObserver(()=>enhanceForms()).observe(document.body,{childList:true,subtree:true})}
watchForms();
