# HelloID-Conn-Prov-Target-Voskamp

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

<p align="center">
  <img src="https://cms.voskampgroep.nl/uploads/logo_beveiligingstechniek_e149303d9f_2cde17dc4c_361d47d7d9.svg" style="width: 50%; max-width: 500px;">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-Voskamp](#helloid-conn-prov-target-voskamp)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Supported features](#supported-features)
  - [Getting started](#getting-started)
    - [HelloID Icon URL](#helloid-icon-url)
    - [Requirements](#requirements)
      - [Creating the Base64 Key from the `PKCS #12` Certificate](#creating-the-base64-key-from-the-pkcs-12-certificate)
    - [Connection settings](#connection-settings)
    - [Correlation configuration](#correlation-configuration)
    - [Field mapping](#field-mapping)
    - [Account Reference](#account-reference)
  - [Remarks](#remarks)
    - [Network access](#network-access)
    - [API permission errors](#api-permission-errors)
  - [Development resources](#development-resources)
    - [API endpoints](#api-endpoints)
    - [API documentation](#api-documentation)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-Voskamp_ is a _target_ connector. _Voskamp_ provides a set of REST APIs that allow you to programmatically interact with its data.

## Supported features

The following features are available:

| Feature                                   | Supported | Actions                                            | Remarks |
| ----------------------------------------- | --------- | -------------------------------------------------- | ------- |
| **Account Lifecycle**                     | ✅         | Create, Correlate, Update, Enable, Disable, Delete |         |
| **Permissions**                           | ✅         | Retrieve, Grant, Revoke                            |         |
| **Resources**                             | ❌         | -                                                  |         |
| **Entitlement Import: Accounts**          | ✅         | -                                                  |         |
| **Entitlement Import: Permissions**       | ✅         | Roles permissions                                  |         |
| **Governance Reconciliation Resolutions** | ✅         | -                                                  |         |



## Getting started

### HelloID Icon URL
URL of the icon used for the HelloID Provisioning target system.
```
https://raw.githubusercontent.com/Tools4everBV/HelloID-Conn-Prov-Target-Voskamp/refs/heads/main/Icon.png
```

### Requirements
- **Client certificate**: Obtain the PFX client certificate and password required for mutual TLS (mTLS).
- **API key**: Obtain an API key with permission to read and modify users, roles, and authorizations.
- **API URL**: Confirm the base URL for the tenant, for example `https://<tenant>.entryx.nl`.
- **Base64 Key**: Generate the base64-encoded key for the `PKCS #12` certificate.

#### Creating the Base64 Key from the `PKCS #12` Certificate

Use the following PowerShell script to create the base64-encoded key:

```powershell
$p12CertificatePath = 'C:\example\example.pfx'
[System.Convert]::ToBase64String((Get-Content $p12CertificatePath -AsByteStream))
```


### Connection settings

The following settings are required to connect to the API.

| Setting              | Description                                                        | Mandatory |
| -------------------- | ------------------------------------------------------------------ | --------- |
| P12CertificateBase64 | Base64-encoded PFX client certificate used for mTLS                | Yes       |
| certificatePassword  | Password for the PFX client certificate                            | Yes       |
| apiKey               | API key sent as a Bearer token                                     | Yes       |
| BaseUrl              | Base URL of the Voskamp API, Example: `https://<tenant>.entryx.nl` | Yes       |

### Correlation configuration

The correlation configuration is used to specify which properties will be used to match an existing account within _Voskamp_ to a person in _HelloID_.

| Setting                   | Value                             |
| ------------------------- | --------------------------------- |
| Enable correlation        | `True`                            |
| Person correlation field  | `PersonContext.Person.ExternalId` |
| Account correlation field | `employee_number`                 |

> [!TIP]
> _For more information on correlation, please refer to our correlation [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems/correlation.html) pages_.

### Field mapping

The field mapping can be imported by using the _fieldMapping.json_ file.

### Account Reference

The account reference is populated with the `id` property from Voskamp.

## Remarks

### Network access
- The API must be reachable from HelloID and support the required HTTPS connection.
- If Cloudflare is used in front of the API, verify that the route supports the required client certificate (mTLS).


### API permission errors
- The Get user call returns a 403 with a JSON error: `You don't have permission to access this.`. The connector treats the account as unavailable in this case.

## Development resources

### API endpoints

The following endpoints are used by the connector

| Endpoint                     | HTTP Method        | Description                                          |
| ---------------------------- | ------------------ | ---------------------------------------------------- |
| `/items/users`               | GET, POST          | Import, create, and correlate users                  |
| `/items/users/{id}`          | GET, PATCH, DELETE | Retrieve, enable, disable, update, and delete a user |
| `/items/roles`               | GET                | Retrieve roles used to name permissions              |
| `/items/authorizations`      | GET, POST          | Retrieve and grant user group authorizations         |
| `/items/authorizations/{id}` | DELETE             | Revoke a specific user group authorization           |

### API documentation

No public API documentation is available.

## Getting help

> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
