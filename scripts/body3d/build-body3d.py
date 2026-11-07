import re, json, gzip, struct, numpy as np, sys
from decode import man, part
P={p[0]:p for p in man['parts']}

REG=[ # (regex on name, region)
 (r'pectoralis major|pectoralis minor', 'chest'),
 (r'deltoid', 'delts'),
 (r'supraspinatus|infraspinatus|teres minor|subscapularis', 'delts'),
 (r'biceps brachii|brachialis|coracobrachialis', 'biceps'),
 (r'brachioradialis|carpi|digitorum superficialis|digitorum profundus|pollicis longus|palmaris|pronator|supinator|anconeus|extensor digit(i|orum)(?! .*(longus|brevis) of)|extensor indicis|abductor pollicis longus|extensor pollicis', 'forearms'),
 (r'triceps', 'triceps'),
 (r'rectus abdominis|pyramidalis', 'abs'),
 (r'external oblique|internal oblique', 'obliques'),
 (r'serratus anterior', 'serratus'),
 (r'rectus femoris|vastus', 'quads'),
 (r'adductor (longus|brevis|magnus|minimus)|gracilis|pectineus', 'adductors'),
 (r'gastrocnemius|soleus|plantaris', 'calves'),
 (r'tibialis anterior|peroneus|fibularis|extensor digitorum longus|extensor hallucis longus', 'tibialis'),
 (r'trapezius', 'traps'),
 (r'latissimus|teres major', 'lats'),
 (r'rhomboid', 'rhomboids'),
 (r'gluteus|tensor fasciae', 'glutes'),
 (r'biceps femoris|semitendinosus|semimembranosus', 'hamstrings'),
 (r'iliocostalis|longissimus (thoracis)|spinalis|multifidus|quadratus lumborum', 'lowback'),
 (r'sternocleidomastoid|splenius|scalen|levator scapulae|platysma', 'neck'),
 (r'sartorius|iliacus|psoas', 'hipflex'),
]
DROP=r'intercostal|diaphragm|levatores|puborect|pubococc|iliococc|coccyge|levator ani|sphincter|gloss|pharyn|laryn|arytenoid|thyro|crico|palat|uvula|stapedius|tympani|rotatores|interspinal|intertransvers|transversus thoracis|subcostal|ischiocavernosus|bulbospong|perine|cremaster|inferior oblique$|superior oblique$|superior rectus|inferior rectus|medial rectus|lateral rectus|levator palpebrae|tarsal|ciliary|semispinalis|obliquus capitis|rectus capitis|longus colli|longus capitis|multifidus|transversus abdominis|quadratus lumborum|serratus posterior|levator costae|popliteus|tibialis posterior|flexor hallucis longus|flexor digitorum longus|obturator|gemellus|piriformis|quadratus femoris|vastus intermedius|adductor brevis|pectoralis minor|subscapularis|digitorum profundus|pollicis longus$|flexor pollicis longus|pronator quadratus|supinator'

def region(name):
    n=name.lower()
    for rx,r in REG:
        if re.search(rx,n): return r
    return 'other'

def decimate(pos,nrm,idx,cell):
    # cluster vertices by grid cell + coarse normal direction (keeps thin sheets two-sided)
    g=np.floor(pos/cell).astype(np.int64)
    d=np.argmax(np.abs(nrm),1)*2+(nrm[np.arange(len(nrm)),np.argmax(np.abs(nrm),1)]>0)
    key=((g[:,0]+50000)*200003+(g[:,1]+50000))*200003+(g[:,2]+50000)
    key=key*8+d
    uk,inv=np.unique(key,return_inverse=True)
    cnt=np.bincount(inv)
    newp=np.zeros((len(uk),3))
    for k in range(3): newp[:,k]=np.bincount(inv,pos[:,k])/cnt
    t=inv[idx]
    ok=(t[:,0]!=t[:,1])&(t[:,1]!=t[:,2])&(t[:,0]!=t[:,2])
    t=t[ok]
    # drop duplicate tris
    st=np.sort(t,1); _,ui=np.unique(st,axis=0,return_index=True); t=t[np.sort(ui)]
    used=np.unique(t); remap=-np.ones(len(newp),np.int64); remap[used]=np.arange(len(used))
    return newp[used], remap[t]

def normals(pos,idx):
    a,b,c=pos[idx[:,0]],pos[idx[:,1]],pos[idx[:,2]]
    fn=np.cross(b-a,c-a)
    n=np.zeros_like(pos)
    for k in range(3): np.add.at(n,idx[:,k],fn)
    l=np.linalg.norm(n,axis=1,keepdims=True); l[l==0]=1
    return n/l

def sub(pos,nrm,idx,mask):
    t=idx[mask]; used=np.unique(t); remap=-np.ones(len(pos),np.int64); remap[used]=np.arange(len(used))
    return pos[used].copy(),nrm[used].copy(),remap[t]

out=[]  # (name, kind, region, pos, idx)
spos,snrm,sidx=part(P['Skin'])
cen=spos[sidx].mean(1); cn=snrm[sidx].mean(1)

def skin_patch(mask, inset, groove=None):
    p,n,t=sub(spos,snrm,sidx,mask)
    off=np.full(len(p),inset)
    if groove is not None: off+=groove(p)
    p=p-n*off[:,None]
    return p,t

