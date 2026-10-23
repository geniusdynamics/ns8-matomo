#
# Copyright (C) 2026 Nethesis S.r.l.
# SPDX-License-Identifier: GPL-3.0-or-later
#

"""Settings the module manages inside Matomo.

They are written to state/common.config.ini.php, which the app container
mounts read-only as config/common.config.ini.php. Matomo reads that file
before config/config.ini.php, so the values set in the Matomo UI still win.
The file carries the LDAP bind password and the smarthost password: it is
regenerated at every start, readable only inside the module (state/ is
private) and not part of the backup (etc/state-include.conf).
"""

import os

import ldapsettings

INI_PATH = "common.config.ini.php"
SMARTHOST_ENV = "smarthost.env"
# The ldapproxy of a user domain and a same-node LDAP server listen on the
# node loopback: the matomo pod uses slirp4netns with allow_host_loopback,
# where 10.0.2.2 is the host loopback.
HOST_LOOPBACK = "10.0.2.2"
# NS8 smarthost encryption -> Matomo [mail] encryption. "none" also stops
# PHPMailer from switching to STARTTLS on its own.
SMTP_ENCRYPTION = {"none": "none", "starttls": "tls", "tls": "ssl"}


def ini_value(value):
    """Quote a string like Matomo's IniWriter does."""
    if isinstance(value, bool):
        return "1" if value else "0"
    if isinstance(value, int):
        return str(value)
    value = str(value)
    if "\n" in value or "\r" in value:
        raise ValueError("line breaks are not allowed in INI values")
    # PHP's INI scanner expands ${VAR} inside double quotes: escape it, or a
    # password with "${" is silently changed or breaks the whole file
    escaped = value.replace("\\", "\\\\").replace('"', '\\"').replace("${", "\\${")
    return '"' + escaped + '"'


def ldap_filter_escape(value):
    """RFC 4515 escaping of a value inside an LDAP filter."""
    out = []
    for ch in value:
        if ch in '*()\\\0':
            out.append("\\%02x" % ord(ch))
        else:
            out.append(ch)
    return "".join(out)


def group_dn(conn):
    """The DN of the login group: a DN is used as is, a group name is looked
    up in the directory (Active Directory only, see validate)."""
    group = conn["group"]
    if not group or "=" in group:
        return group
    import ssl
    import ldap3
    host = conn["host"]
    # ldap3 does not check certificates unless told to: follow the module setting
    tls = ldap3.Tls(validate=ssl.CERT_REQUIRED if conn["tls_verify"] else ssl.CERT_NONE)
    # get_info=NONE: no anonymous schema read before the bind, which AD and
    # Samba refuse after StartTLS (operationsError 00002020)
    if conn["tls"] == "ssl":
        server = ldap3.Server(host, port=conn["port"], use_ssl=True, tls=tls,
                              get_info=ldap3.NONE, connect_timeout=5)
    else:
        server = ldap3.Server(host, port=conn["port"], tls=tls, get_info=ldap3.NONE, connect_timeout=5)
    ldapconn = ldap3.Connection(server, user=conn["bind_dn"], password=conn["bind_password"],
                                receive_timeout=10, raise_exceptions=True)
    if conn["tls"] == "starttls":
        ldapconn.start_tls()
    ldapconn.bind()
    try:
        ldapconn.search(conn["base_dn"],
                        "(&(objectClass=group)(sAMAccountName=%s))" % ldap_filter_escape(group),
                        attributes=[])
        if not ldapconn.entries:
            raise LookupError(f"group {group} not found")
        return ldapconn.entries[0].entry_dn
    finally:
        ldapconn.unbind()


def ldap_sections(conn):
    """[LoginLdap] and [LoginLdap_ns8] for the LoginLdap plugin."""
    ad = conn["schema"] == "ad"
    user_attribute = conn["user_attribute"] or ("sAMAccountName" if ad else "uid")
    host = conn["host"]
    if host in ("127.0.0.1", "localhost", "::1"):
        host = HOST_LOOPBACK
    scheme = "ldaps" if conn["tls"] == "ssl" else "ldap"
    user_filter = "(objectClass=user)" if ad else "(objectClass=posixAccount)"
    if conn["group"]:
        # LDAP_MATCHING_RULE_IN_CHAIN: members of nested groups count too
        user_filter = "(&%s(memberOf:1.2.840.113556.1.4.1941:=%s))" % (user_filter, ldap_filter_escape(group_dn(conn)))
    view_access = "all" if os.environ.get("LDAP_VIEW_ACCESS", "none") == "all" else ""
    # address of a user without a mail attribute (LoginLdap would use
    # @mydomain.com): the name of the user domain, if there is one
    email_suffix = "@" + os.environ["LDAP_DOMAIN"] if conn["source"] == "domain" and os.environ.get("LDAP_DOMAIN") else ""
    return [
        "[LoginLdap]",
        "use_ldap_for_authentication = 1",
        "synchronize_users_after_login = 1",
        "enable_synchronize_access_from_ldap = 0",
        "enable_password_confirmation = 1",
        f"new_user_default_sites_view_access = {ini_value(view_access)}",
        f"ldap_user_id_field = {ini_value(user_attribute)}",
        f"ldap_mail_field = {ini_value('mail')}",
        f"user_email_suffix = {ini_value(email_suffix)}",
        f"ldap_user_filter = {ini_value(user_filter)}",
        'required_member_of = ""',
        "append_user_email_suffix_to_username = 0",
        "use_webserver_auth = 0",
        "ldap_network_timeout = 10",
        "servers[] = ns8",
        "",
        "[LoginLdap_ns8]",
        f"hostname = {ini_value(scheme + '://' + host)}",
        f"port = {int(conn['port'])}",
        f"base_dn = {ini_value(conn['base_dn'])}",
        f"admin_user = {ini_value(conn['bind_dn'])}",
        f"admin_pass = {ini_value(conn['bind_password'])}",
        f"start_tls = {1 if conn['tls'] == 'starttls' else 0}",
        "",
    ]


