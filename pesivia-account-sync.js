/* PESIVIA account cart/favorites sync. Authenticated users only; local guest state stays local. */
(()=>{'use strict';
const CART='pesivia-market-cart-v1',FAV='pesivia-market-favorites';
const parse=(key)=>{try{const x=JSON.parse(localStorage.getItem(key)||'[]');return Array.isArray(x)?x:[]}catch(e){return []}};
const write=(key,data)=>{try{localStorage.setItem(key,JSON.stringify(data))}catch(e){}};
let api=null,user=null,ready=false,busy=false,pending=false;
function mergeCart(remote,local){const m=new Map();for(const item of [...remote,...local]){if(!item||typeof item!=='object'||typeof item.id!=='string'&&typeof item.id!=='number')continue;const id=String(item.id);const qty=Math.max(1,Math.min(99,Number(item.qty)||1));if(m.has(id)){const prev=m.get(id);m.set(id,{...prev,...item,qty:Math.max(prev.qty,qty)})}else m.set(id,{...item,id,qty})}return [...m.values()].slice(0,150)}
function mergeFav(a,b){return [...new Set([...a,...b].filter(x=>typeof x==='string'))].slice(0,500)}
async function save(){if(!ready||busy){pending=true;return}busy=true;try{const {error}=await api.from('mall_customer_state').upsert({user_id:user.id,cart:parse(CART),favorites:parse(FAV),updated_at:new Date().toISOString()},{onConflict:'user_id'});if(error)console.warn('PESIVIA sync:',error.message)}catch(e){console.warn('PESIVIA sync unavailable')}finally{busy=false;if(pending){pending=false;save()}}}
async function start(){if(!window.supabase||!window.MALL_SUPABASE_URL||!window.MALL_SUPABASE_PUBLISHABLE_KEY)return;api=window.supabase.createClient(window.MALL_SUPABASE_URL,window.MALL_SUPABASE_PUBLISHABLE_KEY);const {data,error}=await api.auth.getUser();if(error||!data?.user)return;user=data.user;const {data:remote,error:readError}=await api.from('mall_customer_state').select('cart,favorites').eq('user_id',user.id).maybeSingle();if(readError){console.warn('PESIVIA sync:',readError.message);return}const cart=mergeCart(Array.isArray(remote?.cart)?remote.cart:[],parse(CART));const favorites=mergeFav(Array.isArray(remote?.favorites)?remote.favorites:[],parse(FAV));write(CART,cart);write(FAV,favorites);ready=true;document.dispatchEvent(new CustomEvent('pesivia-account-state-loaded'));await save()}
document.addEventListener('click',e=>{if(!ready)return;const el=e.target.closest('button');if(!el)return;setTimeout(()=>save(),250)},true);
window.addEventListener('storage',e=>{if(ready&&(e.key===CART||e.key===FAV))save()});
start().catch(e=>console.warn('PESIVIA sync unavailable'));
})();