Instructions
Please refer to the "CONFIGURABLE SECTION" of the script, where you can input all your VM configurations. The rest of the script should remain unchanged.

Before running our automated script, please ensure that you cleanly delete your existing Bind9 services using apt remove (including any bind9utils, dnsutils, etc. that you may have installed).

Once done, run the bind9-setup.sh installation script:
-	Ensure script has execute permissions
o	chmod +x bind9-setup.sh
-	Run the script
o	./bind9-setup.sh

After installation, please verify that your DNS server is active and that DNS resolution is functioning correctly:

-	Run sudo systemctl status bind9
o	Expected output: status should show active
-	Use dig @<your Debian/jumphost IP> api.<your cluster name>.<your base domain> +short
o	E.g. dig @48.64.210.22 api.kuanyong-ocp.testcluster.local +short
o	Expected output: The API VIP you have assigned, indicating successful forward DNS lookup.
-	Use dig @<your Debian/jumphost IP> -x <API VIP> +short
o	E.g. dig @48.64.210.22 -x 48.64.210.24 +short
o	Expected output: The host you have configured, indicating successful reverse lookup.

Once these steps are completed, proceed with the OpenShift cluster installation using the openshift-install CLI, following the usual steps we have been using. 

Also, ensure that all nameservers of your Master, Worker and Bootstrap nodes are pointing to your DNS Server’s IP address in the install-config.yaml file.
