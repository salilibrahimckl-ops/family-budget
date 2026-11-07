import json,base64,gzip,numpy as np,sys
D='/home/claude/salilibrahimckl-ops/orthoquest/anatomy/'
man=json.load(open(D+'anatomy2.json'))
names=['bones','vessels','muscles','detail']
_bufs={}
def buf(c):
    if c not in _bufs:
        _bufs[c]=gzip.decompress(base64.b64decode(open(D+names[c]+'.b64.txt').read()))
    return _bufs[c]
def part(p):
    name,sys_,c,off,v,ic,lo,hi=p
    b=buf(c)
    q=np.frombuffer(b,np.uint16,v*3,off).reshape(-1,3).astype(np.float64)
    lo=np.array(lo);hi=np.array(hi)
    pos=lo+q/65535*(hi-lo)
    noff=off+v*6
    n=np.frombuffer(b,np.int8,v*3,noff).reshape(-1,3).astype(np.float64)/127
    io=(noff+v*3+3)&~3
    idx=np.frombuffer(b,np.uint16 if v<65536 else np.uint32,ic,io).astype(np.int64).reshape(-1,3)
    return pos,n,idx