def clamp_patch(vmask_fn, clamp_fn, extra_tri=None, inset=0.005, groove=None):
    vin=vmask_fn(spos)
    tm=vin[sidx].any(1)
    if extra_tri is not None: tm&=extra_tri
    p,n,t=sub(spos,snrm,sidx,tm)
    p=clamp_fn(p)
    off=np.full(len(p),inset)
    if groove is not None: off+=groove(p)
    return p-n*off[:,None],t

def rect_half(y): return np.interp(y,[0.955,1.0,1.1,1.25],[0.03,0.05,0.072,0.085])
RA_Y=(0.958,1.252)
for side,sg in (('right',-1),('left',1)):
    def vm(P,sg=sg):
        x=P[:,0]*sg; y=P[:,1]
        return (P[:,2]>0.02)&(x>0.002)&(x<rect_half(y))&(y>RA_Y[0])&(y<RA_Y[1])
    def cl(P,sg=sg):
        P=P.copy(); x=P[:,0]*sg; y=np.clip(P[:,1],*RA_Y); x=np.clip(x,0.0025,rect_half(y)); P[:,0]=x*sg; P[:,1]=y; return P
    def groove(P):
        g=np.zeros(len(P)); yy=P[:,1]; xx=np.abs(P[:,0])
        for yl in (1.075,1.145,1.205): g+=0.0025*np.exp(-((yy-yl)/0.007)**2)
        g+=0.003*np.exp(-(xx/0.007)**2)
        return g
    p,t=clamp_patch(vm,cl,extra_tri=(cn[:,2]>0.3),inset=0.0035,groove=groove)
    out.append((f'{side.capitalize()} rectus abdominis','patch','abs',p,t))

def lat_top(x): return np.minimum(1.205+x*0.95,1.335)
def lat_med(y): return np.where(y<1.13,0.03+(1.13-y)*0.55,0.006)
for side,sg in (('right',-1),('left',1)):
    def vm(P,sg=sg):
        x=P[:,0]*sg; y=P[:,1]; z=P[:,2]
        return (z<-0.03+np.clip(y-1.0,0,None)*0.25)&(x>lat_med(y))&(x<0.152)&(y>0.99)&(y<lat_top(x))
    def cl(P,sg=sg):
        P=P.copy(); x=P[:,0]*sg; y=P[:,1]
        y=np.clip(y,0.99,None); x=np.clip(x,lat_med(y),0.152); y=np.minimum(y,lat_top(x))
        P[:,0]=x*sg; P[:,1]=y; return P
    p,t=clamp_patch(vm,cl,extra_tri=(cen[:,2]<0.0)&(cn[:,2]<0.3),inset=0.0055)
    out.append((f'{side.capitalize()} latissimus dorsi','patch','lats',p,t))

nm=0
for p in man['parts']:
    name,sys_=p[0],p[1]
    if sys_=='muscle':
        if re.search(DROP,name.lower()): continue
        pos,n,idx=part(p)
        if 'external oblique' in name.lower():
            c=pos[idx].mean(1)
            keep=~((np.abs(c[:,0])<rect_half(c[:,1])+0.004)&(c[:,2]>0.02)&(c[:,1]>RA_Y[0]-0.01)&(c[:,1]<RA_Y[1]))
            pos,n,idx=sub(pos,n,idx,keep)
        out.append((name,'muscle',region(name),pos,idx))
    elif sys_=='bone':
        if re.search(r'tooth|malleus|incus|stapes|hyoid|cartilage',name.lower()): continue
        pos,n,idx=part(p)
        out.append((name,'bone','bone',pos,idx))

cellM=float(sys.argv[1]) if len(sys.argv)>1 else 0.003
cellB=float(sys.argv[2]) if len(sys.argv)>2 else 0.004
# Pack: per part u16 quantized positions, i8 normals, u16/u32 indices (4-byte aligned)
blob=bytearray(); parts=[]; TV=TT=0
for name,kind,reg,pos,idx in out:
    nr=normals(pos,idx)
    if kind!='patch': pos,idx=decimate(pos,nr,idx,cellM if kind=='muscle' else cellB)
    kind='muscle' if kind=='patch' else kind
    if len(idx)<4: continue
    nr=normals(pos,idx)
    lo=pos.min(0); hi=pos.max(0); span=np.where(hi-lo>0,hi-lo,1)
    q=np.round((pos-lo)/span*65535).astype('<u2')
    off=len(blob); blob+=q.tobytes(); blob+=np.round(nr*127).astype('i1').tobytes()
    while len(blob)%4: blob.append(0)
    blob+=idx.astype('<u2' if len(pos)<65536 else '<u4').tobytes()
    while len(blob)%4: blob.append(0)
    parts.append([name,kind,reg,off,len(pos),idx.size,[round(v,5) for v in lo],[round(v,5) for v in hi]])
    TV+=len(pos); TT+=len(idx)
hdr=json.dumps({'v':1,'credit':'BodyParts3D © The Database Center for Life Science (DBCLS), CC BY 4.0','parts':parts},separators=(',',':')).encode()
while (len(hdr)+8)%4: hdr+=b' '
data=b'BF3D'+struct.pack('<I',len(hdr))+hdr+bytes(blob)
gz=gzip.compress(data,9)
open('/home/claude/asset3d/body3d.bin.gz','wb').write(gz)
open('/home/claude/asset3d/body3d.bin','wb').write(data)
import collections
print('parts',len(parts),'verts',TV,'tris',TT,'raw',len(data),'gz',len(gz))
print(collections.Counter(p[2] for p in parts))
