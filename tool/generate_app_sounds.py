"""Generate original short UI effects; no external recordings or licenses."""
import math, random, struct, wave
from pathlib import Path
RATE = 22050
OUT = Path(__file__).resolve().parents[1] / 'assets/sounds'
OUT.mkdir(parents=True, exist_ok=True)
def write(name, duration, sample):
 values=[sample(i/RATE) for i in range(int(duration*RATE))]
 peak=max(abs(x) for x in values) or 1
 with wave.open(str(OUT/(name+'.wav')), 'wb') as wav:
  wav.setparams((1,2,RATE,0,'NONE','not compressed'))
  wav.writeframes(b''.join(struct.pack('<h',int(x/peak*22000)) for x in values))
rng=random.Random(20261122)
def sweep(t):
 return (rng.uniform(-1,1)*.42 + math.sin(2*math.pi*(1100*t-650*t*t))*.12)*math.sin(math.pi*t/.48)**2
write('cart_clear',.48,sweep)
def purchase(t):
 total=0
 for onset,freq in [(0,1320),(.12,1760),(.24,2640)]:
  d=t-onset
  if d>=0:total+=(math.sin(2*math.pi*freq*d)+.25*math.sin(2*math.pi*freq*2.73*d))*math.exp(-8*d)*min(d*400,1)
 return total*min((.85-t)*20,1)
write('purchase_complete',.85,purchase)
for name,freq in [('favorite_on',880),('favorite_off',440)]:
 write(name,.16,lambda t:math.sin(2*math.pi*freq*t)*math.sin(math.pi*t/.16)**2)