def cluster_network():
    """The cluster VPN network (e.g. 10.5.4.0/24), or "" if unknown."""
    try:
        import agent
        return agent.redis_connect(use_replica=True).get("cluster/network") or ""
    except Exception:
        return ""


def noreply_address(host):
    """Sender of Matomo emails: noreply@ the domain of the Matomo host name
    (matomo.example.org -> example.org), which is far more likely to pass
    SPF than Matomo's default noreply@<host name>."""
    labels = host.split(".")
    domain = ".".join(labels[1:]) if len(labels) > 2 else host
    return "noreply@" + domain


def general_section():
    """[General]: client address behind Traefik and email sender."""
    lines = [
        "[General]",
        # Traefik terminates TLS and appends the client address
        "proxy_client_headers[] = HTTP_X_FORWARDED_FOR",
        "proxy_host_headers[] = HTTP_X_FORWARDED_HOST",
        "proxy_scheme_headers[] = HTTP_X_FORWARDED_PROTO",
        "proxy_ip_read_last_in_list = 1",
    ]
    # Published through the Traefik of another node, the Traefik of this
    # node trusts that gateway and appends its VPN address to
    # X-Forwarded-For: skip the cluster VPN, or every visitor would be
    # recorded with the address of the gateway node.
    network = cluster_network()
    if network:
        lines.append(f"proxy_ips[] = {ini_value(network)}")
    host = os.environ.get("TRAEFIK_HOST", "")
    if host:
        lines.append(f"noreply_email_address = {ini_value(noreply_address(host))}")
    return lines + [""]


def read_env_file(path):
    """KEY=VALUE lines of an env file written by the module."""
    values = {}
    try:
        with open(path) as fp:
            for line in fp:
                key, sep, value = line.rstrip("\n").partition("=")
                if sep:
                    values[key] = value
    except FileNotFoundError:
        pass
    return values


def mail_section(smtp):
    """[mail] from the cluster smarthost (bin/discover-smarthost), or no
    section at all when the smarthost is off."""
    if not smtp.get("SMTP_ENABLED") or not smtp.get("SMTP_HOST"):
        return []
    verify = 1 if smtp.get("SMTP_TLSVERIFY") else 0
    lines = [
        "[mail]",
        'transport = "smtp"',
        f"host = {ini_value(smtp['SMTP_HOST'])}",
        f"port = {int(smtp.get('SMTP_PORT') or 25)}",
        f"encryption = {ini_value(SMTP_ENCRYPTION.get(smtp.get('SMTP_ENCRYPTION', ''), ''))}",
        # A smarthost found automatically is usually the VPN address of the
        # mail server: its certificate names the host name, so the name
        # check can only pass when the cluster asks for verification
        f"ssl_verify_peer = {verify}",
        f"ssl_verify_peer_name = {verify}",
        f"ssl_disallow_self_signed = {verify}",
    ]
    if smtp.get("SMTP_USERNAME"):
        lines += [
            'type = "LOGIN"',
            f"username = {ini_value(smtp['SMTP_USERNAME'])}",
            f"password = {ini_value(smtp.get('SMTP_PASSWORD', ''))}",
        ]
    return lines + [""]


def render():
    """Return (ini text, environment lines for the app container)."""
    lines = [
        "; <?php exit; ?> DO NOT REMOVE THIS LINE",
        "; Generated by the NS8 module at every start. Do not edit:",
        "; change the settings from the NS8 UI.",
        "",
    ]
    lines += general_section()
    try:
        lines += mail_section(read_env_file(SMARTHOST_ENV))
    except ValueError as exc:
        import agent
        import sys
        print(agent.SD_WARNING + f"Email disabled, cannot use the smarthost settings: {exc}", file=sys.stderr)
    env = []
    conn = None
    if os.environ.get("LDAP_ENABLED") == "true":
        conn = ldapsettings.connection(active=True)
    if conn:
        try:
            lines += ldap_sections(conn)
        except Exception as exc:
            import agent
            import sys
            print(agent.SD_WARNING + f"LDAP login disabled, cannot prepare it: {exc}", file=sys.stderr)
            conn = None
    if conn and not conn["tls_verify"]:
        env.append("LDAPTLS_REQCERT=never")
    return "\n".join(lines) + "\n", env


def write(ini_path=INI_PATH, env_path="ldap.env"):
    text, env = render()
    old_umask = os.umask(0o077)
    try:
        for path, content in ((ini_path, text), (env_path, "\n".join(env) + "\n")):
            with open(path + ".tmp", "w") as fp:
                fp.write(content)
            # read by www-data inside the container, from a private directory
            os.chmod(path + ".tmp", 0o644)
            os.replace(path + ".tmp", path)
    finally:
        os.umask(old_umask)
