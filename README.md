Configuring site to site VPN tunnel using StrongSwan
====================================================

Intended infrastructure
-----------------------

This tutorial is intended to connect a Scaleway VPC to an other subnet, either on-premise or in an other CSP. The installation steps are intended for ubuntu servers but can be adapted for other linux distributions.

To demonstrate the configuration, this network configuration is assumed:

```
===========[Scaleway VPC]==========                  ============[On Premise]============
           192.168.0.0/24                                       192.168.1.0/24
========[private network 1]===========               ==========[private subnet]==========
[test instance]      [vpn gw instance]--[public ip]  <-----[vpn client]        [test server]
x.x.x.x              192.168.0.1                           192.168.1.1         192.168.1.2
```

Demonstration Terraform Manifest
--------------------------------

The included Terraform manifest will create both Scaleway and On Premise site as VPC to help follow the tutorial. 

To use it follow these steps:

```
export SCW_ACCESS_KEY=<Scaleway API access key>
export SCW_SECRET_KEY=<Scaleway API secret key>
export SCW_DEFAULT_PROJECT_ID=<Associated project ID>
make # This will init, plan and apply terraform manifest
```

This manifest assume you have generated an rsa ssh key with no password and added it to your Scaleway console. This is not the way to do it in production.

Configuration steps
-------------------

Generate a Pre-Shared Key using openssl

```
openssl rand -base64 33
yn58RQF0y6DjRP8DlGbCJq_vPM7GNm4XE
```

On both the vpn gw instance and vpn client, activate ip forwarding, install StrongSwan:

```
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p
apt-get update && apt-get install strongswan -y
```

On the vpn gw instance configure Strongswan (left is the local server, right the remote):

```
cat /etc/ipsec.conf
# /etc/ipsec.conf - strongSwan IPsec configuration file

# basic configuration

config setup
              strictcrlpolicy=no
              uniqueids = yes
              charondebug = "all"

# Site to Site

conn A-to-B
              authby=secret
              left=%defaultroute
              leftid=<VPN GW public IP>
              leftsubnet=192.168.0.0/24
              leftauth=psk
              right=<on premise public IP>
              rightid=<on premise public IP>
              rightsubnet=192.168.1.0/24
              rightauth=psk
              keyexchange=ikev2
              keyingtries=%forever
              fragmentation=yes
              ike=aes192gcm16-aes128gcm16-prfsha256-ecp256-ecp521,aes192-sha256-modp3072
              esp=aes192gcm16-aes128gcm16-ecp256-modp3072,aes192-sha256-ecp256-modp3072
              dpdaction=restart
              auto=route

cat /etc/ipsec.secrets
# /etc/ipsec.secrets - This file holds shared secrets or RSA private keys for authentication.

<VPN GW public IP> : PSK "yn58RQF0y6DjRP8DlGbCJq_vPM7GNm4XE"
```

On the vpn client server configure Strongswan reversing left and right configuration:

```
cat /etc/ipsec.conf
# /etc/ipsec.conf - strongSwan IPsec configuration file

# basic configuration

config setup
              strictcrlpolicy=no
              uniqueids = yes
              charondebug = "all"

# Site to Site

conn B-to-A
              authby=secret
              left=%defaultroute
              leftid=<on premise public IP>
              leftsubnet=192.168.1.0/24
              leftauth=psk
              right=<VPN GW public IP>
              rightid=<VPN GW public IP>
              rightsubnet=192.168.0.0/24
              rightauth=psk
              keyexchange=ikev2
              keyingtries=%forever
              fragmentation=yes
              ike=aes192gcm16-aes128gcm16-prfsha256-ecp256-ecp521,aes192-sha256-modp3072
              esp=aes192gcm16-aes128gcm16-ecp256-modp3072,aes192-sha256-ecp256-modp3072
              dpdaction=restart
              auto=route

cat /etc/ipsec.secrets
# /etc/ipsec.secrets - This file holds shared secrets or RSA private keys for authentication.

<on premise public IP> : PSK "yn58RQF0y6DjRP8DlGbCJq_vPM7GNm4XE"
```

On both vpn gw instance and vpn client, restart StrongSwan:

```
systemctl restart strongswan-starter
```

Route propagation and testing
-----------------------------

To finish the configuration, a static route must be distributed in each subnet to use the server or client as a gw to the other subnet. On the VPC side, we are going to use a DHCP server with the option 121.

On the vpn gw instance, install dnsmasq, ignore errors due to systemd-resolved being up:

```
apt-get install dnsmasq -y
```

Configure and start dnsmasq as a DHCP server only, listening for queries on the private network nic:

```
cat /etc/dnsmasq.conf
interface=ens5
port=0 # disable DNS
dhcp-range=192.168.0.2,192.168.0.254,255.255.255.0,12h
dhcp-option=3,192.168.0.1
dhcp-option=121,192.168.1.0/24,192.168.0.1
log-facility=/var/log/dnsmasq.log
log-async
log-queries
log-dhcp
```

```
systemctl enable --now dnsmasq
```

On the test server, add the static route manually:

```
ip route add 192.168.0.0/24 via 192.168.1.1
```

If using the Terraform manifest, you can configure dnsmasq as above for the other subnet (instead of adding route manually):

```
cat /etc/dnsmasq.conf
interface=ens5
port=0 # disable DNS
dhcp-range=192.168.1.2,192.168.1.254,255.255.255.0,12h
dhcp-option=3,192.168.1.1
dhcp-option=121,192.168.0.0/24,192.168.1.1
log-facility=/var/log/dnsmasq.log
log-async
log-queries
log-dhcp
```

On the vpn gw instance, find the IP distributed to the test instance (result may differ of course):

```
grep DHCPACK /var/log/dnsmasq.log
Apr  6 23:34:14 dnsmasq-dhcp[5583]: 291339098 DHCPACK(ens5) 192.168.0.231 02:00:00:01:0c:b0 tf-srv-angry-visvesvaraya
```

On the test server, test the connection to the test instance:

```
ping 192.168.0.231
PING 192.168.0.231 (192.168.0.231) 56(84) bytes of data.
64 bytes from 192.168.0.231: icmp_seq=1 ttl=62 time=16.3 ms
64 bytes from 192.168.0.231: icmp_seq=2 ttl=62 time=3.24 ms
64 bytes from 192.168.0.231: icmp_seq=3 ttl=62 time=2.74 ms
```

Firewalling considerations
--------------------------

StrongSwan use standard ipsec port which are UDP 500 and 4500. Both the server and the client should open these port for UDP traffic.

Using statefull firewall may not be enough since some of them drop UDP traffic. If you used the Terraform manifest, the security group is accepting UDP 500 and 4500.

NAT considerations
------------------

In each configurations, left and right are set to ```%defaultroute``` to allow the discovery of the internal IP (NAT with Flexible IP). leftid and rightid are set to the facing public IP.
