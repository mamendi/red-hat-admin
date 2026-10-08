## Infor Lawson 10 LDAP Migration Runbook: IBM SDS to AD LDS

## Scope and environment values

This runbook moves the Lawson RM data store (users, actors, services, identities) from IBM Security Directory Server (SDS) to AD LDS, then repoints LSF 10 at it. SDS stays in place, unused, as the rollback path. Run it end to end in non-production first and time each phase.

Assumptions: end-user authentication runs through AD / AD FS or Infor OS and LDAP Bind to corporate AD, so only the RM store moves. Verify every step against Infor's procedure for your exact LSF patch level.

Fill in before starting:

| Value | Current (SDS) | Target (AD LDS) |
| --- | --- | --- |
| LDAP host (FQDN) | `<SDS_HOST>` | `<ADLDS_HOST>` |
| Port (LDAP / LDAPS) | `<389 / 636>` | `<PORT / SSLPORT>` |
| Base DN / partition | `<BASE_DN>` | `<BASE_DN>` (keep identical if possible) |
| Lawson admin bind DN | `<ADMIN_DN>` | `<ADMIN_DN>` |
| LDAPPREFIX (install.cfg) | `<PREFIX>` | `<PREFIX>` |
| AD LDS instance name | n/a | `<INSTANCE>` |
| AD LDS service account | n/a | `<DOMAIN>\svc_lawsonldap_dev` |
| AD LDS admin (Windows user) | n/a | `<DOMAIN>\<user>` |
| LDAP Bind service name | `<LDAPBIND_SVC>` | unchanged |
| Change window | `<DATE / TIME>` | |

## Service accounts

The AD LDS Windows service runs as the regular AD account `svc_lawsonldap_dev`. The Lawson-facing bind accounts stay separate, because their passwords are typed into ssoconfig and stored in install.cfg.

| Account | Purpose | Account used |
| --- | --- | --- |
| AD LDS service logon | Runs the AD LDS instance service | `svc_lawsonldap_dev` |
| AD LDS admin (Windows user) | Lawson install worksheet and `ldifde -b` imports | `<DOMAIN>\<user>` |
| Lawson LDAP admin bind DN | ssoconfig data store settings, install.cfg | `<ADMIN_DN>` |
| LDAP Bind service account | LSF binds to corporate AD for LDAP Bind | unchanged |

Service account setup for `svc_lawsonldap_dev`:

- [ ] Create `svc_lawsonldap_dev` in AD (or confirm it exists); deny interactive logon per your service account policy
- [ ] Store the password in the vault; record the rotation owner and schedule
- [ ] Set the AD LDS instance service logon to `<DOMAIN>\svc_lawsonldap_dev` (services.msc grants Log on as a service)
- [ ] Grant the account read on the LDAPS certificate's private key (the cert stays in the AD LDS service's Personal store)
- [ ] Restart the instance and confirm the event log shows a clean start
- [ ] Add a password-rotation step: update the service logon and restart the instance

Production will need its own account (for example, a `_prd` counterpart) rather than reusing the dev one.

## Phase 1: Plan and back up

Nothing here changes production; it captures every restore point before the freeze.

- [ ] Copy `LAWDIR/system/install.cfg` and record LDAP host, port, base DN, admin DN, `LDAPPREFIX`
- [ ] List all services: SSOP/SSOPV2, LDAP Bind, THICKCLIENT, DSP (LBI, MSCM, LSO), Landmark federation
- [ ] SDS native backup: `idsdbback -I <instance> -k <backup_dir>`
- [ ] SDS LDIF export of the Lawson suffix: `idsdb2ldif -I <instance> -s "<BASE_DN>" -o lawson_sds.ldif`
- [ ] ssoconfig export of ALL services + ALL identities: `ssoconfig -c` > 5 Manage Lawson Services > 6 Export service and identity info > All > ALL > `all_svc_ident.xml`
- [ ] Separate exports of SSOP and the LDAP Bind service (identities NONE) as small restore points
- [ ] Back up the WebSphere profile config (`backupConfig`)
- [ ] Record baseline counts: users, actors, identities per service, roles
- [ ] Announce the security change freeze in LSA from export to cutover

## Phase 2: Build and prepare AD LDS

The instance must have the Lawson schema and working LDAPS before any data lands.

- [ ] Install the AD LDS role on a supported, domain-joined Windows Server
- [ ] Create the instance (`<INSTANCE>`), ports `<PORT>` / `<SSLPORT>`, application partition = `<BASE_DN>`
- [ ] During setup import MS-InetOrgPerson.LDF and MS-User.LDF
- [ ] Set the service logon to svc_lawsonldap_dev (see Service accounts)
- [ ] Add the AD LDS admin Windows user to the instance Administrators role
- [ ] Create the Lawson admin bind DN in the partition and grant it full control
- [ ] Extend the schema with Infor's Lawson AD LDS schema LDIF: `ldifde -i -f <lawson_schema>.ldf -s <ADLDS_HOST>:<PORT> -j <log_dir> -c "CN=Configuration,DC=X" #configurationNamingContext`
- [ ] Import the LDAPS certificate (.pfx with private key) into the AD LDS service's Personal store; restart the instance
- [ ] Import the issuing CA chain into the WebSphere and Java truststores LSF uses
- [ ] Test: `ldp.exe` binds over LDAPS to `<ADLDS_HOST>:<SSLPORT>` as the Lawson admin DN
- [ ] Open firewall from LSF, WebSphere, and Landmark hosts to `<SSLPORT>`

