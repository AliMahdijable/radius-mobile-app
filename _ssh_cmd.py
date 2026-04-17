import paramiko, sys, os
ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect('162.19.235.103', port=222, username='ali', password='ali144pq', timeout=10)
cmd = sys.argv[1] if len(sys.argv) > 1 else 'ls'
stdin, stdout, stderr = ssh.exec_command(cmd)
out = stdout.read().decode('utf-8', errors='replace')
err = stderr.read().decode('utf-8', errors='replace')
sys.stdout.buffer.write(out.encode('utf-8'))
if err:
    sys.stdout.buffer.write(b'\nSTDERR: ')
    sys.stdout.buffer.write(err.encode('utf-8'))
ssh.close()
