"""No robot/network IO: exact completion fences and command sequencing."""
import asyncio
import copy
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
P = ROOT / 'ha-components/custom_components/ix_roborock_sequence/sequence.py'
spec = importlib.util.spec_from_file_location('ix_sequence_test', P)
engine = importlib.util.module_from_spec(spec);spec.loader.exec_module(engine)

def record(begin=1001, **kw):
    return {'begin':begin,'end':begin+50 if begin is not None else None,'complete':1,'error':0,'clean_type':1,'start_type':2,'finish_reason':52,'map_flag':0,**kw}

def snapshot():
    return {'available':True,'state':'charging','in_cleaning':0,'in_returning':0,'error':0,'battery':97,
            'map':0,'mode':'custom','mop_ready':True,'record':record(900),
            'preferences':{'fan_speed':'custom','mop_intensity':'custom','mop_mode':'custom'}}

class CompletionTests(unittest.TestCase):
    def test_only_new_successful_whole_home_record(self):
        self.assertTrue(engine.completed(record(),900,1000,0))
        for field,values in {'begin':[900,969,1031,None], 'end':[1000,None], 'complete':[0,None],
                'error':[1,None], 'clean_type':[2,3,None], 'finish_reason':[21,24,32,61,None], 'map_flag':[1], 'start_type':[1,3,None]}.items():
            for value in values:
                with self.subTest(field=field,value=value):
                    self.assertFalse(engine.completed(record(**{field:value}),900,1000,0))
        for reason in engine.FINISHED:self.assertTrue(engine.completed(record(finish_reason=reason),900,1000,0))
    def test_readiness_is_read_only_and_fail_closed(self):
        for key,values in {'available':[False], 'state':['cleaning','paused','idle','washing_the_mop'],
                'in_cleaning':[1,2,None], 'in_returning':[1,None], 'error':[1,None],
                'battery':[49], 'map':[None], 'mop_ready':[False]}.items():
            for value in values:
                s=snapshot();s[key]=value
                with self.subTest(key=key,value=value),self.assertRaises(engine.SequenceError):
                    engine.Runner(lambda:s,None,None).ready()

class RuntimeTests(unittest.IsolatedAsyncioTestCase):
    async def exercise(self, fault=None):
        s=snapshot();calls=[];reports=[];clock=[0.0];starts=[0];ticks=[0]
        async def command(kind,value):
            calls.append((kind,copy.deepcopy(value)))
            if fault=='command' and kind=='start':raise RuntimeError('mock command failure')
            if kind=='mode':
                if fault!='ack':s['mode']=value
            if kind=='start':starts[0]+=1;ticks[0]=0;s.update(state='cleaning',in_cleaning=1)
        async def sleep(seconds):
            clock[0]+=seconds;ticks[0]+=1
            if fault=='pause':s['state']='paused';return
            if fault=='unavailable':s['available']=False;return
            if fault=='map':s['map']=1;return
            if fault=='mode':s['mode']='vac_and_mop';return
            if fault=='timeout':clock[0]+=15000;return
            if fault=='cancel':raise asyncio.CancelledError
            if fault=='recharge' and starts[0]==1 and ticks[0]<3:
                s.update(state='charging',in_cleaning=1,battery=15)
                # Neither a dock transition nor a previous successful record is completion.
                self.assertEqual(starts[0],1);return
            s.update(state='charging',in_cleaning=0,battery=80)
            if fault=='stale':
                clock[0]+=15000;return
            s['record']=record(1001+starts[0]*10)
            if fault=='incomplete':s['record']['complete']=0
            if fault=='partial':s['record']['clean_type']=3
            if fault=='manual_cancel':s['record']['finish_reason']=21
            if fault=='water':s['mop_ready']=False
        r=engine.Runner(lambda:copy.deepcopy(s),command,lambda p,m:reports.append((p,m)),
                        sleep=sleep,monotonic=lambda:clock[0],wall=lambda:1000)
        error=None
        try:await r.run()
        except (engine.SequenceError,RuntimeError,asyncio.CancelledError) as exc:error=exc
        return calls,reports,error
    async def test_successful_whole_passes_and_restore(self):
        calls,reports,error=await self.exercise();self.assertIsNone(error)
        self.assertEqual(calls,[('mode','vacuum'),('start',None),('mode','mop'),('start',None),('restore',snapshot()['preferences'])])
        self.assertEqual(reports[-1][0],'complete')
    async def test_recharge_does_not_advance_to_mop(self):
        calls,_,error=await self.exercise('recharge');self.assertIsNone(error)
        self.assertEqual([x for x in calls if x[0]=='mode'],[('mode','vacuum'),('mode','mop')])
    async def test_abort_cases_never_start_mop(self):
        for fault in ['pause','unavailable','map','mode','timeout','cancel','stale','incomplete','partial','manual_cancel','water','ack','command']:
            with self.subTest(fault=fault):
                calls,_,error=await self.exercise(fault);self.assertIsNotNone(error)
                self.assertNotIn(('mode','mop'),calls)
                self.assertLessEqual(calls.count(('start',None)),1)
    async def test_brief_interrupt_remains_latched(self):
        r=engine.Runner(snapshot,None,None);r.abort_reason='Paused briefly, then resumed'
        with self.assertRaises(engine.SequenceError):r.check()

if __name__=='__main__':unittest.main()
