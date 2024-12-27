#!/bin/bash

cat >/usr/local/bin/numlock <<'EOF'
#!/bin/bash

for tty in /dev/tty{1..6}
do
  /usr/bin/setleds -D +num < "$tty";
done
EOF
chmod +x /usr/local/bin/numlock

cat >/etc/systemd/system/numlock.service <<'EOF'
[Unit]
Description=numlock

[Service]
ExecStart=/usr/local/bin/numlock
StandardInput=tty
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl start numlock.service
systemctl enable numlock.service
