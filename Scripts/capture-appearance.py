import argparse,json,os,pathlib,subprocess,time
parser=argparse.ArgumentParser(description='Capture real AirType views with isolated fixture data and no hardware connections.')
parser.add_argument('--app',required=True,help='Debug AirType.app bundle')
parser.add_argument('--output',required=True)
args=parser.parse_args()
out=pathlib.Path(args.output).resolve()
out.mkdir(parents=True,exist_ok=True)
app=pathlib.Path(args.app).resolve()/'Contents/MacOS/vRemote'
scenes=[('01-voice-light','audio-remote',[]),('02-beta-at-bottom','audio-remote',['--review-beta']),('03-voice-dark','audio-remote',['--review-dark']),('04-follow-system','mapping',['--review-system']),('05-charts-light','usage',[]),('06-charts-dark','usage',['--review-dark']),('07-microphone-off','keyboard-only',[])]
results=[]
for name,scene,flags in scenes:
    logpath=out/(name+'.log')
    shot=out/(name+'.png')
    if shot.exists(): shot.unlink()
    with logpath.open('w') as log:
        p=subprocess.Popen(['/usr/bin/sandbox-exec','-p','(version 1) (allow default) (deny network*)',str(app),'--p1-ui-review','--scene='+scene,'--review-output='+str(shot)]+flags,stdout=log,stderr=subprocess.STDOUT,env=dict(os.environ,NSUnbufferedIO='YES'))
        try:
            time.sleep(1.5)
            sockets=subprocess.run(['/usr/sbin/lsof','-nP','-a','-p',str(p.pid),'-i'],capture_output=True,text=True)
            exitcode=p.wait(timeout=12)
            if not shot.exists(): raise RuntimeError(logpath.read_text())
            results.append({'scene':scene,'flags':flags,'screenshot':shot.name,'pid':p.pid,'internetSockets':sockets.stdout.strip(),'exit':exitcode,'captureMethod':'native-view-bitmap' if 'native content bitmap' in logpath.read_text() else 'window-screencapture'})
            print(name,flush=True)
        finally:
            if p.poll() is None: p.terminate(); p.wait(timeout=3)
(out/'ui-results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2))
