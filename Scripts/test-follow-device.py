import pathlib,subprocess,plistlib,time,json,sys
repo=pathlib.Path(__file__).resolve().parents[1]
root=repo/'.build/follow-real-probe'
out=pathlib.Path(sys.argv[1]).resolve()
out.mkdir(parents=True,exist_ok=True)
apps=[]
for i in (1,2):
 app=root/f'follow-probe-{i}/Reader{i}.app'
 (app/'Contents/MacOS').mkdir(parents=True,exist_ok=True)
 info={'CFBundleIdentifier':f'local.airtype.ReaderTest{i}','CFBundleName':f'Reader Test {i}','CFBundleExecutable':f'Reader{i}','CFBundlePackageType':'APPL'}
 (app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
 subprocess.run(['cp',str(repo/'.build/debug/vRemote'),str(app/f'Contents/MacOS/Reader{i}')],check=True)
 subprocess.run(['codesign','--force','--deep','--sign','-',str(app)],check=True,capture_output=True)
 apps.append(app)
logs=[];procs=[];results=[]
try:
 for i,app in enumerate(apps,1):
  log=(out/f'coreaudio-reader-{i}.log').open('w');logs.append(log)
  procs.append(subprocess.Popen([str(app/f'Contents/MacOS/Reader{i}'),'--microphone-reader-test'],stdout=log,stderr=log))
 time.sleep(2)
 raw=subprocess.check_output([str(repo/'.build/debug/vRemote'),'--microphone-readers-inspect'],text=True)
 rows=json.loads(raw);results.append({'stage':'two-readers','readers':rows})
 assert all(any(r['bundleID']==f'local.airtype.ReaderTest{i}' for r in rows) for i in (1,2)),rows
 allowed=json.loads(subprocess.check_output([str(repo/'.build/debug/vRemote'),'--microphone-readers-inspect','--allow-app='+str(apps[0])],text=True))
 results.append({'stage':'only-first-app-allowed','readers':allowed})
 assert len(allowed)==1 and allowed[0]['bundleID']=='local.airtype.ReaderTest1'
 procs[0].terminate();procs[0].wait(timeout=3);time.sleep(.5)
 rows=json.loads(subprocess.check_output([str(repo/'.build/debug/vRemote'),'--microphone-readers-inspect'],text=True))
 results.append({'stage':'one-reader','readers':rows})
 assert not any(r['bundleID']=='local.airtype.ReaderTest1' for r in rows)
 assert any(r['bundleID']=='local.airtype.ReaderTest2' for r in rows)
 allowed=json.loads(subprocess.check_output([str(repo/'.build/debug/vRemote'),'--microphone-readers-inspect','--allow-app='+str(apps[0])],text=True))
 results.append({'stage':'allowed-app-ended-unlisted-remains','readers':allowed})
 assert allowed==[]
 procs[1].terminate();procs[1].wait(timeout=3);time.sleep(.5)
 rows=json.loads(subprocess.check_output([str(repo/'.build/debug/vRemote'),'--microphone-readers-inspect'],text=True))
 results.append({'stage':'no-test-readers','readers':rows})
 assert not any(r['bundleID'].startswith('local.airtype.ReaderTest') for r in rows)
 print('PASS real CoreAudio two / one / zero independent input consumers')
finally:
 for p in procs:
  if p.poll() is None:p.terminate();p.wait(timeout=3)
 for log in logs:log.close()
 (out/'coreaudio-readers.json').write_text(json.dumps(results,ensure_ascii=False,indent=2))
