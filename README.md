# freebsd-jitsi-meet-setup
A shell script which helps you set up jitsi-meet on a FreeBSD host

## Prerequisites
- You've installed jitsi-meet, jitsi-videobridge, jicofo, prosody and a webserver (either nginx or apache24) from ports or packages (optionally they can be installed by the script).
- You've got a valid TLS server certificate and a private key for the server. The certificate has to be verified by clients' web browsers.

## Usage
- Clone this repository anywhere you want.
- Run 'setup.sh' just after installing the aforementioned ports or packages.
- The script takes three mandatory arguments:
  1. SERVER_FQDN - the server's resolvable domain name.
  2. SERVER_CERT_PATH - a full pathname of the server certificate.
  3. SERVER_KEY_PATH - a full pathname of the server private key.
- If you use apache24 instead of nginx, specify -a flag.
- If you want authentication for room creation, specify -r flag.
- If the server is behind a NAT, specify -n LOCAL:PUBLIC where LOCAL is a private IP address actually assigned to the server and PUBLIC is a public IP address to which the LOCAL address is translated by the NAT.

## Examples
- Nginx, no authentiation and no NAT
  ```shell
  # ./setup.sh jitsi.example.com /usr/local/etc/letsencrypt/live/jitsi.example.com/fullchain.pem /usr/local/etc/letsencrypt/live/jitsi.example.com/privkey.pem
  ```

- Apache24, no authentication and no NAT
  ```shell
  # ./setup.sh -a jitsi.example.com /usr/local/etc/letsencrypt/live/jitsi.example.com/fullchain.pem /usr/local/etc/letsencrypt/live/jitsi.example.com/privkey.pem
  ```

- Nginx, authentiation and no NAT
  ```shell
  # ./setup.sh -r jitsi.example.com /usr/local/etc/letsencrypt/live/jitsi.example.com/fullchain.pem /usr/local/etc/letsencrypt/live/jitsi.example.com/privkey.pem
  ```

- Nginx, no authentiation and NAT
  ```shell
  # ./setup.sh -n 192.168.10.5:10.1.1.5 jitsi.example.com /usr/local/etc/letsencrypt/live/jitsi.example.com/fullchain.pem /usr/local/etc/letsencrypt/live/jitsi.example.com/privkey.pem
  ```
