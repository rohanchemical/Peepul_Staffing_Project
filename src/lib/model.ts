export const ROLES = ['Project Associate','Senior Project Associate','Project Manager','Senior Project Manager','Programme Manager','Senior Programme Manager'];
export const MONTHS = ['Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec','Jan','Feb','Mar'];
export const CATEGORIES = ['People & employer costs','Teacher training','Travel & field delivery','Technology & equipment','Assessment & MEL','Innovation activities','Shared / central allocation'];
export const sum = (a: number[]) => a.reduce((s,v) => s + Number(v || 0),0);
export const money = (v: number | null | undefined) => v == null ? 'Data required' : new Intl.NumberFormat('en-IN',{style:'currency',currency:'INR',maximumFractionDigits:0}).format(v);
export const lakh = (v: number | null | undefined) => v == null ? '—' : `₹${(v / 100000).toLocaleString('en-IN',{maximumFractionDigits:2})}L`;
export const fiscalDate = (year: number, month: number) => `${year + (month >= 9 ? 1 : 0)}-${String((month + 3) % 12 + 1).padStart(2,'0')}-01`;
export const dateLabel = (d: string) => new Date(d+'T00:00:00').toLocaleDateString('en-IN',{day:'numeric',month:'short',year:'numeric'});
export type Row = Record<string, any>;
export type Policy = {project_per_programme:number;associates_per_project:number;junior_per_senior:number[];surge:number[];is_ratified:boolean};
export const defaultPolicy: Policy = {project_per_programme:3,associates_per_project:3,junior_per_senior:[1,3,2],surge:[4,2,0],is_ratified:false};
export function staffing(programme: Row, rows: Row[], people: Row[], policy: Policy, asof: string, options: {requests?:number[];promotions?:boolean;choices?:number[];exits?:number[]} = {}) {
 const input=Array.from({length:6},(_,i)=>rows.find(r=>r.programme_id===programme.id&&r.role_index===i));
 const donor=input.map(r=>Number(r?.donor_posts||0)),org=input.map(r=>Number(r?.org_plan||0));
 const roster=people.filter(p=>p.programme_id===programme.id&&p.active&&(!p.start_date||p.start_date<=asof)&&(!p.end_date||p.end_date>=asof));
 const current=input.map((r,i)=>Math.max(0,(programme.roster_mode?roster.filter(p=>p.role_index===i).length:Number(r?.current_staff||0))-(options.exits?.[i]||0)));
 const requests=options.requests||input.map(r=>Number(r?.hiring_requests||0));
 const promotions=Array.from({length:5},(_,step)=>{const layer=Math.floor(step/2),within=step%2===0;const target=within?Math.round((donor[layer*2]+donor[layer*2+1])/(1+policy.junior_per_senior[layer])):donor[(layer+1)*2]+donor[(layer+1)*2+1];const already=within?current[step+1]:current[step+1]+current[step+2];const ceiling=Math.min(current[step],Math.max(0,target-already));return {step,within,target,already,seats:target-already,ceiling,chosen:options.promotions===false?0:Math.min(ceiling,Math.max(0,options.choices?.[step]??ceiling))};});
 const after=current.map((v,i)=>v+(i?promotions[i-1].chosen:0)-(i<5?promotions[i].chosen:0));
 const hires=Array(6).fill(0),ceo=Array(6).fill(0);
 const layers=Array.from({length:3},(_,j)=>{const i=j*2,d=donor[i]+donor[i+1],c=current[i]+current[i+1],a=after[i]+after[i+1],cap=d+policy.surge[j],room=Math.max(0,cap-a),ideal=Math.round(d/(1+policy.junior_per_senior[j])),seniorSeats=Math.max(0,ideal-after[i+1]);hires[i+1]=Math.min(requests[i+1],room,seniorSeats);hires[i]=Math.min(requests[i],Math.max(0,room-hires[i+1]));ceo[i+1]=Math.min(hires[i+1],Math.max(0,a+hires[i+1]-d));ceo[i]=Math.min(hires[i],Math.max(0,a+hires[i+1]+hires[i]-Math.max(d,a+hires[i+1])));return {index:j,donor:d,current:c,after:a,cap,room,above:Math.max(0,c-cap),open:Math.max(0,d-c),ideal,seniorSeats,fundedAfter:Math.max(0,d-a-hires[i]-hires[i+1])};});
 return {programme,input,missing:input.filter(r=>!r).length,donor,org,current,fte:sum(roster.map(p=>Number(p.allocation)/100)),requests,promotions,after,hires,ceo,layers,final:after.map((v,i)=>v+hires[i]),total:sum(current),funded:sum(donor),above:sum(layers.map(l=>l.above)),promotionCount:sum(promotions.map(p=>p.chosen)),hireCount:sum(hires),holdCount:sum(requests)-sum(hires),ceoCount:sum(ceo)};
}
export type StaffModel = ReturnType<typeof staffing>;
export function finance(lines: Row[], entries: Row[], cutoff: number) {
 const result=lines.map(l=>{const get=(kind:string,m:number)=>{const r=entries.find(e=>e.budget_line_id===l.id&&e.kind===kind&&e.month_index===m);return r?Number(r.amount):null;};
  const actual=Array.from({length:12},(_,m)=>get('actual',m)),committed=Array.from({length:12},(_,m)=>get('commitment',m)),forecast=Array.from({length:12},(_,m)=>get('forecast',m));
  const plan=(l.monthly_plan||Array(12).fill(0)).map(Number),a=sum(actual.slice(0,cutoff+1).map(v=>v??0));
  const missingActual=actual.slice(0,cutoff+1).filter(v=>v===null).length;
  const missingForecast=forecast.slice(cutoff+1).filter(v=>v===null).length;
  const etc=missingForecast?null:sum(forecast.slice(cutoff+1).map((f,j)=>Math.max(f??0,committed[cutoff+1+j]??0)));
  const c=sum(committed.slice(cutoff+1).map(v=>v??0)),eac=etc===null||missingActual?null:a+etc;
  return {line:l,plan,actual,committed,forecast,ytdActual:a,ytdBudget:sum(plan.slice(0,cutoff+1)),missingActual,missingForecast,etc,remainingCommitments:c,eac,headroom:eac===null?null:Number(l.annual_budget)-eac,available:Number(l.annual_budget)-a-c};
 });
 const complete=result.length>0&&result.every(r=>r.eac!==null);
 return {rows:result,annual:sum(lines.map(l=>Number(l.annual_budget))),original:sum(lines.map(l=>Number(l.original_annual))),actual:sum(result.map(r=>r.ytdActual)),commitments:sum(result.map(r=>r.remainingCommitments)),ytdBudget:sum(result.map(r=>r.ytdBudget)),eac:complete?sum(result.map(r=>r.eac!)):null,missingActual:sum(result.map(r=>r.missingActual)),missingForecast:sum(result.map(r=>r.missingForecast)),available:sum(result.map(r=>r.available))};
}
export function scenario(model: StaffModel, costs: Row[], f: ReturnType<typeof finance>, options: Row, cutoff: number, confirmed: number, policy: Policy) {
 const rates=Array.from({length:6},(_,i)=>{const r=costs.find(c=>c.programme_id===model.programme.id&&c.role_index===i);return r?Number(r.monthly_base)*(1+Number(r.employer_percent)/100):null;});
 const needed=new Set<number>();model.hires.forEach((v,i)=>{if(v)needed.add(i);});model.promotions.forEach(p=>{if(p.chosen){needed.add(p.step);needed.add(p.step+1);}});(options.exits||[]).forEach((v:number,i:number)=>{if(v)needed.add(i);});
 const missing=[...needed].some(i=>rates[i]===null),months=Math.max(0,11-cutoff),hireMonths=Math.max(0,12-Math.max(cutoff+1,Number(options.hireMonth)));
 const hiring=missing?null:sum(model.hires.map((v,i)=>v*(rates[i]??0)))*hireMonths;
 const promotions=missing?null:sum(model.promotions.map(p=>p.chosen*((rates[p.step+1]??0)-(rates[p.step]??0))))*months;
 const exitSaving=missing?null:sum((options.exits||[]).map((v:number,i:number)=>v*(rates[i]??0)))*months;
 const people=f.rows.filter(r=>r.line.category==='People & employer costs'),travel=f.rows.filter(r=>r.line.category==='Travel & field delivery'),tech=f.rows.filter(r=>r.line.category==='Technology & equipment');
 const remaining=(rs:typeof f.rows)=>sum(rs.map(r=>r.etc??0));
 const increment=remaining(people)*Number(options.increment||0)/100,travelChange=remaining(travel)*Number(options.travel||0)/100,techSaving=remaining(tech)*Number(options.techSaving||0)/100;
 // Savings are bounded by the entered remaining personnel forecast.
 const cappedExit=exitSaving===null?null:Math.min(exitSaving,remaining(people)+increment+(hiring??0)+(promotions??0));
 const eac=missing||f.eac===null?null:Math.max(f.actual,f.eac+(hiring??0)+(promotions??0)+increment+travelChange-techSaving-(cappedExit??0));
 const budget=f.annual+Number(options.budgetIncrease||0),funding=confirmed*(1-Number(options.fundingCut||0)/100)+Number(options.additionalFunding||0);
 const layers=[model.final[4]+model.final[5],model.final[2]+model.final[3],model.final[0]+model.final[1]],targets=[layers[0],layers[0]*policy.project_per_programme,layers[0]*policy.project_per_programme*policy.associates_per_project];
 return {model,rates,missing,eac,hiring,promotions,exitSaving:cappedExit,increment,travelChange,techSaving,budget,funding,headroom:eac===null?null:budget-eac,gap:eac===null?null:Math.max(0,eac-funding),ratioOK:layers.every((v,i)=>v===targets[i]),personMonths:(model.hires[0]+model.hires[1])*hireMonths};
}
export function evenly(annual:number){const first=Math.round(annual/12*100)/100;return Array.from({length:12},(_,i)=>i===11?Math.round((annual-first*11)*100)/100:first);}
