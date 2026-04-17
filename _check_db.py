import paramiko
ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect('162.19.235.103', port=222, username='ali', password='ali144pq', timeout=10)
cmd = "mysql -u root -pali144mm myservices_agent -e 'SELECT id, action_type, CAST(JSON_UNQUOTE(JSON_EXTRACT(action_data, \"$.amount\")) AS DECIMAL(18,2)) as json_amount, CAST(JSON_UNQUOTE(JSON_EXTRACT(action_data, \"$.price\")) AS DECIMAL(18,2)) as json_price FROM activity_logs WHERE id IN (76009, 76008, 76011);'"
stdin, stdout, stderr = ssh.exec_command(cmd)
out = stdout.read().decode('utf-8', errors='replace')
err = stderr.read().decode('utf-8', errors='replace')
import sys
sys.stdout.buffer.write((out if out else 'No output').encode('utf-8'))
sys.stdout.buffer.write(b'\n')
if err:
    sys.stdout.buffer.write(b'ERR: ')
    sys.stdout.buffer.write(err.encode('utf-8'))
ssh.close()
