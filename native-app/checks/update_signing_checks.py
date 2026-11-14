#!/usr/bin/env python3
"""Exercise the operator signer without reading production signing material."""
from pathlib import Path
import subprocess, tempfile, base64, os
root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as tmp:
 p=Path(tmp); tool=p/'signer'; key=p/'key'; message=p/'archive.zip'
 subprocess.run(['xcrun','swiftc',str(root/'script/update_signing.swift'),'-o',str(tool)],check=True)
 def run(*args,ok=True):
  result=subprocess.run([str(tool),*map(str,args)],capture_output=True,text=True)
  assert (result.returncode==0)==ok
  return result.stdout.strip()
 public=run('generate',key); assert len(base64.b64decode(public))==32
 assert key.stat().st_mode & 0o777 == 0o600
 assert run('public',key)==public
 run('generate',key,ok=False)
 message.write_bytes(b'actual signed fixture bytes')
 signature=run('sign',key,message); assert len(base64.b64decode(signature))==64
 verify=p/'verify.swift'
 verify.write_text('''import Foundation
import CryptoKit
let a=CommandLine.arguments
let key=try Curve25519.Signing.PublicKey(rawRepresentation:Data(base64Encoded:a[1])!)
let ok=key.isValidSignature(Data(base64Encoded:a[2])!,for:try Data(contentsOf:URL(fileURLWithPath:a[3])))
exit(ok ? 0 : 1)
''')
 subprocess.run(['swift',str(verify),public,signature,str(message)],check=True)
 message.write_bytes(b'tampered fixture')
 assert subprocess.run(['swift',str(verify),public,signature,str(message)]).returncode!=0
 link=p/'link'; link.symlink_to(key); run('public',link,ok=False)
 os.chmod(key,0o644); run('public',key,ok=False)
 print('PASS signer: key export, 0600, overwrite rejection, signature verification, tampering, symlink and permission rejection')
