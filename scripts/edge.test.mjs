import assert from 'node:assert/strict';
import fs from 'node:fs';import vm from 'node:vm';import {stripTypeScriptTypes} from 'node:module';
const source=fs.readFileSync('supabase/functions/people-account/index.ts','utf8').replace(/^import .*;\n/,'');
let handler,role='superadmin',pending=false,created=0,updated;
const query=()=>{let table,filter;const q={select(){return q},eq(k,v){filter=v;return q},maybeSingle:async()=>({data:{id:'programme'}}),single:async()=>({data:table==='memberships'?{role,active:true,needs_password_change:pending}: {id:'record',user_id:'new-user'}}),update(v){updated=v;return q},upsert:async()=>({error:null}),then(resolve){return Promise.resolve({error:null}).then(resolve)}};return {q,setTable:v=>table=v};};
const admin={auth:{getUser:async token=>({data:{user:token==='valid'?{id:'admin-user'}:null}}),admin:{createUser:async()=>{created++;return {data:{user:{id:'new-user'}}}},updateUserById:async()=>({error:null})}},from:table=>{const {q,setTable}=query();setTable(table);return q}};
const context={Deno:{env:{get:()=>''},serve:h=>handler=h},createClient:()=>admin,Request,Response,crypto,Set,Uint8Array,console};
vm.runInNewContext(stripTypeScriptTypes(source),context);
async function request(body,token='valid'){const headers={'Content-Type':'application/json'};if(token)headers.authorization='Bearer '+token;const r=await handler(new Request('https://test.invalid',{method:'POST',headers,body:JSON.stringify(body)}));return {status:r.status,body:await r.json()};}
assert.equal((await request({action:'create-user'},null)).status,401);
assert.equal((await request({action:'create-user'},'invalid')).status,401);
for(role of ['data_admin','leadership','programme_manager'])assert.equal((await request({action:'create-user'})).status,403);
role='superadmin';pending=true;assert.equal((await request({action:'create-user'})).status,403);pending=false;
assert.equal((await request({action:'create-user',email:'user@example.org',display_name:'User',role:'programme_manager'})).status,400);
const r=await request({action:'create-user',email:'user@example.org',display_name:'User',role:'programme_manager',programme_id:'programme'});assert.equal(r.status,200);assert.ok(r.body.temporary_password.length>=30);assert.equal(created,1);assert.equal(updated.needs_password_change,true);assert.equal(updated.programme_id,'programme');assert.equal(updated.role,'programme_manager');
assert.equal((await request({action:'update-member',user_id:'admin-user',role:'superadmin',active:false})).status,400);
console.log('PASS: endpoint authentication, all non-admin role denials, temporary-password gate, required programme, account creation payload and self-access protection.');