## Phase 3: Clone the data

The import is done when object counts match the Phase 1 baseline and the ldifde log shows no unexplained rejects.

- [ ] Copy `lawson_sds.ldif` to a working file; never edit the original
- [ ] Strip SDS operational attributes: `ibm-entryUUID`, `creatorsName`, `modifiersName`, `createTimestamp`, `modifyTimestamp`, `aclEntry`, `aclPropagate`, `entryOwner`, `ibm-*`
- [ ] Remove or remap attributes and object classes the AD LDS schema doesn't define
- [ ] Drop `userPassword` hashes; list any RM-local accounts that will need `unicodePwd` set over LDAPS afterward
- [ ] Rewrite the DN suffix if it changed; confirm `LDAPPREFIX` matches install.cfg
- [ ] Sort entries parent before child
- [ ] Dry run against a scratch partition, then import for real:

```
ldifde -k -b <ADLDS_ADMIN> <DOMAIN> * -s <ADLDS_HOST> -t <PORT> -i -f lawson_adlds.ldif -v -j <log_dir>
```

- [ ] Review `ldif.err` and `ldif.log`; fix each reject and re-run (`-k` skips existing entries)
- [ ] Reconcile counts against the baseline: users, actors, identities per service, roles
- [ ] Spot-check 5 complex actors (multiple roles, custom attributes) in LSA view after Phase 4

## Phase 4: Repoint LSF and reload services

This is the cutover: after step 1, LSF reads and writes AD LDS only.

- [ ] Stop Lawson users from logging in (maintenance page or WebSphere app stop)
- [ ] `ssoconfig -c` > Change Lawson authentication data store settings: provider URL `ldaps://<ADLDS_HOST>:<SSLPORT>`, bind DN, password (twice)
- [ ] Smoke test: `lsconfig -l` returns data
- [ ] Update `LAWDIR/system/install.cfg` with the new LDAP host, port, DN so patches and CTPs don't revert to SDS
- [ ] Reload missing services or identities if needed: `ssoconfig -l <password> all_svc_ident.xml` (lower-case L)
- [ ] Export the LDAP Bind service and confirm its provider URL still points to corporate AD over LDAPS
- [ ] Update WebSphere user registry if it references SDS; restart the deployment manager and nodes
- [ ] Update Landmark federation settings if Landmark is federated with LSF
- [ ] Restart LSF/LATM services and WebSphere application servers

## Phase 5: Validate and cut over

Go-live requires every row to pass; any failure goes to Rollback if it can't be fixed inside the window.

| Test | How | Expected | Result |
| --- | --- | --- | --- |
| Portal / Ming.le login | Sign in through AD FS or Infor OS as a normal user | Lands on home page | |
| LSA lookups | Open 5 users and actors from the spot-check list | Roles and attributes match SDS | |
| Add-ins / thick client | Log in via LDAP Bind | Login succeeds | |
| IPA flows into LSF | Run a flow that does DME or file access | Completes | |
| MSCM handheld | Log in on a device | Login succeeds | |
| LBI / DSP apps | Open a dashboard | Loads with user's security | |
| Batch jobs | Run a job under a service identity | Completes | |
| New user add | Create and delete a test user in LSA | Writes to AD LDS | |
| LDAPS only | Confirm no LSF traffic on port 389 (netstat / AD LDS logs) | 636 only | |

- [ ] Lift the security change freeze
- [ ] Keep SDS running but unused for at least one full business cycle (one payroll run)
- [ ] Update monitoring to watch AD LDS instead of SDS
- [ ] Decommission SDS after sign-off

## Rollback

Rollback is a repoint, not a restore, as long as SDS was left untouched; budget about 30 minutes.

1. Stop user access to Lawson.
2. `ssoconfig -c` > Change Lawson authentication data store settings back to the SDS values from the Scope table.
3. Restore the backed-up `install.cfg`.
4. Revert any WebSphere registry or Landmark federation changes made in Phase 4.
5. Restart LSF/LATM and WebSphere; run `lsconfig -l`.
6. Re-run the Phase 5 login tests against SDS.
7. Any security changes made in AD LDS after cutover must be re-entered in SDS by hand.

## Open items and sign-off

Confirm these with Infor (Concierge case or KB) before the production window.

- [ ] Infor's "Cloning LDAP Users and Services" procedure for your LSF patch level, compared with this runbook
- [ ] Location and version of the Lawson AD LDS schema LDIF
- [ ] Whether opaque-format identity exports reload cleanly after the data store changes
- [ ] Any Infor-supplied export/import utility that replaces the manual LDIF transform
- [ ] Change ticket, approvers, and rollback decision owner

## Sources

- [Infor LDAP installation values](https://docs.infor.com/lsf/10.0/en-us/lsfwinolh/lsfctig_windows/fuj1546281427614.html)
- [Infor: Importing LDAP data](https://docs.infor.com/lsf/10.0/en-us/lsfibmiolh/lsfgg_ibmi_websphere/eva1546264025807.html)
- [Infor: Export the LDAP Bind service](https://docs.infor.com/lsf/10.0/en-us/lsfwinolh/ldaps/dbq1585333412617.html)
- [Infor Lawson compatibility matrix](https://support.infor.com/espublic/DLSearch/28987/InforLawsonCompatibilityMatrix-UNIX-Windows-IBMi-Latest.pdf)
- [Nogalis: LDAP signing for Lawson](https://www.nogalis.com/2020/04/17/configuring-lawson-and-landmark-for-ldap-signing/)
